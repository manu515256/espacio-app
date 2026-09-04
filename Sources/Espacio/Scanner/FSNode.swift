import Foundation
import Synchronization

/// One node of the scanned tree. Directories, app bundles, big files and one
/// "aggregate" node per directory that sums every file below the size threshold.
///
/// Sizes are atomics because worker threads propagate allocated bytes up the
/// ancestor chain while other workers are still populating siblings.
public final class FSNode: @unchecked Sendable, Identifiable, Hashable {
    public enum Kind: UInt8 {
        case directory
        case file
        case bundle     // *.app — shown as a unit but still explorable
        case aggregate  // "N small files" pseudo node
    }

    public let name: String
    public unowned let parent: FSNode?
    public let kind: Kind
    /// Modification time (seconds since 1970). Only meaningful for files.
    public let modified: Double
    private let _size: Atomic<Int64>
    private let _fileCount: Atomic<Int64>
    /// Populated exactly once by the worker that scanned this directory.
    public var children: [FSNode] = []
    public var accessDenied = false

    public init(name: String, parent: FSNode?, kind: Kind, size: Int64 = 0, fileCount: Int64 = 0, modified: Double = 0) {
        self.name = name
        self.parent = parent
        self.kind = kind
        self.modified = modified
        _size = Atomic(size)
        _fileCount = Atomic(fileCount)
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public static func == (a: FSNode, b: FSNode) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    /// Allocated bytes on disk (recursive for directories).
    public var size: Int64 { _size.load(ordering: .relaxed) }
    /// Number of regular files (recursive for directories).
    public var fileCount: Int64 { _fileCount.load(ordering: .relaxed) }

    @inline(__always) func addSize(_ n: Int64) { _size.wrappingAdd(n, ordering: .relaxed) }
    @inline(__always) func addFiles(_ n: Int64) { _fileCount.wrappingAdd(n, ordering: .relaxed) }

    public var isDirectory: Bool { kind == .directory || kind == .bundle }
    public var isRoot: Bool { parent == nil }

    /// Absolute POSIX path. The root node's `name` is its full path.
    public var path: String {
        guard let parent else { return name }
        let p = parent.path
        return p == "/" ? "/" + name : p + "/" + name
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var depth: Int {
        var d = 0
        var p = parent
        while let n = p { d += 1; p = n.parent }
        return d
    }

    public var displayName: String {
        switch kind {
        case .aggregate:
            let n = fileCount
            return n == 1 ? "1 archivo pequeño" : "\(n) archivos pequeños"
        default:
            return isRoot ? (name == "/" ? "Macintosh HD" : (name as NSString).lastPathComponent) : name
        }
    }

    public var fileExtension: String {
        guard kind == .file, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    /// Children sorted by size, largest first.
    public func sortedChildren() -> [FSNode] {
        children.sorted { $0.size > $1.size }
    }

    /// Ancestors from root down to (and including) self.
    public var ancestry: [FSNode] {
        var chain: [FSNode] = [self]
        var p = parent
        while let n = p { chain.append(n); p = n.parent }
        return chain.reversed()
    }

    /// Detach `child` from the tree and subtract its size from every ancestor.
    /// Called from the main thread after a successful trash/delete.
    public func removeChild(_ child: FSNode) {
        guard let idx = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: idx)
        let bytes = child.size
        let files = child.fileCount > 0 ? child.fileCount : (child.kind == .file ? 1 : 0)
        var p: FSNode? = self
        while let n = p {
            n.addSize(-bytes)
            n.addFiles(-files)
            p = n.parent
        }
    }

    /// Find a descendant by absolute path (only works below this node).
    public func find(path target: String) -> FSNode? {
        let base = path
        guard target.hasPrefix(base) else { return nil }
        if target == base { return self }
        var rest = target.dropFirst(base.count)
        if rest.hasPrefix("/") { rest = rest.dropFirst() }
        var node = self
        for comp in rest.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == comp }) else { return nil }
            node = next
        }
        return node
    }
}
