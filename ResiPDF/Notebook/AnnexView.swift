import SwiftUI

/// Hoja de anexo: se llena sola con las marcas del libro (o con las figuras recortadas).
struct AnnexView: View {
    let kind: AnnexKind
    @ObservedObject var store: NotebookStore
    let presets: [MarkPreset]
    let onGo: (Int) -> Void
    let onInsert: (NotebookFigure) -> Void

    static func entries(_ kind: AnnexKind, in marks: [StudyMark]) -> [StudyMark] {
        marks.filter { $0.action == kind.action && !$0.group.hasPrefix("Sello") && $0.group != "Comentarios" }
            .sorted { $0.pageIndex < $1.pageIndex }
    }

    private var entries: [StudyMark] { Self.entries(kind, in: store.marks) }

    private var hint: String {
        if kind == .figures {
            return "Recorta figuras del libro con la herramienta ✂︎ (menú ⋯ del dock): enmarca la imagen con el Pencil."
        }
        if let preset = presets.first(where: { $0.action == kind.action }) {
            return "Se llena sola con lo que marcas como «\(preset.name)». Toca «p.» para volver al libro."
        }
        return "Ningún color del patrón actual alimenta este anexo. Asígnale la acción en Preferencias."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANEXO \(kind.letter)")
                        .font(.caption.weight(.bold))
                        .kerning(1)
                        .foregroundStyle(.secondary)
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.title2.weight(.bold))
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Divider()
                if kind == .figures {
                    figures
                } else {
                    list
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            .padding(12)
            .environment(\.colorScheme, .light)
        }
    }

    @ViewBuilder
    private var list: some View {
        if entries.isEmpty {
            Text("Todavía no hay nada aquí.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
        } else {
            ForEach(Array(entries.enumerated()), id: \.element.id) { n, item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(n + 1).")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color(item.color.withAlphaComponent(1)))
                        .frame(minWidth: 28, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayText)
                            .font(kind == .questions ? .body.weight(.medium) : .body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        HStack(spacing: 6) {
                            Button("p. \(item.pageIndex + 1)") { onGo(item.pageIndex) }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider().opacity(0.5)
            }
        }
    }

    @ViewBuilder
    private var figures: some View {
        if store.figures.isEmpty {
            Text("Todavía no has recortado figuras.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                ForEach(store.figures) { figure in
                    VStack(alignment: .leading, spacing: 6) {
                        Group {
                            if let img = store.image(named: figure.file) {
                                Image(uiImage: img).resizable().scaledToFit()
                            } else {
                                Color(.tertiarySystemFill)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: 170)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator), lineWidth: 0.5))
                        Text(figure.caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button { onInsert(figure) } label: {
                            Label("Insertar en la hoja actual", systemImage: "square.and.arrow.down.on.square")
                        }
                        Button { onGo(figure.sourcePage) } label: {
                            Label("Ir a la p. \(figure.sourcePage + 1) del libro", systemImage: "book")
                        }
                        Button(role: .destructive) { store.deleteFigure(figure.id) } label: {
                            Label("Eliminar figura", systemImage: "trash")
                        }
                    }
                    .onTapGesture { onInsert(figure) }
                }
            }
        }
    }
}
