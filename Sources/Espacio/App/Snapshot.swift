import AppKit
import SwiftUI

/// Debug aid: `ESPACIO_SNAPSHOT_DIR=/tmp/x Espacio.app` waits for the scan,
/// walks every section, writes a PNG of the window for each, and quits.
enum Snapshot {
    @MainActor
    static func runIfRequested(state: AppState) {
        guard let dir = ProcessInfo.processInfo.environment["ESPACIO_SNAPSHOT_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            while state.phase == .idle || state.phase == .scanning || state.appsLoading {
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? await Task.sleep(for: .seconds(2))
            if let w = NSApp.windows.first(where: { $0.isVisible }) {
                FileHandle.standardError.write("ESPACIO_WINDOW \(w.windowNumber)\n".data(using: .utf8)!)
                var origin = NSPoint(x: 60, y: 40)
                if ProcessInfo.processInfo.environment["ESPACIO_SNAPSHOT_RETINA"] != nil,
                   let screen = NSScreen.screens.first(where: { $0.backingScaleFactor > 1 }) {
                    origin = NSPoint(x: screen.frame.minX + 40, y: screen.frame.minY + 40)
                }
                w.setFrame(NSRect(origin: origin, size: NSSize(width: 1500, height: 1000)), display: true)
                FileHandle.standardError.write("ESPACIO_SCREEN scale=\(w.screen?.backingScaleFactor ?? 0) frame=\(w.frame)\n".data(using: .utf8)!)
            }
            if let victim = ProcessInfo.processInfo.environment["ESPACIO_SNAPSHOT_UNINSTALL"],
               let app = state.apps.first(where: { $0.name == victim }) {
                let leftovers = await AppInventory.leftovers(for: app)
                let fails = await state.uninstall(app, leftovers: leftovers)
                let msg = "ESPACIO_UNINSTALL \(app.url.path) leftovers=\(leftovers.map(\.url.path)) failures=\(fails.map(\.message)) remaining=\(state.apps.contains(where: { $0.name == victim }))\n"
                FileHandle.standardError.write(msg.data(using: .utf8)!)
            }
            if let wanted = ProcessInfo.processInfo.environment["ESPACIO_SNAPSHOT_APP"] {
                state.selectedApp = state.apps.first { $0.name.localizedCaseInsensitiveContains(wanted) }
            }
            try? await Task.sleep(for: .seconds(1))
            let hold = Double(ProcessInfo.processInfo.environment["ESPACIO_SNAPSHOT_HOLD"] ?? "") ?? 1.6
            var order = Array(AppSection.allCases.dropFirst()) + [AppSection.overview]
            if let only = ProcessInfo.processInfo.environment["ESPACIO_SNAPSHOT_ONLY"], let s = AppSection(rawValue: only) { order = [s] }
            for section in order {
                state.section = section
                try? await Task.sleep(for: .seconds(hold))
                capture(to: "\(dir)/\(section.rawValue).png")
                external(section: section, dir: dir)
            }
            exit(0)
        }
    }

    /// Real composited pixels (glass included) via `screencapture -l`, which
    /// only works when the launching process has Screen Recording permission.
    @MainActor
    static func external(section: AppSection, dir: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", "\(dir)/\(section.rawValue)-real.png"]
        try? p.run()
        p.waitUntilExit()
    }

    @MainActor
    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
        window.displayIfNeeded()
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
