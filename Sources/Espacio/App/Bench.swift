import Foundation

enum Bench {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--bench") else { return }
        let path = i + 1 < args.count ? args[i + 1] : "/"
        var opts = ScanOptions()
        if let t = ProcessInfo.processInfo.environment["ESPACIO_THREADS"], let n = Int(t) { opts.threads = n }
        let scanner = DiskScanner(options: opts)
        let sem = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var value: ScanResult? }
        let box = Box()
        scanner.start(root: path) { r in box.value = r; sem.signal() }
        sem.wait()
        guard let r = box.value else { exit(1) }
        print("root       \(path)")
        print("threads    \(opts.threads)")
        print("time       \(ByteFormat.duration(r.duration))")
        print("files      \(ByteFormat.count(r.fileCount))")
        print("dirs       \(ByteFormat.count(r.dirCount))")
        print("denied     \(ByteFormat.count(r.deniedCount))")
        print("bytes      \(ByteFormat.string(r.root.size))")
        print("nodes      \(ByteFormat.count(Int64(countNodes(r.root))))")
        print("--- top children")
        for c in r.root.sortedChildren().prefix(12) {
            print("  \(ByteFormat.string(c.size).padding(toLength: 12, withPad: " ", startingAt: 0)) \(c.displayName)")
        }
        print("--- top files")
        for f in r.topFiles.prefix(10) {
            print("  \(ByteFormat.string(f.size).padding(toLength: 12, withPad: " ", startingAt: 0)) \(f.path)")
        }
        exit(0)
    }

    private static func countNodes(_ n: FSNode) -> Int {
        var total = 1
        for c in n.children { total += countNodes(c) }
        return total
    }
}
