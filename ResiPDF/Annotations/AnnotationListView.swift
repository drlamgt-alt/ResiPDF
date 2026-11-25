import SwiftUI
import PDFKit

struct AnnotationItem: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let page: PDFPage
    let group: String
    let kind: String
    let text: String
    let color: UIColor
}

/// Lista de todas las marcas del PDF, filtrable por significado
/// (ej. ver solo las moradas = «Pregunta de examen») y exportable como resumen.
struct AnnotationListView: View {
    let pdf: PDFDocument
    @ObservedObject var store: SettingsStore
    let onSelect: (PDFPage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [AnnotationItem] = []
    @State private var filter: String?
    @State private var loaded = false

    private var groups: [String] {
        let present = Set(items.map(\.group))
        var order = store.settings.presets.map(\.name)
        order += store.settings.stamps.map { "Sello \($0)" }
        order += ["Comentarios", "Dibujos y flechas", "Otros"]
        let known = order.filter { present.contains($0) }
        let extra = present.subtracting(order).sorted()
        return known + extra
    }

    private var filtered: [AnnotationItem] {
        guard let filter else { return items }
        return items.filter { $0.group == filter }
    }

    var body: some View {
        NavigationStack {
            List {
                if !groups.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip("Todas", color: nil, selected: filter == nil) { filter = nil }
                                ForEach(groups, id: \.self) { g in
                                    let c = store.settings.presets.first { $0.name == g }?.color
                                    chip(g, color: c, selected: filter == g) { filter = g }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                ForEach(filtered) { item in
                    Button {
                        onSelect(item.page)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(item.color.withAlphaComponent(1)))
                                .frame(width: 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("p. \(item.pageIndex + 1) · \(item.group) · \(item.kind)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(item.text.isEmpty ? "(sin texto)" : item.text)
                                    .foregroundStyle(.primary)
                                    .lineLimit(4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Anotaciones (\(filtered.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: markdown(), preview: SharePreview("Resumen de anotaciones")) {
                        Label("Exportar resumen", systemImage: "square.and.arrow.up")
                    }
                    .disabled(items.isEmpty)
                }
            }
            .overlay {
                if loaded && items.isEmpty {
                    ContentUnavailableView("Sin anotaciones",
                                           systemImage: "highlighter",
                                           description: Text("Elige un color en la paleta y pasa el Apple Pencil sobre el texto."))
                }
            }
            .task {
                items = collect()
                loaded = true
            }
        }
    }

    private func chip(_ title: String, color: UIColor?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(Color(color)).frame(width: 10, height: 10)
                }
                Text(title).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)))
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recolección

    private func collect() -> [AnnotationItem] {
        let textTypes: Set<String> = ["Highlight", "Underline", "StrikeOut", "Squiggly", "Square"]
        let kinds: [String: String] = [
            "Highlight": "Resaltado", "Underline": "Subrayado", "StrikeOut": "Tachado",
            "Squiggly": "Ondulado", "Square": "Recuadro", "FreeText": "Comentario",
            "Text": "Nota", "Ink": "Trazo", "Line": "Flecha",
        ]
        var out: [AnnotationItem] = []

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            var seenGroups = Set<String>()
            for a in page.annotations {
                let type = a.type ?? ""
                guard let kind = kinds[type], !MaskStyle.isMask(a) else { continue }
                if AnnotationController.isStamp(a) {
                    let stamp = a.contents ?? "?"
                    out.append(AnnotationItem(pageIndex: i, page: page, group: "Sello \(stamp)", kind: "Sello",
                                              text: pageSnippet(page), color: a.color))
                    continue
                }
                if let g = AnnotationController.groupID(of: a) {
                    if seenGroups.contains(g) { continue }
                    seenGroups.insert(g)
                }

                var text = a.contents ?? ""
                if text.isEmpty, textTypes.contains(type) {
                    text = page.selection(for: a.bounds)?.string ?? ""
                }
                text = text.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let group: String
                switch type {
                case "FreeText", "Text":
                    group = "Comentarios"
                case "Ink", "Line":
                    group = store.nearestPreset(to: a.color)?.name ?? "Dibujos y flechas"
                default:
                    group = store.nearestPreset(to: a.color)?.name ?? "Otros"
                }
                out.append(AnnotationItem(pageIndex: i, page: page, group: group, kind: kind,
                                          text: text, color: a.color))
            }
        }
        return out
    }

    /// Primer renglón con texto de la página (para identificar dónde está un sello).
    private func pageSnippet(_ page: PDFPage) -> String {
        let text = page.string ?? ""
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 12 } ?? ""
        return String(line.prefix(120))
    }

    /// Resumen en Markdown agrupado por significado — ideal para pasar a Anki o repasar.
    private func markdown() -> String {
        var md = "# Resumen de anotaciones\n"
        if let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            md += "_\(title)_\n"
        }
        for g in groups where filter == nil || filter == g {
            md += "\n## \(g)\n"
            for item in items where item.group == g {
                let t = item.text.isEmpty ? "(\(item.kind.lowercased()))" : item.text
                md += "- **p. \(item.pageIndex + 1)** — \(t)\n"
            }
        }
        return md
    }
}
