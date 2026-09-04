import Foundation
import Synchronization

/// Lock-protected bounded min-heap that keeps the K largest files seen so far.
/// Workers check the atomic threshold first so the lock is only taken when a
/// file could actually enter the heap — which is rare once the heap is full.
final class TopFiles: @unchecked Sendable {
    private let capacity: Int
    private var heap: [(size: Int64, node: FSNode)] = []
    private let lock = NSLock()
    private let threshold = Atomic<Int64>(0)

    init(capacity: Int) {
        self.capacity = capacity
        heap.reserveCapacity(capacity + 1)
    }

    @inline(__always)
    func offer(_ node: FSNode, size: Int64) {
        if size < threshold.load(ordering: .relaxed) { return }
        lock.lock()
        defer { lock.unlock() }
        if heap.count < capacity {
            heap.append((size, node))
            siftUp(heap.count - 1)
            if heap.count == capacity { threshold.store(heap[0].size, ordering: .relaxed) }
        } else if size > heap[0].size {
            heap[0] = (size, node)
            siftDown(0)
            threshold.store(heap[0].size, ordering: .relaxed)
        }
    }

    func snapshot() -> [FSNode] {
        lock.lock()
        defer { lock.unlock() }
        return heap.sorted { $0.size > $1.size }.map(\.node)
    }

    private func siftUp(_ i: Int) {
        var i = i
        while i > 0 {
            let p = (i - 1) / 2
            if heap[p].size <= heap[i].size { break }
            heap.swapAt(p, i)
            i = p
        }
    }

    private func siftDown(_ i: Int) {
        var i = i
        let n = heap.count
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < n && heap[l].size < heap[m].size { m = l }
            if r < n && heap[r].size < heap[m].size { m = r }
            if m == i { break }
            heap.swapAt(m, i)
            i = m
        }
    }
}
