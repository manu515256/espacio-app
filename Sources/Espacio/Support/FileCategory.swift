import SwiftUI

enum FileCategory: String, CaseIterable, Identifiable {
    case apps, video, images, audio, archives, documents, code, diskImages, caches, appData, system, other, small

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apps: "Aplicaciones"
        case .video: "Video"
        case .images: "Imágenes"
        case .audio: "Audio"
        case .archives: "Archivos comprimidos"
        case .documents: "Documentos"
        case .code: "Código y desarrollo"
        case .diskImages: "Máquinas virtuales e imágenes de disco"
        case .caches: "Cachés y temporales"
        case .appData: "Datos de apps"
        case .system: "Sistema"
        case .other: "Otros"
        case .small: "Archivos pequeños"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "app.fill"
        case .video: "film.fill"
        case .images: "photo.fill"
        case .audio: "waveform"
        case .archives: "archivebox.fill"
        case .documents: "doc.text.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .diskImages: "externaldrive.fill"
        case .caches: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .appData: "tray.full.fill"
        case .system: "gearshape.fill"
        case .other: "shippingbox.fill"
        case .small: "circle.grid.3x3.fill"
        }
    }

    var color: Color {
        switch self {
        case .apps: Color(hue: 0.58, saturation: 0.50, brightness: 0.74)       // steel blue
        case .video: Color(hue: 0.03, saturation: 0.55, brightness: 0.78)      // terracotta
        case .images: Color(hue: 0.11, saturation: 0.62, brightness: 0.82)     // ochre
        case .audio: Color(hue: 0.76, saturation: 0.30, brightness: 0.72)      // dusty violet
        case .archives: Color(hue: 0.08, saturation: 0.45, brightness: 0.72)   // tan
        case .documents: Color(hue: 0.55, saturation: 0.42, brightness: 0.78)  // sky
        case .code: Color(hue: 0.26, saturation: 0.40, brightness: 0.66)       // olive
        case .diskImages: Color(hue: 0.62, saturation: 0.38, brightness: 0.70) // slate indigo
        case .caches: Color(hue: 0.06, saturation: 0.65, brightness: 0.86)     // burnt orange
        case .appData: Color(hue: 0.47, saturation: 0.35, brightness: 0.68)    // sea teal
        case .system: Color(white: 0.48)
        case .other: Color(white: 0.60)
        case .small: Color(white: 0.36)
        }
    }

    private static let byExtension: [String: FileCategory] = {
        var m: [String: FileCategory] = [:]
        for e in ["mp4", "mov", "mkv", "avi", "m4v", "webm", "wmv", "flv", "mts", "ts", "prores"] { m[e] = .video }
        for e in ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "raw", "dng", "cr2", "nef", "arw", "psd", "ai", "svg", "webp", "bmp", "sketch", "fig"] { m[e] = .images }
        for e in ["mp3", "m4a", "wav", "flac", "aac", "aif", "aiff", "ogg", "opus", "alac", "wma"] { m[e] = .audio }
        for e in ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "pkg", "xip", "ipa", "apk", "jar", "war", "deb", "rpm"] { m[e] = .archives }
        for e in ["dmg", "iso", "img", "vmdk", "vdi", "qcow2", "vhd", "vhdx", "raw", "sparseimage", "sparsebundle", "utm", "vbox"] { m[e] = .diskImages }
        for e in ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "csv", "epub", "odt", "ods"] { m[e] = .documents }
        for e in ["js", "ts", "tsx", "jsx", "swift", "py", "rs", "go", "java", "kt", "c", "cpp", "cc", "h", "hpp", "m", "mm", "json", "yaml", "yml", "toml", "lock", "wasm", "o", "a", "dylib", "so", "framework", "xcarchive", "ipsw", "node", "pyc", "whl", "class"] { m[e] = .code }
        for e in ["cache", "tmp", "temp", "log", "crash", "ips"] { m[e] = .caches }
        return m
    }()

    /// Directory names that imply a category for everything beneath them.
    private static let byDirectoryName: [String: FileCategory] = [
        "node_modules": .code, ".git": .code, "DerivedData": .code, "CoreSimulator": .code, ".build": .code,
        "target": .code, "Pods": .code, ".cargo": .code, ".rustup": .code, ".gradle": .code, ".m2": .code,
        ".npm": .caches, ".yarn": .caches, "pnpm": .caches, "Caches": .caches, "Cache": .caches, "cache": .caches,
        "tmp": .caches, "Logs": .caches, "logs": .caches, "CrashReporter": .caches, "DiagnosticReports": .caches,
        ".Trash": .caches, "Trash": .caches,
        "Photos Library.photoslibrary": .images, "Music": .audio, "Movies": .video,
        "Developer": .code, "Application Support": .appData, "Containers": .appData, "Group Containers": .appData,
        "Mail": .appData, "Messages": .appData, "MobileSync": .appData,
    ]

    /// Names that only mean "system" when they sit directly under `/`.
    private static let rootLevelSystemNames: Set<String> = ["System", "usr", "private", "bin", "sbin", "Library", "opt", "cores", "etc", "var"]

    /// Category for a file given the category inherited from its directory chain.
    static func forFile(_ node: FSNode, inherited: FileCategory?) -> FileCategory {
        let ext = node.fileExtension
        if ext == "raw", node.name == "Docker.raw" { return .diskImages }
        if let c = byExtension[ext] { return c }
        return inherited ?? .other
    }

    static func forDirectory(named name: String, underRoot: Bool = false) -> FileCategory? {
        if name.hasSuffix(".app") { return .apps }
        if underRoot && rootLevelSystemNames.contains(name) { return .system }
        return byDirectoryName[name]
    }

    static func of(_ node: FSNode) -> FileCategory {
        switch node.kind {
        case .aggregate: return .small
        case .bundle: return .apps
        case .file:
            let ext = node.fileExtension
            if ext == "raw", node.name == "Docker.raw" { return .diskImages }
            if let c = byExtension[ext] { return c }
            return inheritedCategory(of: node) ?? .other
        case .directory:
            return inheritedCategory(of: node) ?? .other
        }
    }

    private static func inheritedCategory(of node: FSNode) -> FileCategory? {
        var p: FSNode? = node.kind == .file ? node.parent : node
        var found: FileCategory?
        while let n = p, !n.isRoot {
            if n.kind == .bundle { return .apps }
            let underRoot = n.parent?.isRoot == true && n.parent?.name == "/"
            if let c = forDirectory(named: n.name, underRoot: underRoot) { found = c; break }
            p = n.parent
        }
        return found
    }
}
