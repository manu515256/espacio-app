import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showPicker = false

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.section) {
                ForEach(AppSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { sidebarFooter }
        } detail: {
            Group {
                switch state.section {
                case .overview: OverviewView()
                case .apps: AppsView()
                case .files: LargestFilesView()
                case .explorer: ExplorerView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground() }
        }
        .navigationTitle("Espacio")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Todo el disco", systemImage: "internaldrive") { state.startScan(path: "/") }
                    Button("Carpeta personal", systemImage: "house") { state.startScan(path: NSHomeDirectory()) }
                    Divider()
                    Button("Elegir carpeta…", systemImage: "folder") { showPicker = true }
                } label: {
                    Label(rootLabel, systemImage: "internaldrive")
                }
                if state.isScanning {
                    Button("Cancelar", systemImage: "xmark.circle") { state.cancelScan() }
                } else {
                    Button("Escanear", systemImage: "arrow.clockwise") { state.startScan() }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { state.startScan(path: url.path) }
        }
        .alert("No se pudo mover a la Papelera", isPresented: Binding(get: { !state.failures.isEmpty }, set: { if !$0 { state.failures = [] } })) {
            Button("OK") { state.failures = [] }
        } message: {
            Text(state.failures.map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "\n"))
        }
    }

    private var rootLabel: String {
        if state.scanRoot == "/" { return "Todo el disco" }
        if state.scanRoot == NSHomeDirectory() { return "Carpeta personal" }
        return (state.scanRoot as NSString).lastPathComponent
    }

    private var subtitle: String {
        if state.isScanning { return "Escaneando… \(ByteFormat.count(state.liveFiles)) archivos" }
        if let r = state.result { return "\(ByteFormat.string(r.root.size)) en \(ByteFormat.count(r.fileCount)) archivos" }
        return ""
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let v = state.volume {
                SizeBar(fraction: v.usedFraction, color: v.usedFraction > 0.95 ? Theme.accent : Theme.info, height: 5)
                Text("\(ByteFormat.string(v.available)) libres de \(ByteFormat.string(v.total))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(12)
    }
}
