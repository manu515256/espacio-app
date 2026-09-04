import Foundation
import Synchronization

public final class FSNode: @unchecked Sendable, Identifiable, Hashable {
    public enum Kind: UInt8 {
        case directory
        case file
        case bundle
        case aggregate
    }

    public let name: String
    public unowned let parent: FSNode?
    public let kind: Kind
    public let modified: Double
    private let _size: Atomic<Int64>
    private let _fileCount: Atomic<Int64>
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

    public var size: Int64 { _size.load(ordering: .relaxed) }
    public var fileCount: Int64 { _fileCount.load(ordering: .relaxed) }

    @inline(__always) func addSize(_ n: Int64) { _size.wrappingAdd(n, ordering: .relaxed) }
    @inline(__always) func addFiles(_ n: Int64) { _fileCount.wrappingAdd(n, ordering: .relaxed) }

    public var isDirectory: Bool { kind == .directory || kind == .bundle }
    public var isRoot: Bool { parent == nil }

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
            return n == 1 ? L("1 archivo pequeño") : L("%lld archivos pequeños", n)
        default:
            return isRoot ? (name == "/" ? "Macintosh HD" : (name as NSString).lastPathComponent) : name
        }
    }

    public var fileExtension: String {
        guard kind == .file, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    public func sortedChildren() -> [FSNode] {
        children.sorted { $0.size > $1.size }
    }

    public var ancestry: [FSNode] {
        var chain: [FSNode] = [self]
        var p = parent
        while let n = p { chain.append(n); p = n.parent }
        return chain.reversed()
    }

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
