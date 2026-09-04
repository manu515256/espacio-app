import AppKit
import CoreServices
import Foundation

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    let executableName: String?
    let version: String?
    let size: Int64
    let fileCount: Int64
    let lastUsed: Date?
    let node: FSNode
    /// Root of the scan that produced `node`; retained so the parent chain
    /// (needed for `node.path`) stays alive after discovery finishes.
    let treeRoot: FSNode

    var id: String { url.path }
    static func == (a: InstalledApp, b: InstalledApp) -> Bool { a.url == b.url }
    func hash(into h: inout Hasher) { h.combine(url) }

    var isRunning: Bool {
        guard let bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var isSelf: Bool { bundleID == Bundle.main.bundleIdentifier }

    var icon: NSImage {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 128, height: 128)
        return img
    }
}

struct Leftover: Identifiable, Hashable {
    enum Kind: String {
        case support = "Datos de la app"
        case cache = "Caché"
        case preferences = "Preferencias"
        case container = "Contenedor"
        case groupContainer = "Contenedor compartido"
        case savedState = "Estado guardado"
        case logs = "Registros"
        case webkit = "Datos web"
        case launchAgent = "Agente de inicio"
        case scripts = "Scripts"
        case cookies = "Cookies"
        case other = "Otro"
    }

    let url: URL
    let kind: Kind
    let size: Int64

    var id: String { url.path }
}

enum AppInventory {
    static var searchRoots: [String] {
        ["/Applications", NSHomeDirectory() + "/Applications"]
    }

