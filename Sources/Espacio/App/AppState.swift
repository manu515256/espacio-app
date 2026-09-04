import AppKit
import Observation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview, apps, files, explorer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: L("Resumen")
        case .apps: L("Aplicaciones")
        case .files: L("Archivos grandes")
        case .explorer: L("Explorador")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "chart.pie.fill"
        case .apps: "square.grid.2x2.fill"
        case .files: "doc.text.magnifyingglass"
        case .explorer: "rectangle.3.group.fill"
        }
    }
}

struct VolumeInfo {
    let name: String
    let total: Int64
    let available: Int64
    let availableStrict: Int64
    var used: Int64 { max(total - available, 0) }
    var purgeable: Int64 { max(available - availableStrict, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct CategoryTotal: Identifiable {
    let category: FileCategory
    var bytes: Int64
    var id: FileCategory { category }
}

struct QuickWin: Identifiable {
    enum Action { case trash, emptyTrash, reveal }
    let id: String
    let title: String
    let hint: String
    let symbol: String
    let node: FSNode
    let action: Action
    var size: Int64 { node.size }
}

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable { case idle, scanning, done, cancelled }

    var phase: Phase = .idle
    var section: AppSection = .overview
    var language: AppLanguage = AppLanguage.current

    func setLanguage(_ lang: AppLanguage) {
        guard lang != language else { return }
        AppLanguage.current = lang
        language = lang
        refreshVolume()
    }
    var scanRoot = "/"
    var volume: VolumeInfo?

    var liveFiles: Int64 = 0
    var liveDirs: Int64 = 0
    var liveBytes: Int64 = 0
    var liveDenied: Int64 = 0
    var liveTop: [FSNode] = []

    var result: ScanResult?
    var topFiles: [FSNode] = []
    var categories: [CategoryTotal] = []
    var quickWins: [QuickWin] = []
    var explorerRoot: FSNode?
    var treeVersion = 0

    var apps: [InstalledApp] = []
    var appsLoading = false
    var selectedApp: InstalledApp?

    func showApp(at path: String) {
        guard let app = apps.first(where: { $0.url.path == path }) else { return }
        selectedApp = app
        section = .apps
    }

    var trashedBytes: Int64 = 0
    var failures: [TrashService.Failure] = []

    private var scanner: DiskScanner?
    private var appsTask: Task<Void, Never>?

    var root: FSNode? { result?.root }
    var isScanning: Bool { phase == .scanning }

    func bootstrap() {
        guard phase == .idle else { return }
        refreshVolume()
        loadApps()
        startScan()
    }

    func refreshVolume() {
        let url = URL(fileURLWithPath: scanRoot)
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return }
        volume = VolumeInfo(
            name: v.volumeName ?? L("Disco"),
            total: Int64(v.volumeTotalCapacity ?? 0),
            available: v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0),
            availableStrict: Int64(v.volumeAvailableCapacity ?? 0))
    }

    func loadApps() {
        appsTask?.cancel()
        appsLoading = true
        appsTask = Task {
            let found = await AppInventory.discover()
            guard !Task.isCancelled else { return }
            apps = found
            appsLoading = false
        }
    }

