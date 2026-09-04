import AppKit
import SwiftUI

struct TreemapView: View {
    let root: FSNode
    let version: Int
    @Binding var selected: FSNode?
    var onZoom: (FSNode) -> Void
    var onTrash: (FSNode) -> Void

    @Environment(AppState.self) private var state
    @State private var items: [TreemapItem] = []
    @State private var image: NSImage?
    @State private var builtFor: String = ""
    @State private var hoverPoint: CGPoint?
    @State private var hoveredItem: TreemapItem?

    private var hovered: FSNode? { hoveredItem?.node }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: size.width, height: size.height)
                }
                if let s = selected, let item = items.first(where: { $0.node === s }) {
                    highlight(item.rect, radius: item.depth == 0 ? 7 : 4, opacity: 0.95)
                }
                if let item = hoveredItem, item.node !== selected {
                    highlight(item.rect, radius: item.depth == 0 ? 7 : 4, opacity: 0.8)
                }
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            hoverPoint = p
                            let hit = hitTest(p)
                            if hit?.node !== hoveredItem?.node { hoveredItem = hit }
                        case .ended:
                            hoverPoint = nil; hoveredItem = nil
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard let hit = hitTest(value.location), !hit.synthetic else { return }
                        if hit.node.isDirectory {
                            onZoom(hit.node)
                        } else {
                            selected = hit.node
                        }
                    })
                    .contextMenu {
                        if let n = hovered, n.parent != nil {
                            Text(n.displayName)
                            Button(L("Mostrar en Finder"), systemImage: "finder") { TrashService.reveal(n.url) }
                            if n.kind == .bundle, state.apps.contains(where: { $0.url.path == n.path }) {
                                Button(L("Ver en Aplicaciones"), systemImage: "square.grid.2x2") { state.showApp(at: n.path) }
                            }
                            if n.isDirectory { Button(L("Abrir acá"), systemImage: "arrow.down.right.and.arrow.up.left") { onZoom(n) } }
                            Button(L("Copiar ruta"), systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(n.path, forType: .string)
                            }
                            Divider()
                            Button(L("Mover a la Papelera"), systemImage: "trash", role: .destructive) { onTrash(n) }
                        }
                    }

                if let p = hoverPoint, let item = hoveredItem {
                    tooltip(for: item, at: p, in: size)
                }
            }
            .onAppear { rebuild(size) }
            .onChange(of: size) { _, s in rebuild(s) }
            .onChange(of: root) { _, _ in rebuild(size) }
            .onChange(of: version) { _, _ in rebuild(size) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func highlight(_ r: CGRect, radius: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Color.white.opacity(opacity), lineWidth: 2)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
    }

    private func rebuild(_ size: CGSize) {
        let key = "\(root.id.hashValue)-\(Int(size.width))x\(Int(size.height))-\(version)"
        guard key != builtFor, size.width > 10, size.height > 10 else { return }
        builtFor = key
        items = TreemapBuilder.build(root: root, in: CGRect(origin: .zero, size: size))
        let scale = NSApp.keyWindow?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        image = TreemapRenderer.render(items: items, size: size, scale: scale)
        hoveredItem = nil
        Trace.log("treemap rebuilt root=\(root.displayName) items=\(items.count) size=\(Int(size.width))x\(Int(size.height)) scale=\(scale)")
    }

    private func hitTest(_ p: CGPoint) -> TreemapItem? {
        var best: TreemapItem?
        for item in items where item.rect.contains(p) {
            best = item
        }
        return best
    }

    @ViewBuilder
    private func tooltip(for item: TreemapItem, at p: CGPoint, in size: CGSize) -> some View {
        let n = item.node
        let pct = root.size > 0 ? Double(n.size) / Double(root.size) * 100 : 0
        VStack(alignment: .leading, spacing: 3) {
            Text(n.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            HStack(spacing: 6) {
                Text(ByteFormat.string(n.size)).font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                Text(String(format: "%.1f %%", locale: AppLanguage.current.locale, pct)).font(.caption).foregroundStyle(.secondary)
                if n.isDirectory { Text(L("· %@ archivos", ByteFormat.count(n.fileCount))).font(.caption).foregroundStyle(.secondary) }
            }
            if !item.synthetic {
                Text(n.prettyPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: 320, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .fixedSize()
        .offset(x: min(p.x + 14, size.width - 330), y: p.y + 18 > size.height - 70 ? p.y - 70 : p.y + 18)
        .allowsHitTesting(false)
    }
}

enum TreemapRenderer {
    private static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let sizeFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    static func render(items: [TreemapItem], size: CGSize, scale: CGFloat) -> NSImage? {
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard pw > 0, ph > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.current = flipped

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor.white.withAlphaComponent(0.92)]
        let sizeAttrs: [NSAttributedString.Key: Any] = [.font: sizeFont, .foregroundColor: NSColor.white.withAlphaComponent(0.85)]

        for item in items {
            let r = item.rect
            let radius: CGFloat = item.depth == 0 ? 7 : 4
            let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            let fill = item.container
                ? Palette.nsContainer(index: item.hue, depth: item.depth, kind: item.node.kind)
                : Palette.nsColor(index: item.hue, depth: item.depth, shade: item.shade, kind: item.node.kind)
            fill.setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.10).setStroke()
            path.lineWidth = item.container ? 1 : 0.8
            path.stroke()

            let labelH: CGFloat = item.container ? TreemapBuilder.headerHeight : r.height
            guard r.width >= 46, labelH >= 14 else { continue }
            let name = item.container && r.width >= 120
                ? "\(item.node.displayName)  ·  \(ByteFormat.string(item.node.size))"
                : item.node.displayName
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: r.insetBy(dx: 4, dy: 2)).addClip()
            let origin = CGPoint(x: r.minX + 6, y: r.minY + (item.container ? 2 : 5))
            (name as NSString).draw(at: origin, withAttributes: titleAttrs)
            if !item.container && r.height >= 34 {
                (ByteFormat.string(item.node.size) as NSString).draw(at: CGPoint(x: origin.x, y: origin.y + 15), withAttributes: sizeAttrs)
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
