import AppKit
import Foundation

/// Moves files to the Trash. Tries the plain FileManager route first and falls
/// back to asking Finder (which shows the admin-password prompt) for items the
/// current user cannot move, e.g. root-owned apps installed by a .pkg.
enum TrashService {
    struct Failure: Identifiable {
        let id = UUID()
        let url: URL
        let message: String
    }

    @MainActor
    static func trash(_ urls: [URL]) async -> [Failure] {
        var needsFinder: [URL] = []
        var failures: [Failure] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain
                    && (error.code == NSFileWriteNoPermissionError || error.code == NSFileReadNoPermissionError
                        || error.code == NSFileWriteVolumeReadOnlyError)
                    || (error.domain == NSPOSIXErrorDomain && (error.code == Int(EACCES) || error.code == Int(EPERM))) {
                    needsFinder.append(url)
                } else {
                    failures.append(Failure(url: url, message: error.localizedDescription))
                }
            }
        }
        if !needsFinder.isEmpty {
            if let message = finderTrash(needsFinder) {
                failures += needsFinder.map { Failure(url: $0, message: message) }
            }
        }
        return failures
    }

    /// Returns an error message, or nil on success.
    @MainActor
    private static func finderTrash(_ urls: [URL]) -> String? {
        let items = urls.map { "POSIX file \"\(escape($0.path))\"" }.joined(separator: ", ")
        let source = """
        tell application "Finder"
            delete {\(items)}
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "No se pudo crear el script." }
        script.executeAndReturnError(&error)
        if let error {
            return error[NSAppleScript.errorMessage] as? String ?? "Finder rechazó la operación."
        }
        return nil
    }

    @MainActor
    static func emptyTrash() -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if let error { return error[NSAppleScript.errorMessage] as? String ?? "Finder rechazó la operación." }
        return nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
