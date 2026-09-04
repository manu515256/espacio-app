import SwiftUI

struct LargestFilesView: View {
    @Environment(AppState.self) private var state
    @State private var selection = Set<FSNode.ID>()
    @State private var sortOrder = [KeyPathComparator(\FSNode.size, order: .reverse)]
    @State private var query = ""
    @State private var category: FileCategory? = nil
    @State private var confirm = false

    private var rows: [FSNode] {
        _ = state.treeVersion
        var list = state.topFiles
        if let category { list = list.filter { FileCategory.of($0) == category } }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
        }
        return list.sorted(using: sortOrder)
    }

    private var selectedNodes: [FSNode] {
        let ids = selection
        return state.topFiles.filter { ids.contains($0.id) }
    }

    private var selectedBytes: Int64 { selectedNodes.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            header
            table
        }
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty { actionBar }
        }
        .confirmationDialog(confirmTitle, isPresented: $confirm, titleVisibility: .visible) {
            Button("Mover a la Papelera", role: .destructive) {
                let nodes = selectedNodes
                selection = []
                Task { await state.trash(nodes) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Podés recuperarlos desde la Papelera. El espacio se libera al vaciarla.")
        }
    }

    private var confirmTitle: String {
        "¿Mover \(selection.count == 1 ? "1 archivo" : "\(selection.count) archivos") (\(ByteFormat.string(selectedBytes))) a la Papelera?"
    }

    private var header: some View {
        HStack(spacing: 12) {
            SectionTitle(title: "Archivos grandes",
                         subtitle: state.result == nil ? "Esperando el escaneo…" : "Los \(ByteFormat.count(Int64(state.topFiles.count))) archivos más pesados del escaneo")
            Spacer()
            Picker("Tipo", selection: $category) {
                Text("Todos los tipos").tag(FileCategory?.none)
                Divider()
                ForEach(FileCategory.allCases.filter { $0 != .small && $0 != .apps }) { c in
                    Label(c.label, systemImage: c.symbol).tag(FileCategory?.some(c))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 210)
            TextField("Buscar por nombre o ruta", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Nombre", value: \.name) { n in
                HStack(spacing: 8) {
                    NodeIcon(node: n, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.name).lineLimit(1).truncationMode(.middle)
                        Text(n.parent?.prettyPath ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.vertical, 2)
            }
            .width(min: 280, ideal: 420)

            TableColumn("Tamaño", value: \.size) { n in
                HStack(spacing: 8) {
                    SizeBar(fraction: Double(n.size) / Double(max(state.topFiles.first?.size ?? 1, 1)),
                            color: FileCategory.of(n).color, height: 5)
                        .frame(width: 70)
                    Text(ByteFormat.string(n.size)).monospacedDigit().font(.callout.weight(.semibold))
                }
            }
            .width(min: 150, ideal: 170)

            TableColumn("Tipo") { n in CategoryChip(category: FileCategory.of(n)) }
                .width(min: 120, ideal: 170)

            TableColumn("Modificado", value: \.modified) { n in
                Text(n.modifiedDate?.shortDate ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 120)
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: FSNode.ID.self) { ids in
            let nodes = state.topFiles.filter { ids.contains($0.id) }
            if !nodes.isEmpty {
                Button("Mostrar en Finder", systemImage: "finder") { TrashService.reveal(nodes.map(\.url)) }
                if nodes.count == 1 {
                    Button("Abrir", systemImage: "arrow.up.forward.app") { TrashService.open(nodes[0].url) }
                    Button("Copiar ruta", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(nodes[0].path, forType: .string)
                    }
                }
                Divider()
                Button("Mover a la Papelera", systemImage: "trash", role: .destructive) {
                    selection = ids
                    confirm = true
                }
            }
        } primaryAction: { ids in
            let nodes = state.topFiles.filter { ids.contains($0.id) }
            TrashService.reveal(nodes.map(\.url))
        }
    }

    private var actionBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(selection.count) seleccionado\(selection.count == 1 ? "" : "s")").font(.callout.weight(.semibold))
                Text(ByteFormat.string(selectedBytes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button("Mostrar en Finder", systemImage: "finder") { TrashService.reveal(selectedNodes.map(\.url)) }
                .buttonStyle(.glass).tint(.clear)
            Button("Mover a la Papelera", systemImage: "trash") { confirm = true }
                .buttonStyle(.glassProminent).tint(Theme.danger)
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .padding(.horizontal, 24).padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
