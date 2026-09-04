import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state
    @State private var pendingTrash: [FSNode] = []
    @State private var confirmEmptyTrash = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if state.isScanning {
                    scanningCard
                } else if state.result != nil {
                    if state.trashedBytes > 0 { trashBanner }
                    HStack(alignment: .top, spacing: 18) {
                        categoriesCard
                        topFilesCard
                    }
                    quickWinsCard
                }
            }
            .padding(24)
        }
        .confirmationDialog(trashTitle, isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } }),
                            titleVisibility: .visible) {
            Button(L("Mover a la Papelera"), role: .destructive) {
                let nodes = pendingTrash
                pendingTrash = []
                Task { await state.trash(nodes) }
            }
            Button(L("Cancelar"), role: .cancel) { pendingTrash = [] }
        } message: {
            Text(L("Podés recuperarlo desde la Papelera. El espacio se libera al vaciarla."))
        }
        .confirmationDialog(L("¿Vaciar la Papelera?"), isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button(L("Vaciar Papelera"), role: .destructive) { state.emptyTrash() }
            Button(L("Cancelar"), role: .cancel) {}
        } message: {
            Text(L("Esto elimina definitivamente todo lo que hay en la Papelera."))
        }
    }

    private var trashTitle: String {
        let total = pendingTrash.reduce(Int64(0)) { $0 + $1.size }
        return pendingTrash.count == 1
            ? L("¿Mover “%@” (%@) a la Papelera?", pendingTrash[0].displayName, ByteFormat.string(total))
            : L("¿Mover %lld elementos (%@) a la Papelera?", Int64(pendingTrash.count), ByteFormat.string(total))
    }

    private var hero: some View {
        Card(padding: 24) {
            HStack(spacing: 28) {
                ZStack {
                    RingChart(segments: ringSegments, size: 210, lineWidth: 22)
                    VStack(spacing: 2) {
                        Text(state.volume.map { String(format: "%.0f%%", locale: AppLanguage.current.locale, $0.usedFraction * 100) } ?? "—")
                            .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(L("usado")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "internaldrive.fill").foregroundStyle(.secondary)
                        Text(state.volume?.name ?? L("Disco")).font(.headline)
                        if state.scanRoot != "/" {
                            Badge(text: state.scanRoot.replacingOccurrences(of: NSHomeDirectory(), with: "~"), color: Theme.info)
                        }
                    }
                    if let v = state.volume {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ByteFormat.string(v.used)).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(L("de %@", ByteFormat.string(v.total))).font(.title3).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            let low = Double(v.available) / Double(max(v.total, 1)) < 0.05
                            Label(L("%@ disponibles", ByteFormat.string(v.available)), systemImage: low ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(low ? Theme.accent : Theme.ok)
                                .font(.callout.weight(.medium))
                            if v.purgeable > 0 {
                                Text(L("· %@ purgables", ByteFormat.string(v.purgeable))).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(title: L("archivos"), value: ByteFormat.count(state.liveFiles), symbol: "doc.fill", tint: Theme.info)
                        StatTile(title: L("carpetas"), value: ByteFormat.count(state.liveDirs), symbol: "folder.fill", tint: FileCategory.images.color)
                        if let r = state.result {
                            StatTile(title: L("escaneado en"), value: ByteFormat.duration(r.duration), symbol: "bolt.fill", tint: Theme.accent)
                        } else {
                            StatTile(title: L("escaneados"), value: ByteFormat.string(state.liveBytes), symbol: "bolt.fill", tint: Theme.accent)
                        }
                    }
                    if state.liveDenied > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                            Text(L("%@ carpetas sin permiso de lectura.", ByteFormat.count(state.liveDenied)))
                                .font(.callout)
                            Button(L("Dar acceso total al disco…"), systemImage: "lock.open.fill") { TrashService.openFullDiskAccessSettings() }
                                .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.small)
                            Text(L("Después volvé a escanear.")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var ringSegments: [RingChart.Segment] {
        guard let v = state.volume, v.total > 0 else { return [] }
        let total = Double(v.total)
        var segs: [RingChart.Segment] = []
        var accounted: Int64 = 0
        if !state.categories.isEmpty {
            for c in state.categories {
                segs.append(.init(id: c.category.rawValue, color: c.category.color, fraction: Double(c.bytes) / total))
                accounted += c.bytes
            }
        } else if state.isScanning {
            segs.append(.init(id: "live", color: Theme.accent, fraction: Double(state.liveBytes) / total))
            accounted = state.liveBytes
        }
        let restUsed = max(v.used - accounted, 0)
        if restUsed > 0 {
            segs.append(.init(id: "system", color: Color(white: 0.34), fraction: Double(restUsed) / total))
        }
        return segs
    }

    private var scanningCard: some View {
        Card(padding: 24) {
            HStack(spacing: 24) {
                ScanRing(size: 92, lineWidth: 9)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Escaneando %@…", state.scanRoot == "/" ? L("todo el disco") : state.scanRoot))
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(L("%@ archivos · %@ carpetas · %@", ByteFormat.count(state.liveFiles), ByteFormat.count(state.liveDirs), ByteFormat.string(state.liveBytes)))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                    if !state.liveTop.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Más grandes hasta ahora")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                            ForEach(state.liveTop.prefix(5)) { n in
                                HStack {
                                    Text(n.name).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(ByteFormat.string(n.size)).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                Spacer()
                Button(L("Cancelar"), systemImage: "xmark") { state.cancelScan() }
                    .buttonStyle(.glass).tint(.clear)
            }
        }
    }

    private var trashBanner: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill").foregroundStyle(Theme.accent).font(.title3)
                Text((try? AttributedString(markdown: L("Moviste **%@** a la Papelera. El espacio se libera cuando la vaciás.", ByteFormat.string(state.trashedBytes)))) ?? AttributedString(""))
                Spacer()
                Button(L("Vaciar Papelera"), systemImage: "trash.slash") { confirmEmptyTrash = true }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
            }
        }
    }

    private var categoriesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: L("Por categoría"), subtitle: L("Qué tipo de contenido ocupa el disco"))
                if state.categories.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    let total = Double(max(state.root?.size ?? 1, 1))
                    ForEach(state.categories) { c in
                        VStack(spacing: 5) {
                            HStack {
                                Image(systemName: c.category.symbol).foregroundStyle(c.category.color).frame(width: 18)
                                Text(c.category.label).font(.callout)
                                Spacer()
                                Text(String(format: "%.1f %%", locale: AppLanguage.current.locale, Double(c.bytes) / total * 100)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                Text(ByteFormat.string(c.bytes)).font(.callout.weight(.semibold)).monospacedDigit().frame(width: 84, alignment: .trailing)
                            }
                            SizeBar(fraction: Double(c.bytes) / total, color: c.category.color, height: 5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var topFilesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: L("Archivos más grandes"))
                    Spacer()
                    Button(L("Ver todos")) { state.section = .files }.buttonStyle(.glass).tint(.clear).controlSize(.small)
                }
                let maxSize = Double(state.topFiles.first?.size ?? 1)
                ForEach(state.topFiles.prefix(8)) { n in
                    HStack(spacing: 10) {
                        NodeIcon(node: n, size: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(n.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(ByteFormat.string(n.size)).font(.callout.weight(.semibold)).monospacedDigit()
                            }
                            SizeBar(fraction: Double(n.size) / maxSize, color: FileCategory.of(n).color, height: 4)
                            Text(n.parent?.prettyPath ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .contextMenu {
                        Button(L("Mostrar en Finder"), systemImage: "finder") { TrashService.reveal(n.url) }
                        Button(L("Mover a la Papelera"), systemImage: "trash", role: .destructive) { pendingTrash = [n] }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var quickWinsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: L("Limpieza rápida"), subtitle: L("Lugares que suelen acumular espacio recuperable"))
                if state.quickWins.isEmpty {
                    Text(L("Nada llamativo por acá.")).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(state.quickWins) { win in
                            QuickWinCard(win: win) {
                                switch win.action {
                                case .trash: pendingTrash = [win.node]
                                case .emptyTrash: confirmEmptyTrash = true
                                case .reveal: TrashService.reveal(win.node.url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct QuickWinCard: View {
    let win: QuickWin
    let primary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: win.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L(win.title)).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(win.node.prettyPath).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(ByteFormat.string(win.size)).font(.system(.callout, design: .rounded, weight: .bold)).monospacedDigit()
            }
            Text(L(win.hint)).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("Mostrar"), systemImage: "finder") { TrashService.reveal(win.node.url) }
                    .buttonStyle(.glass).tint(.clear).controlSize(.small)
                Spacer()
                switch win.action {
                case .trash:
                    Button(L("Papelera"), systemImage: "trash", action: primary)
                        .buttonStyle(.glassProminent).tint(Theme.danger).controlSize(.small)
                case .emptyTrash:
                    Button(L("Vaciar"), systemImage: "trash.slash", action: primary)
                        .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.small)
                case .reveal:
                    Button(L("Explorar"), systemImage: "rectangle.3.group", action: primary)
                        .buttonStyle(.glass).tint(.clear).controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