    /// Scans the application folders and builds the inventory. Fast even with
    /// Xcode installed because it reuses the parallel engine.
    static func discover() async -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in searchRoots where FileManager.default.fileExists(atPath: root) {
            var opts = ScanOptions()
            opts.topFileCount = 1
            opts.skipPaths = []
            let result = await DiskScanner(options: opts).scan(root: root)
            collectBundles(in: result.root, depth: 0, treeRoot: result.root, into: &apps)
        }
        return apps.sorted { $0.size > $1.size }
    }

    private static func collectBundles(in node: FSNode, depth: Int, treeRoot: FSNode, into apps: inout [InstalledApp]) {
        for child in node.children {
            if child.kind == .bundle {
                if let app = makeApp(from: child, treeRoot: treeRoot) { apps.append(app) }
            } else if child.kind == .directory && depth < 1 {
                collectBundles(in: child, depth: depth + 1, treeRoot: treeRoot, into: &apps)
            }
        }
    }

    private static func makeApp(from node: FSNode, treeRoot: FSNode) -> InstalledApp? {
        let url = node.url
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        // Same name Finder shows (localized). Finder may keep the extension
        // when "show all filename extensions" is on, so strip it ourselves.
        var displayName = FileManager.default.displayName(atPath: url.path)
        if displayName.lowercased().hasSuffix(".app") { displayName.removeLast(4) }
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String)
        return InstalledApp(
            url: url,
            name: displayName,
            bundleID: bundle?.bundleIdentifier,
            executableName: info["CFBundleExecutable"] as? String,
            version: version,
            size: node.size,
            fileCount: node.fileCount,
            lastUsed: lastUsedDate(for: url, executable: info["CFBundleExecutable"] as? String),
            node: node,
            treeRoot: treeRoot)
    }

    /// Spotlight's last-used date when the index has it; otherwise the access
    /// time of the main executable, which the loader touches on every launch.
    private static func lastUsedDate(for url: URL, executable: String?) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date
        }
        guard let executable else { return nil }
        var st = stat()
        let path = url.appendingPathComponent("Contents/MacOS/\(executable)").path
        guard stat(path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(st.st_atimespec.tv_sec))
    }

    // MARK: Leftovers

    /// Files outside the bundle that belong to the app: containers, caches,
    /// preferences, saved state, logs… Matched by bundle id and by app name.
    static func leftovers(for app: InstalledApp) async -> [Leftover] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        var names = Set<String>()
        names.insert(app.name)
        names.insert(app.url.deletingPathExtension().lastPathComponent)
        if let exe = app.executableName { names.insert(exe) }
        let bundleID = app.bundleID

        var candidates: [(String, Leftover.Kind)] = []

        func add(_ path: String, _ kind: Leftover.Kind) {
            if fm.fileExists(atPath: path) { candidates.append((path, kind)) }
        }
        func addChildren(of dir: String, kind: Leftover.Kind, where predicate: (String) -> Bool) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for e in entries where predicate(e) { candidates.append((dir + "/" + e, kind)) }
        }

        let lowerNames = Set(names.map { $0.lowercased() })
        let nameMatch: (String) -> Bool = { lowerNames.contains($0.lowercased()) }
        let idMatch: (String) -> Bool = { entry in
            guard let bundleID else { return false }
            let e = entry.lowercased(), id = bundleID.lowercased()
            return e == id || e.hasPrefix(id + ".") || e.hasSuffix("." + id) || e.contains("." + id + ".")
        }

        for lib in [home + "/Library", "/Library"] {
            addChildren(of: lib + "/Application Support", kind: .support) { idMatch($0) || nameMatch($0) }
            addChildren(of: lib + "/Caches", kind: .cache) { idMatch($0) || nameMatch($0) }
            addChildren(of: lib + "/Preferences", kind: .preferences) { idMatch(($0 as NSString).deletingPathExtension) }
            addChildren(of: lib + "/Logs", kind: .logs) { idMatch($0) || nameMatch($0) }
            addChildren(of: lib + "/LaunchAgents", kind: .launchAgent) { idMatch(($0 as NSString).deletingPathExtension) }
        }
        addChildren(of: "/Library/LaunchDaemons", kind: .launchAgent) { idMatch(($0 as NSString).deletingPathExtension) }
        addChildren(of: home + "/Library/Containers", kind: .container) { idMatch($0) }
        addChildren(of: home + "/Library/Group Containers", kind: .groupContainer) { idMatch($0) }
        addChildren(of: home + "/Library/Saved Application State", kind: .savedState) { idMatch(($0 as NSString).deletingPathExtension) }
        addChildren(of: home + "/Library/WebKit", kind: .webkit) { idMatch($0) }
        addChildren(of: home + "/Library/HTTPStorages", kind: .webkit) { idMatch(($0 as NSString).deletingPathExtension) }
        addChildren(of: home + "/Library/Application Scripts", kind: .scripts) { idMatch($0) }
        addChildren(of: home + "/Library/Cookies", kind: .cookies) { idMatch(($0 as NSString).deletingPathExtension) }
        addChildren(of: home + "/Library/Preferences/ByHost", kind: .preferences) { entry in
            guard let bundleID else { return false }
            return entry.lowercased().hasPrefix(bundleID.lowercased() + ".")
        }

        // De-duplicate and never suggest something inside the bundle itself.
        var seen = Set<String>()
        var result: [Leftover] = []
        for (path, kind) in candidates where !seen.contains(path) && !path.hasPrefix(app.url.path) {
            seen.insert(path)
            let size = await DiskScanner.allocatedSize(of: path)
            result.append(Leftover(url: URL(fileURLWithPath: path), kind: kind, size: size))
        }
        return result.sorted { $0.size > $1.size }
    }
}

extension DiskScanner {
    /// Allocated size of a file or a whole directory tree, using the parallel engine.
    static func allocatedSize(of path: String) async -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            var st = stat()
            return stat(path, &st) == 0 ? Int64(st.st_blocks) * 512 : 0
        }
        var opts = ScanOptions()
        opts.threads = 4
        opts.topFileCount = 1
        opts.minFileSize = .max
        opts.skipPaths = []
        return await DiskScanner(options: opts).scan(root: path).root.size
    }
}
