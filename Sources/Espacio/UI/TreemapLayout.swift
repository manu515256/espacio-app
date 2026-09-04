import CoreGraphics

/// Squarified treemap (Bruls, Huizing & van Wijk). Weights must be sorted
/// descending; returns one rect per weight in the same order.
enum TreemapLayout {
    static func layout(weights: [Double], in bounds: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: weights.count)
        guard !weights.isEmpty, bounds.width > 0, bounds.height > 0 else { return rects }
        let total = weights.reduce(0, +)
        guard total > 0 else { return rects }
        let scale = bounds.width * bounds.height / total

        var remaining = bounds
        var i = 0
        while i < weights.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0.5 else { break }

            var end = i + 1
            var sum = weights[i] * scale
            var lo = sum, hi = sum
            var worst = ratio(sum: sum, lo: lo, hi: hi, side: side)
            while end < weights.count {
                let a = weights[end] * scale
                let s = sum + a
                let w = ratio(sum: s, lo: min(lo, a), hi: max(hi, a), side: side)
                if w <= worst {
                    sum = s; lo = min(lo, a); hi = max(hi, a); worst = w; end += 1
                } else {
                    break
                }
            }

            if remaining.width >= remaining.height {
                let stripW = CGFloat(sum) / remaining.height
                var y = remaining.minY
                for k in i..<end {
                    let h = CGFloat(weights[k] * scale) / stripW
                    rects[k] = CGRect(x: remaining.minX, y: y, width: stripW, height: h)
                    y += h
                }
                remaining.origin.x += stripW
                remaining.size.width -= stripW
            } else {
                let stripH = CGFloat(sum) / remaining.width
                var x = remaining.minX
                for k in i..<end {
                    let w = CGFloat(weights[k] * scale) / stripH
                    rects[k] = CGRect(x: x, y: remaining.minY, width: w, height: stripH)
                    x += w
                }
                remaining.origin.y += stripH
                remaining.size.height -= stripH
            }
            i = end
        }
        return rects
    }

    @inline(__always)
    private static func ratio(sum: Double, lo: Double, hi: Double, side: Double) -> Double {
        guard lo > 0, sum > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return max(w2 * hi / s2, s2 / (w2 * lo))
    }
}

struct TreemapItem {
    let node: FSNode
    let rect: CGRect
    let depth: Int
    let hue: Int
    /// Small per-item hue offset so siblings inside one folder stay in the
    /// same family but remain distinguishable.
    let shade: Int
    /// True for the "N more items" bucket that has no real node behind it.
    let synthetic: Bool
    /// Whether children were laid out inside (so the fill is drawn as a frame).
    let container: Bool
}

enum TreemapBuilder {
    static let headerHeight: CGFloat = 18

    static func build(root: FSNode, in bounds: CGRect) -> [TreemapItem] {
        var items: [TreemapItem] = []
        items.reserveCapacity(1200)
        place(node: root, rect: bounds, depth: 0, hueBase: nil, into: &items)
        return items
    }

    private static func place(node: FSNode, rect: CGRect, depth: Int, hueBase: Int?, into items: inout [TreemapItem]) {
        let kids = node.sortedChildren().filter { $0.size > 0 }
        guard !kids.isEmpty else { return }
        let limit = depth == 0 ? 500 : (depth == 1 ? 80 : 30)
        let shown = Array(kids.prefix(limit))
        let rest = kids.dropFirst(limit)
        var weights = shown.map { Double($0.size) }
        var restNode: FSNode?
        if !rest.isEmpty {
            let restSize = rest.reduce(Int64(0)) { $0 + $1.size }
            let n = FSNode(name: "\(rest.count) elementos más", parent: nil, kind: .aggregate, size: restSize, fileCount: Int64(rest.count))
            restNode = n
            weights.append(Double(restSize))
        }
        let gap: CGFloat = depth == 0 ? 3 : 2
        let rects = TreemapLayout.layout(weights: weights, in: rect)

        for (i, r0) in rects.enumerated() {
            let r = r0.insetBy(dx: gap / 2, dy: gap / 2)
            guard r.width >= 1, r.height >= 1 else { continue }
            let isRest = i >= shown.count
            let node = isRest ? restNode! : shown[i]
            let hue = hueBase ?? i
            let canNest = !isRest && node.isDirectory && depth < 2
                && r.width >= 56 && r.height >= 44 && r.width * r.height >= 5000
            items.append(TreemapItem(node: node, rect: r, depth: depth, hue: hue, shade: depth == 0 ? 0 : i,
                                     synthetic: isRest, container: canNest))
            if canNest {
                let inner = CGRect(x: r.minX + 3, y: r.minY + headerHeight, width: r.width - 6, height: r.height - headerHeight - 3)
                place(node: node, rect: inner, depth: depth + 1, hueBase: hue, into: &items)
            }
        }
    }
}
