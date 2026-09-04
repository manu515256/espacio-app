import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

/// Restrained dark palette: neutral graphite surfaces, one amber accent,
/// tomato for destructive actions, and earthy muted hues for data.
enum Theme {
    static let background = Color(red: 0.082, green: 0.082, blue: 0.088)
    static let backgroundTop = Color(red: 0.105, green: 0.105, blue: 0.112)
    static let card = Color.white.opacity(0.045)
    static let cardStroke = Color.white.opacity(0.075)
    static let tile = Color.white.opacity(0.035)
    static let track = Color.white.opacity(0.07)

    static let accent = Color(hue: 0.105, saturation: 0.72, brightness: 0.92)   // amber
    static let danger = Color(hue: 0.02, saturation: 0.70, brightness: 0.88)    // tomato
    static let ok = Color(hue: 0.33, saturation: 0.38, brightness: 0.70)        // muted green
    static let info = Color(hue: 0.58, saturation: 0.45, brightness: 0.74)      // steel blue
    static let muted = Color(white: 0.55)

    /// Ten muted, mutually distinguishable hues for the treemap (h, s, b).
    static let series: [(Double, Double, Double)] = [
        (0.58, 0.50, 0.72), // steel blue
        (0.11, 0.62, 0.80), // ochre
        (0.26, 0.40, 0.64), // olive
        (0.03, 0.55, 0.77), // terracotta
        (0.47, 0.35, 0.66), // sea teal
        (0.76, 0.30, 0.70), // dusty violet
        (0.08, 0.45, 0.72), // tan
        (0.60, 0.24, 0.66), // slate
        (0.93, 0.42, 0.66), // plum
        (0.55, 0.42, 0.78), // sky
    ]
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.backgroundTop, Theme.background], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Cards & typography

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.title3, design: .rounded, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SizeBar: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct CategoryChip: View {
    let category: FileCategory
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(category.color).frame(width: 7, height: 7)
            Text(category.label).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(category.color.opacity(0.13), in: Capsule())
    }
}

struct Badge: View {
    let text: String
    var color: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Indeterminate spinning arc used while scanning.
struct ScanRing: View {
    var size: CGFloat = 120
    var lineWidth: CGFloat = 10
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.32)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
        }
        .frame(width: size, height: size)
        .onAppear { spin = true }
    }
}

/// Donut of used space split by category, remainder = free.
struct RingChart: View {
    struct Segment: Identifiable {
        let id: String
        let color: Color
        let fraction: Double
    }
    let segments: [Segment]
    var size: CGFloat = 220
    var lineWidth: CGFloat = 24
    @State private var progress: Double = 0

    var body: some View {
        let gap = 0.003
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            ForEach(Array(cumulative().enumerated()), id: \.element.0.id) { _, pair in
                let (seg, start) = pair
                let end = start + seg.fraction
                Circle()
                    .trim(from: min(start + gap, end) * progress, to: max(end - gap, start) * progress)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.spring(duration: 1.4, bounce: 0.15)) { progress = 1 } }
    }

    private func cumulative() -> [(Segment, Double)] {
        var acc = 0.0
        return segments.map { s in
            let start = acc
            acc += s.fraction
            return (s, start)
        }
    }
}

// MARK: - Icons

@MainActor
enum IconCache {
    private static var byExtension: [String: NSImage] = [:]
    private static var byPath: [String: NSImage] = [:]

    static func icon(for node: FSNode, size: CGFloat = 20) -> NSImage {
        switch node.kind {
        case .bundle:
            return appIcon(path: node.path, size: size)
        case .directory:
            return cached("/dir", size: size) { NSWorkspace.shared.icon(for: .folder) }
        case .aggregate:
            return cached("/agg", size: size) { NSWorkspace.shared.icon(for: .data) }
        case .file:
            let ext = node.fileExtension
            return cached("." + ext, size: size) {
                NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
            }
        }
    }

    static func appIcon(path: String, size: CGFloat) -> NSImage {
        let key = "\(path)@\(size)"
        if let i = byPath[key] { return i }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: size, height: size)
        byPath[key] = img
        return img
    }

    private static func cached(_ key: String, size: CGFloat, make: () -> NSImage) -> NSImage {
        let k = "\(key)@\(size)"
        if let i = byExtension[k] { return i }
        let img = make()
        img.size = NSSize(width: size, height: size)
        byExtension[k] = img
        return img
    }
}

struct NodeIcon: View {
    let node: FSNode
    var size: CGFloat = 20
    var body: some View {
        Image(nsImage: IconCache.icon(for: node, size: size))
            .resizable()
            .frame(width: size, height: size)
    }
}

// MARK: - Helpers

extension Date {
    var relativeSpanish: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }

    var shortDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

extension FSNode {
    var modifiedDate: Date? { modified > 0 ? Date(timeIntervalSince1970: modified) : nil }
    var parentPath: String { parent?.path ?? "" }
    /// Home-relative, Finder-style path for display.
    var prettyPath: String {
        let home = NSHomeDirectory()
        let p = path
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
    }
}

/// Treemap colours: one muted hue per top-level sibling, nested items only
/// vary in lightness so a folder reads as one family. Flat fills, no gradients.
enum Palette {
    static func color(index: Int, depth: Int = 0, shade: Int = 0, kind: FSNode.Kind = .directory) -> Color {
        if kind == .aggregate { return Color(white: max(0.22, 0.40 - Double(depth) * 0.06)) }
        let (h, s, b) = Theme.series[((index % Theme.series.count) + Theme.series.count) % Theme.series.count]
        let wobble = shade == 0 ? 0.0 : (shade % 2 == 0 ? 0.06 : -0.06)
        let brightness = min(0.95, max(0.30, b * (1 - 0.13 * Double(depth)) + wobble))
        return Color(hue: h, saturation: s, brightness: brightness)
    }

    /// Darker flat fill for folders that show their children inside.
    static func container(index: Int, depth: Int = 0, kind: FSNode.Kind = .directory) -> Color {
        if kind == .aggregate { return Color(white: 0.20) }
        let (h, s, b) = Theme.series[((index % Theme.series.count) + Theme.series.count) % Theme.series.count]
        return Color(hue: h, saturation: s * 0.85, brightness: max(0.22, b * 0.42 - 0.04 * Double(depth)))
    }

    // AppKit twins used by the CoreGraphics rasteriser.
    static func nsColor(index: Int, depth: Int = 0, shade: Int = 0, kind: FSNode.Kind = .directory) -> NSColor {
        if kind == .aggregate { return NSColor(white: max(0.22, 0.40 - Double(depth) * 0.06), alpha: 1) }
        let (h, s, b) = Theme.series[((index % Theme.series.count) + Theme.series.count) % Theme.series.count]
        let wobble = shade == 0 ? 0.0 : (shade % 2 == 0 ? 0.06 : -0.06)
        let brightness = min(0.95, max(0.30, b * (1 - 0.13 * Double(depth)) + wobble))
        return NSColor(hue: h, saturation: s, brightness: brightness, alpha: 1)
    }

    static func nsContainer(index: Int, depth: Int = 0, kind: FSNode.Kind = .directory) -> NSColor {
        if kind == .aggregate { return NSColor(white: 0.20, alpha: 1) }
        let (h, s, b) = Theme.series[((index % Theme.series.count) + Theme.series.count) % Theme.series.count]
        return NSColor(hue: h, saturation: s * 0.85, brightness: max(0.22, b * 0.42 - 0.04 * Double(depth)), alpha: 1)
    }
}
