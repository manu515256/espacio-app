import SwiftUI

@main
struct EspacioApp: App {
    @State private var state = AppState()

    init() {
        UserDefaults.standard.register(defaults: [
            "ApplePersistenceIgnoreState": true,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        Bench.runIfRequested()
    }

    var body: some Scene {
        let _ = Trace.log("scene body")
        WindowGroup {
            ContentView()
                .onAppear { Trace.log("content appeared") }
                .environment(state)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    Trace.log("task started")
                    if let root = ProcessInfo.processInfo.environment["ESPACIO_ROOT"] { state.scanRoot = root }
                    state.bootstrap()
                    Snapshot.runIfRequested(state: state)
                }
        }
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum Trace {
    static func log(_ m: String) {
        guard ProcessInfo.processInfo.environment["ESPACIO_TRACE"] != nil else { return }
        FileHandle.standardError.write("ESPACIO_TRACE \(m) windows=\(NSApp?.windows.count ?? -1)\n".data(using: .utf8)!)
    }
}