    func startScan(path: String? = nil) {
        if let path { scanRoot = path }
        scanner?.cancel()
        let scanner = DiskScanner()
        self.scanner = scanner
        phase = .scanning
        result = nil
        topFiles = []
        categories = []
        quickWins = []
        explorerRoot = nil
        liveFiles = 0; liveDirs = 0; liveBytes = 0; liveDenied = 0; liveTop = []
        refreshVolume()

        let rootPath = scanRoot
        Task {
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard let self, self.scanner === scanner else { return }
                    let p = scanner.progress
                    self.liveFiles = p.fileCount
                    self.liveDirs = p.dirCount
                    self.liveBytes = p.byteCount
                    self.liveDenied = p.deniedCount
                    self.liveTop = scanner.currentTopFiles(limit: 8)
                }
            }
            let r = await scanner.scan(root: rootPath)
            ticker.cancel()
            guard self.scanner === scanner else { return }
            self.finish(r)
        }
    }

    func cancelScan() {
        scanner?.cancel()
    }

    private func finish(_ r: ScanResult) {
        result = r
        topFiles = r.topFiles
        explorerRoot = r.root
        liveFiles = r.fileCount
        liveDirs = r.dirCount
        liveDenied = r.deniedCount
        liveBytes = r.root.size
        phase = r.wasCancelled ? .cancelled : .done
        refreshVolume()
        recomputeDerived()
    }

    private func recomputeDerived() {
        guard let root else { return }
        let version = treeVersion
        Task.detached(priority: .userInitiated) {
            let cats = CategoryTotals.compute(root: root)
            await MainActor.run {
                guard self.treeVersion == version, self.root === root else { return }
                self.categories = cats
            }
        }
        quickWins = QuickWins.build(root: root)
    }

    @discardableResult
    func trash(_ nodes: [FSNode]) async -> [TrashService.Failure] {
        let unique = Array(Set(nodes))
        var sizes: [String: Int64] = [:]
        for n in unique { sizes[n.path] = n.size }
        return await trash(urls: unique.map(\.url), knownSizes: sizes)
    }

    @discardableResult
    func trash(urls: [URL], knownSizes: [String: Int64] = [:]) async -> [TrashService.Failure] {
        let fails = await TrashService.trash(urls)
        let failedPaths = Set(fails.map(\.url.path))
        let removedPaths = urls.map(\.path).filter { !failedPaths.contains($0) }
        applyRemoval(paths: removedPaths, knownSizes: knownSizes)
        failures = fails
        return fails
    }

    private func applyRemoval(paths: [String], knownSizes: [String: Int64]) {
        guard !paths.isEmpty else { return }

        var removedNodes: [FSNode] = []
        for p in paths {
            if let n = root?.find(path: p) {
                removedNodes.append(n)
                trashedBytes += n.size
            } else {
                trashedBytes += knownSizes[p] ?? 0
            }
        }
        let removedSet = Set(removedNodes)
        func isGone(_ n: FSNode) -> Bool { n.ancestry.contains(where: removedSet.contains) }
        if let er = explorerRoot, isGone(er) {
            explorerRoot = er.ancestry.reversed().first { !isGone($0) } ?? root
        }
        topFiles.removeAll(where: isGone)
        for n in removedNodes { n.parent?.removeChild(n) }

        let removedApps = apps.filter { app in
            paths.contains { app.url.path == $0 || app.url.path.hasPrefix($0 + "/") }
        }
        for app in removedApps { app.node.parent?.removeChild(app.node) }
        if !removedApps.isEmpty {
            let gone = Set(removedApps.map(\.url))
            apps.removeAll { gone.contains($0.url) }
            if let sel = selectedApp, gone.contains(sel.url) { selectedApp = nil }
        }

        treeVersion += 1
        refreshVolume()
        recomputeDerived()
    }

    func uninstall(_ app: InstalledApp, leftovers: [Leftover]) async -> [TrashService.Failure] {
        if let id = app.bundleID {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            for r in running { r.terminate() }
            if !running.isEmpty {
                for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) {
                    try? await Task.sleep(for: .milliseconds(150))
                }
                for r in running where !r.isTerminated { r.forceTerminate() }
            }
        }
        var sizes: [String: Int64] = [app.url.path: app.size]
        for l in leftovers { sizes[l.url.path] = l.size }
        return await trash(urls: [app.url] + leftovers.map(\.url), knownSizes: sizes)
    }

    func emptyTrash() {
        if let message = TrashService.emptyTrash() {
            failures = [TrashService.Failure(url: URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"), message: message)]
        } else {
            trashedBytes = 0
            refreshVolume()
        }
    }
}

extension DiskScanner {
    func currentTopFiles(limit: Int) -> [FSNode] {
        Array(topSnapshot().prefix(limit))
    }
}

enum CategoryTotals {
    static func compute(root: FSNode) -> [CategoryTotal] {
        var totals = [Int64](repeating: 0, count: FileCategory.allCases.count)
        let index = Dictionary(uniqueKeysWithValues: FileCategory.allCases.enumerated().map { ($1, $0) })
        let rootIsSlash = root.name == "/"
        func walk(_ node: FSNode, inherited: FileCategory?) {
            let underRoot = rootIsSlash && node === root
            for child in node.children {
                switch child.kind {
                case .file:
                    let c = FileCategory.forFile(child, inherited: inherited)
                    totals[index[c]!] += child.size
                case .aggregate:
                    totals[index[inherited ?? .small]!] += child.size
                case .bundle:
                    totals[index[.apps]!] += child.size
                case .directory:
                    walk(child, inherited: FileCategory.forDirectory(named: child.name, underRoot: underRoot) ?? inherited)
                }
            }
        }
        walk(root, inherited: nil)
        return FileCategory.allCases.enumerated()
            .map { CategoryTotal(category: $1, bytes: totals[$0]) }
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }
}

enum QuickWins {
    static func build(root: FSNode) -> [QuickWin] {
        let home = NSHomeDirectory()
        let specs: [(String, String, String, String, String, QuickWin.Action)] = [
            ("trash", home + "/.Trash", "Papelera", "Vaciarla libera el espacio de inmediato.", "trash.fill", .emptyTrash),
            ("docker", home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", "Disco de Docker",
             "Se achica con `docker system prune -a`. Borrar el archivo elimina todas las imágenes y contenedores.", "shippingbox.fill", .reveal),
            ("caches", home + "/Library/Caches", "Cachés de usuario", "Las apps las vuelven a generar. Cerrá las apps abiertas antes.", "clock.arrow.trianglehead.counterclockwise.rotate.90", .trash),
            ("derived", home + "/Library/Developer/Xcode/DerivedData", "DerivedData de Xcode", "Builds intermedios; Xcode los recompila.", "hammer.fill", .trash),
            ("devicesupport", home + "/Library/Developer/Xcode/iOS DeviceSupport", "Símbolos de dispositivos iOS", "Se vuelven a descargar al conectar un iPhone.", "iphone", .trash),
            ("archives", home + "/Library/Developer/Xcode/Archives", "Archives de Xcode", "Builds archivados para distribución.", "archivebox.fill", .reveal),
            ("simulators", home + "/Library/Developer/CoreSimulator/Devices", "Simuladores", "`xcrun simctl delete unavailable` borra los obsoletos.", "ipad.and.iphone", .reveal),
            ("simcaches", home + "/Library/Developer/CoreSimulator/Caches", "Caché de simuladores", "Se regenera sola.", "ipad.and.iphone", .trash),
            ("logs", home + "/Library/Logs", "Registros", "Logs de apps y diagnósticos.", "text.document.fill", .trash),
            ("npm", home + "/.npm/_cacache", "Caché de npm", "Equivale a `npm cache clean --force`.", "cube.box.fill", .trash),
            ("pnpm", home + "/Library/pnpm/store", "Store de pnpm", "Equivale a `pnpm store prune`.", "cube.box.fill", .reveal),
            ("yarn", home + "/Library/Caches/Yarn", "Caché de Yarn", "Se regenera al instalar.", "cube.box.fill", .trash),
            ("brew", home + "/Library/Caches/Homebrew", "Caché de Homebrew", "Equivale a `brew cleanup`.", "mug.fill", .trash),
            ("cargo", home + "/.cargo/registry", "Registro de Cargo", "Crates descargados; se vuelven a bajar.", "cube.box.fill", .reveal),
            ("gradle", home + "/.gradle/caches", "Caché de Gradle", "Se regenera al compilar.", "cube.box.fill", .trash),
            ("gomod", home + "/go/pkg/mod", "Módulos de Go", "Equivale a `go clean -modcache`.", "cube.box.fill", .reveal),
            ("android", home + "/.android/avd", "Emuladores Android", "Imágenes de dispositivos virtuales.", "ipad.and.iphone", .reveal),
            ("backups", home + "/Library/Application Support/MobileSync/Backup", "Backups de iPhone/iPad", "Gestionalos desde Finder › dispositivo.", "externaldrive.fill", .reveal),
            ("downloads", home + "/Downloads", "Descargas", "Vale la pena revisarla.", "arrow.down.circle.fill", .reveal),
            ("mailattach", home + "/Library/Mail", "Mail", "Adjuntos y buzones descargados.", "envelope.fill", .reveal),
        ]
        return specs.compactMap { id, path, title, hint, symbol, action in
            guard let node = root.find(path: path), node.size > 50 * 1024 * 1024 else { return nil }
            return QuickWin(id: id, title: title, hint: hint, symbol: symbol, node: node, action: action)
        }
    }
}
