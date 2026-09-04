import Foundation
import Darwin
import Synchronization

public struct ScanOptions: Sendable {
    public var minFileSize: Int64 = 64 * 1024
    public var threads: Int = max(4, min(16, ProcessInfo.processInfo.activeProcessorCount))
    public var topFileCount: Int = 2000
    public var skipPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/Network", "/.vol", "/home", "/net",
        "/private/var/vm", "/private/var/db/dyld", "/System/Library/Templates",
    ]
    public init() {}
}

public final class ScanProgress: @unchecked Sendable {
    let files = Atomic<Int64>(0)
    let dirs = Atomic<Int64>(0)
    let bytes = Atomic<Int64>(0)
    let denied = Atomic<Int64>(0)
    let cancelled = Atomic<Bool>(false)

    public var fileCount: Int64 { files.load(ordering: .relaxed) }
    public var dirCount: Int64 { dirs.load(ordering: .relaxed) }
    public var byteCount: Int64 { bytes.load(ordering: .relaxed) }
    public var deniedCount: Int64 { denied.load(ordering: .relaxed) }
    public func cancel() { cancelled.store(true, ordering: .relaxed) }
    public var isCancelled: Bool { cancelled.load(ordering: .relaxed) }
}

public struct ScanResult: @unchecked Sendable {
    public let root: FSNode
    public let topFiles: [FSNode]
    public let duration: TimeInterval
    public let fileCount: Int64
    public let dirCount: Int64
    public let deniedCount: Int64
    public let wasCancelled: Bool
}

private struct Job {
    let node: FSNode
    let path: String
}

private final class JobQueue: @unchecked Sendable {
    private var jobs: [Job] = []
    private let cond = NSCondition()
    private var busy = 0
    private var stopped = false

    func push(_ batch: [Job]) {
        guard !batch.isEmpty else { return }
        cond.lock()
        jobs.append(contentsOf: batch)
        if batch.count == 1 { cond.signal() } else { cond.broadcast() }
        cond.unlock()
    }

    func next() -> Job? {
        cond.lock()
        defer { cond.unlock() }
        while true {
            if stopped { return nil }
            if let job = jobs.popLast() {
                busy += 1
                return job
            }
            if busy == 0 {
                stopped = true
                cond.broadcast()
                return nil
            }
            cond.wait()
        }
    }

    func finished() {
        cond.lock()
        busy -= 1
        if busy == 0 && jobs.isEmpty { cond.broadcast() }
        cond.unlock()
    }

    func stop() {
        cond.lock()
        stopped = true
        cond.broadcast()
        cond.unlock()
    }
}

public final class DiskScanner: @unchecked Sendable {
    public let options: ScanOptions
    public let progress = ScanProgress()

