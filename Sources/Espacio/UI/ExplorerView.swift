import SwiftUI

struct ExplorerView: View {
    @Environment(AppState.self) private var state
    @State private var selected: FSNode?
    @State private var pendingTrash: FSNode?

    var body: some View {
        Group {
            if let root = state.explorerRoot {
                content(root: root)
            } else {
                VStack(spacing: 12) {
                    if state.isScanning { ScanRing(size: 60, lineWidth: 6) }
                    Text(state.isScanning ? L("El explorador aparece cuando termina el escaneo.") : L("Todavía no hay un escaneo."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog(
            L("¿Mover “%@” (%@) a la Papelera?", pendingTrash?.displayName ?? "", ByteFormat.string(pendingTrash?.size ?? 0)),
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Mover a la Papelera"), role: .destructive) {
                guard let n = pendingTrash else { return }
                pendingTrash = nil
                if selected === n { selected = nil }
                Task { await state.trash([n]) }
            }
            Button(L("Cancelar"), role: .cancel) { pendingTrash = nil }
        } message: {
            Text(L("Podés recuperarlo desde la Papelera. El espacio se libera al vaciarla."))
        }
    }

    private func content(root: FSNode) -> some View {
        VStack(spacing: 14) {
            breadcrumb(root: root)
            HStack(spacing: 14) {
                TreemapView(root: root, version: state.treeVersion, selected: $selected,
                            onZoom: { zoom(to: $0) },
                            onTrash: { pendingTrash = $0 })
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .id(root.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                sidePanel(root: root)
                    .frame(width: 330)
            }
        }
        .padding(20)
        .onChange(of: state.treeVersion) { _, _ in selected = nil }
    }

    private func zoom(to node: FSNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) {
            state.explorerRoot = node
            selected = nil
        }
    }

    private func breadcrumb(root: FSNode) -> some View {
        HStack(spacing: 10) {
            Button { if let p = root.parent { zoom(to: p) } } label: {
                Image(systemName: "arrow.up").frame(width: 14)
            }
            .buttonStyle(.glass).tint(.clear).disabled(root.parent == nil)
            .keyboardShortcut(.upArrow, modifiers: .command)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    let chain = root.ancestry
                    ForEach(Array(chain.enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(n.displayName) { zoom(to: n) }
                            .buttonStyle(.plain)
                            .font(.callout.weight(i == chain.count - 1 ? .semibold : .regular))
                            .foregroundStyle(i == chain.count - 1 ? .primary : .secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
            .glassEffect(.regular, in: .capsule)

            Spacer()
            Text(L("%@ · %@ archivos", ByteFormat.string(root.size), ByteFormat.count(root.fileCount)))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Button(L("Mostrar en Finder"), systemImage: "finder") { TrashService.reveal(root.url) }
                .buttonStyle(.glass).tint(.clear)
        }
    }

    private func sidePanel(root: FSNode) -> some View {
        VStack(spacing: 12) {
            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Contenido")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            let kids = root.sortedChildren().filter { $0.size > 0 }
                            ForEach(Array(kids.prefix(400).enumerated()), id: \.element.id) { i, n in
                                ChildRow(node: n, fraction: Double(n.size) / Double(max(root.size, 1)),
                                         color: Palette.color(index: i, kind: n.kind), isSelected: selected === n)
                                    .onTapGesture {
                                        if n.isDirectory && !n.children.isEmpty { zoom(to: n) } else { selected = n }
                                    }
                                    .contextMenu {
                                        if n.kind != .aggregate {
                                            Button(L("Mostrar en Finder"), systemImage: "finder") { TrashService.reveal(n.url) }
                                            Button(L("Mover a la Papelera"), systemImage: "trash", role: .destructive) { pendingTrash = n }
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            if let n = selected {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            NodeIcon(node: n, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.displayName).font(.callout.weight(.semibold)).lineLimit(2)
                                Text(ByteFormat.string(n.size)).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                            }
                        }
                        if let d = n.modifiedDate { Text(L("Modificado %@", d.relativeDescription)).font(.caption).foregroundStyle(.secondary) }
                        Text(n.prettyPath).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        HStack {
                            Button(L("Mostrar"), systemImage: "finder") { TrashService.reveal(n.url) }
                                .buttonStyle(.glass).tint(.clear).controlSize(.small)
                            Spacer()
                            if n.kind != .aggregate {
                                Button(L("Papelera"), systemImage: "trash") { pendingTrash = n }
                                    .buttonStyle(.glassProminent).tint(Theme.danger).controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ChildRow: View {
    let node: FSNode
    let fraction: Double
    let color: Color
    let isSelected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(node.displayName).font(.callout).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ByteFormat.string(node.size)).font(.callout.weight(.semibold)).monospacedDigit()
                }
                SizeBar(fraction: fraction, color: color, height: 3)
            }
            if node.isDirectory {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? Theme.accent.opacity(0.18) : (hover ? Color.white.opacity(0.05) : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
