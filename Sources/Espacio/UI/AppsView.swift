import SwiftUI

struct AppsView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case size = "Tamaño", name = "Nombre", lastUsed = "Último uso"
        var id: String { rawValue }
    }

    @Environment(AppState.self) private var state
    @State private var query = ""
    private var selected: InstalledApp? {
        get { state.selectedApp }
        nonmutating set { state.selectedApp = newValue }
    }
    @State private var sort: Sort = .size

    private var apps: [InstalledApp] {
        var list = state.apps
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || ($0.bundleID?.lowercased().contains(q) ?? false) }
        }
        switch sort {
        case .size: list.sort { $0.size > $1.size }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
        return list
    }

    private var totalBytes: Int64 { state.apps.reduce(0) { $0 + $1.size } }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 360)
            Divider().overlay(Color.white.opacity(0.08))
            Group {
                if let app = selected, state.apps.contains(app) {
                    AppDetailView(app: app) { selected = nil }
                        .id(app.id)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Aplicaciones",
                             subtitle: state.appsLoading ? "Buscando apps…" : "\(state.apps.count) apps · \(ByteFormat.string(totalBytes))")
                Spacer()
                if state.appsLoading { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 8) {
                TextField("Buscar app", text: $query).textFieldStyle(.roundedBorder)
                Picker("Orden", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 120)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    let maxSize = Double(state.apps.first?.size ?? 1)
                    ForEach(apps) { app in
                        AppRow(app: app, fraction: Double(app.size) / maxSize, isSelected: selected == app)
                            .onTapGesture { selected = app }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "app.dashed").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Elegí una app para ver cuánto ocupa y desinstalarla con todos sus restos.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
    }
}

struct AppRow: View {
    let app: InstalledApp
    let fraction: Double
    let isSelected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.appIcon(path: app.url.path, size: 40)).resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name).font(.callout.weight(.semibold)).lineLimit(1)
                    if app.isRunning { Circle().fill(Theme.ok).frame(width: 6, height: 6) }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                SizeBar(fraction: fraction, color: FileCategory.apps.color, height: 3)
            }
            Spacer(minLength: 8)
            Text(ByteFormat.string(app.size)).font(.system(.callout, design: .rounded, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.18) : (hover ? Color.white.opacity(0.05) : .clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hover = $0 }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let v = app.version { parts.append("v\(v)") }
        if let d = app.lastUsed { parts.append("usada \(d.relativeSpanish)") } else { parts.append("sin uso registrado") }
        return parts.joined(separator: " · ")
    }
}

struct AppDetailView: View {
    let app: InstalledApp
    let onUninstalled: () -> Void

    @Environment(AppState.self) private var state
    @State private var leftovers: [Leftover] = []
    @State private var chosen = Set<String>()
    @State private var loading = true
    @State private var confirm = false
    @State private var working = false
    @State private var failures: [TrashService.Failure] = []

    private var chosenLeftovers: [Leftover] { leftovers.filter { chosen.contains($0.id) } }
    private var leftoverBytes: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    private var toFree: Int64 { app.size + chosenLeftovers.reduce(0) { $0 + $1.size } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(spacing: 12) {
                    StatTile(title: "la app", value: ByteFormat.string(app.size), symbol: "app.fill", tint: FileCategory.apps.color)
                    StatTile(title: "restos fuera de la app", value: loading ? "…" : ByteFormat.string(leftoverBytes), symbol: "tray.full.fill", tint: FileCategory.caches.color)
                    StatTile(title: "archivos", value: ByteFormat.count(app.fileCount), symbol: "doc.fill", tint: Theme.info)
                    StatTile(title: "último uso", value: app.lastUsed?.relativeSpanish ?? "—", symbol: "clock.fill", tint: FileCategory.appData.color)
                }
                leftoversCard
                if !failures.isEmpty {
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Algunos elementos no se pudieron mover", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
                            ForEach(failures) { f in
                                Text("\(f.url.path): \(f.message)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .task(id: app.id) {
            loading = true
            let found = await AppInventory.leftovers(for: app)
            leftovers = found
            chosen = Set(found.map(\.id))
            loading = false
        }
        .confirmationDialog("¿Desinstalar \(app.name)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Mover todo a la Papelera", role: .destructive) { uninstall() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se moverán la app y \(chosenLeftovers.count) archivos relacionados (\(ByteFormat.string(toFree))) a la Papelera.\(app.isRunning ? " La app se cerrará primero." : "")")
        }
    }

    private var header: some View {
        HStack(spacing: 20) {
            Image(nsImage: IconCache.appIcon(path: app.url.path, size: 96)).resizable().frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(app.name).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    if app.isRunning { Badge(text: "En ejecución", color: Theme.ok) }
                    if app.isSelf { Badge(text: "Esta app", color: Theme.info) }
                }
                HStack(spacing: 8) {
                    if let v = app.version { Text("Versión \(v)") }
                    if let id = app.bundleID { Text("·"); Text(id).textSelection(.enabled) }
                }
                .font(.callout).foregroundStyle(.secondary)
                Text(app.url.path).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var leftoversCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "Archivos relacionados", subtitle: "Cachés, preferencias y datos que quedan al borrar solo la app")
                    Spacer()
                    if !leftovers.isEmpty {
                        Button(chosen.count == leftovers.count ? "Ninguno" : "Todos") {
                            chosen = chosen.count == leftovers.count ? [] : Set(leftovers.map(\.id))
                        }
                        .buttonStyle(.glass).tint(.clear).controlSize(.small)
                    }
                }
                if loading {
                    HStack { ProgressView().controlSize(.small); Text("Buscando restos…").foregroundStyle(.secondary) }
                } else if leftovers.isEmpty {
                    Text("No encontré archivos fuera del paquete de la app.").foregroundStyle(.secondary)
                } else {
                    ForEach(leftovers) { item in
                        Toggle(isOn: Binding(
                            get: { chosen.contains(item.id) },
                            set: { on in if on { chosen.insert(item.id) } else { chosen.remove(item.id) } }
                        )) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                                        Badge(text: item.kind.rawValue)
                                    }
                                    Text(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text(ByteFormat.string(item.size)).font(.callout.weight(.semibold)).monospacedDigit()
                            }
                        }
                        .toggleStyle(.checkbox)
                        .contextMenu {
                            Button("Mostrar en Finder", systemImage: "finder") { TrashService.reveal(item.url) }
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Liberás \(ByteFormat.string(toFree))").font(.callout.weight(.semibold)).monospacedDigit()
                Text(chosenLeftovers.count == 1 ? "app + 1 archivo relacionado" : "app + \(chosenLeftovers.count) archivos relacionados")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Mostrar en Finder", systemImage: "finder") { TrashService.reveal(app.url) }
                .buttonStyle(.glass).tint(.clear)
            Button {
                confirm = true
            } label: {
                if working { ProgressView().controlSize(.small) } else { Label("Desinstalar", systemImage: "trash") }
            }
            .buttonStyle(.glassProminent).tint(Theme.danger)
            .disabled(working || app.isSelf)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func uninstall() {
        working = true
        let items = chosenLeftovers
        Task {
            let fails = await state.uninstall(app, leftovers: items)
            working = false
            failures = fails
            if fails.isEmpty { onUninstalled() }
        }
    }
}