    private let queue = JobQueue()
    private let top: TopFiles
    private var allowedDevices: [Int32] = []
    private let hardLinkLock = NSLock()
    private var seenHardLinks = Set<UInt64>()

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
        self.top = TopFiles(capacity: options.topFileCount)
    }

    public func cancel() {
        progress.cancel()
        queue.stop()
    }

    public func topSnapshot() -> [FSNode] { top.snapshot() }

    public func scan(root rootPath: String) async -> ScanResult {
        await withCheckedContinuation { cont in
            start(root: rootPath) { cont.resume(returning: $0) }
        }
    }

    public func start(root rootPath: String, completion: @escaping @Sendable (ScanResult) -> Void) {
        let started = DispatchTime.now()
        let normalized = rootPath == "/" ? "/" : (rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath)
        let root = FSNode(name: normalized, parent: nil, kind: normalized.hasSuffix(".app") ? .bundle : .directory)
        allowedDevices = Self.deviceSet(for: normalized)
        queue.push([Job(node: root, path: normalized)])

        let group = DispatchGroup()
        for i in 0..<options.threads {
            group.enter()
            let t = Thread { [self] in
                self.workerLoop()
                group.leave()
            }
            t.name = "espacio.scan.\(i)"
            t.qualityOfService = .userInitiated
            t.stackSize = 1 << 20
            t.start()
        }
        group.notify(queue: .global(qos: .userInitiated)) { [self] in
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
            completion(ScanResult(
                root: root,
                topFiles: top.snapshot(),
                duration: elapsed,
                fileCount: progress.fileCount,
                dirCount: progress.dirCount,
                deniedCount: progress.deniedCount,
                wasCancelled: progress.isCancelled))
        }
    }

    private static func deviceSet(for path: String) -> [Int32] {
        func dev(_ p: String) -> Int32? {
            var st = stat()
            return stat(p, &st) == 0 ? st.st_dev : nil
        }
        guard let rootDev = dev(path) else { return [] }
        var set = [rootDev]
        if let sys = dev("/"), let data = dev("/System/Volumes/Data"), rootDev == sys || rootDev == data {
            if !set.contains(sys) { set.append(sys) }
            if !set.contains(data) { set.append(data) }
        }
        return set
    }

    private static let bufferSize = 512 * 1024

    private static let commonAttrMask: attrgroup_t = {
        var m: UInt32 = UInt32(ATTR_CMN_RETURNED_ATTRS)
        m |= UInt32(ATTR_CMN_ERROR)
        m |= UInt32(ATTR_CMN_NAME)
        m |= UInt32(ATTR_CMN_DEVID)
        m |= UInt32(ATTR_CMN_OBJTYPE)
        m |= UInt32(ATTR_CMN_MODTIME)
        m |= UInt32(ATTR_CMN_FILEID)
        return attrgroup_t(m)
    }()

    private static let fileAttrMask: attrgroup_t = {
        var m: UInt32 = UInt32(ATTR_FILE_LINKCOUNT)
        m |= UInt32(ATTR_FILE_ALLOCSIZE)
        return attrgroup_t(m)
    }()

    private static let bulkOptions: UInt64 = UInt64(FSOPT_NOFOLLOW) | UInt64(FSOPT_PACK_INVAL_ATTRS)

    private func workerLoop() {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = Self.commonAttrMask
        attrs.fileattr = Self.fileAttrMask

        while var job = queue.next() {
            while true {
                let local = readDirectory(job, buffer: buffer, attrs: &attrs)
                guard let nextJob = local, !progress.isCancelled else { break }
                job = nextJob
            }
            queue.finished()
        }
    }

    private func readDirectory(_ job: Job, buffer: UnsafeMutableRawPointer, attrs: inout attrlist) -> Job? {
        let node = job.node
        let path = job.path
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == EACCES || errno == EPERM {
                node.accessDenied = true
                progress.denied.wrappingAdd(1, ordering: .relaxed)
            }
            return nil
        }
        defer { close(fd) }

        let minSize = options.minFileSize
        let isRootSlash = path == "/"
        var fileBytes: Int64 = 0
        var fileCount: Int64 = 0
        var smallBytes: Int64 = 0
        var smallCount: Int64 = 0
        var kids: [FSNode] = []
        var subJobs: [Job] = []

        while !progress.isCancelled {
            let count = getattrlistbulk(fd, &attrs, buffer, Self.bufferSize, Self.bulkOptions)
            if count <= 0 {
                if count < 0 && errno == EACCES {
                    node.accessDenied = true
                    progress.denied.wrappingAdd(1, ordering: .relaxed)
                }
                break
            }

            var p = buffer
            for _ in 0..<Int(count) {
                let entryStart = p
                let length = p.loadUnaligned(as: UInt32.self)
                p += 4
                let returned = p.loadUnaligned(as: attribute_set_t.self)
                p += MemoryLayout<attribute_set_t>.size
                defer { p = entryStart + Int(length) }

                var entryError: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                    entryError = p.loadUnaligned(as: UInt32.self); p += 4
                }
                var namePtr: UnsafePointer<CChar>? = nil
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = p.loadUnaligned(as: attrreference_t.self)
                    namePtr = UnsafeRawPointer(p + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                    p += MemoryLayout<attrreference_t>.size
                }
                var devid: Int32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                    devid = p.loadUnaligned(as: Int32.self); p += 4
                }
                var objType: UInt32 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    objType = p.loadUnaligned(as: UInt32.self); p += 4
                }
                var modified: Double = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    let ts = p.loadUnaligned(as: timespec.self)
                    modified = Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
                    p += MemoryLayout<timespec>.size
                }
                var fileID: UInt64 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                    fileID = p.loadUnaligned(as: UInt64.self); p += 8
                }
                var linkCount: UInt32 = 1
                if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                    linkCount = p.loadUnaligned(as: UInt32.self); p += 4
                }
                var allocated: Int64 = 0
                if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocated = p.loadUnaligned(as: Int64.self); p += 8
                }

                guard entryError == 0, let namePtr else { continue }

                switch objType {
                case 2:
                    if !allowedDevices.isEmpty && !allowedDevices.contains(devid) { continue }
                    let name = String(cString: namePtr)
                    let childPath = isRootSlash ? "/" + name : path + "/" + name
                    if !options.skipPaths.isEmpty && options.skipPaths.contains(childPath) { continue }
                    let kind: FSNode.Kind = name.hasSuffix(".app") ? .bundle : .directory
                    let child = FSNode(name: name, parent: node, kind: kind)
                    kids.append(child)
                    subJobs.append(Job(node: child, path: childPath))
                case 1:
                    if linkCount > 1 {
                        hardLinkLock.lock()
                        let inserted = seenHardLinks.insert(fileID).inserted
                        hardLinkLock.unlock()
                        if !inserted { continue }
                    }
                    fileBytes += allocated
                    fileCount += 1
                    if allocated >= minSize {
                        let child = FSNode(name: String(cString: namePtr), parent: node, kind: .file,
                                           size: allocated, fileCount: 1, modified: modified)
                        kids.append(child)
                        top.offer(child, size: allocated)
                    } else {
                        smallBytes += allocated
                        smallCount += 1
                    }
                default:
                    continue
                }
            }
        }

        if smallCount > 0 {
            kids.append(FSNode(name: "", parent: node, kind: .aggregate, size: smallBytes, fileCount: smallCount))
        }
        node.children = kids

        if fileBytes != 0 || fileCount != 0 {
            var cursor: FSNode? = node
            while let n = cursor {
                n.addSize(fileBytes)
                n.addFiles(fileCount)
                cursor = n.parent
            }
        }
        progress.bytes.wrappingAdd(fileBytes, ordering: .relaxed)
        progress.files.wrappingAdd(fileCount, ordering: .relaxed)
        progress.dirs.wrappingAdd(1, ordering: .relaxed)

        let keep = subJobs.popLast()
        queue.push(subJobs)
        return keep
    }
}
