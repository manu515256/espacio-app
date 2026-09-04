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
            .id(state.language)
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
            .id(state.language)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground() }
        }
        .environment(\.locale, state.language.locale)
        .navigationTitle("Espacio")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(L("Idioma"), selection: Binding(get: { state.language }, set: { state.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.menuTitle).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help(L("Idioma"))
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button(L("Todo el disco"), systemImage: "internaldrive") { state.startScan(path: "/") }
                    Button(L("Carpeta personal"), systemImage: "house") { state.startScan(path: NSHomeDirectory()) }
                    Divider()
                    Button(L("Elegir carpeta…"), systemImage: "folder") { showPicker = true }
                } label: {
                    Label(rootLabel, systemImage: "internaldrive")
                }
                if state.isScanning {
                    Button(L("Cancelar"), systemImage: "xmark.circle") { state.cancelScan() }
                } else {
                    Button(L("Escanear"), systemImage: "arrow.clockwise") { state.startScan() }
                        .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { state.startScan(path: url.path) }
        }
        .alert(L("No se pudo mover a la Papelera"), isPresented: Binding(get: { !state.failures.isEmpty }, set: { if !$0 { state.failures = [] } })) {
            Button(L("OK")) { state.failures = [] }
        } message: {
            Text(state.failures.map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "\n"))
        }
    }

    private var rootLabel: String {
        if state.scanRoot == "/" { return L("Todo el disco") }
        if state.scanRoot == NSHomeDirectory() { return L("Carpeta personal") }
        return (state.scanRoot as NSString).lastPathComponent
    }

    private var subtitle: String {
        if state.isScanning { return L("Escaneando… %@ archivos", ByteFormat.count(state.liveFiles)) }
        if let r = state.result { return L("%@ en %@ archivos", ByteFormat.string(r.root.size), ByteFormat.count(r.fileCount)) }
        return ""
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let v = state.volume {
                SizeBar(fraction: v.usedFraction, color: v.usedFraction > 0.95 ? Theme.accent : Theme.info, height: 5)
                Text(L("%@ libres de %@", ByteFormat.string(v.available), ByteFormat.string(v.total)))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(12)
    }
}
