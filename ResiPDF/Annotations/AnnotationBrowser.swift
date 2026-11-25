import SwiftUI
import PDFKit

struct AnnotationItem: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let page: PDFPage
    /// Nombre del marcador (o «Comentarios», «Sello Q»…)
    let group: String
    let action: ReviewAction?
    let kind: String
    let text: String
    let color: UIColor
    let tags: [String]
}

/// Lista de marcas del PDF con filtros por color y por etiqueta, y exportación.
/// Se usa dentro de la barra lateral.
struct AnnotationBrowser: View {
    let pdf: PDFDocument
    @ObservedObject var store: SettingsStore
    var refreshToken: Int = 0
    let onSelect: (PDFPage) -> Void

    @State private var items: [AnnotationItem] = []
    @State private var colorFilter: String?
    @State private var tagFilter: String?

    private var groups: [String] {
        let present = Set(items.map(\.group))
        let order = store.settings.presets.map(\.name) + ["Comentarios", "Dibujos y flechas", "Otros"]
        let known = order.filter { present.contains($0) }
        return known + present.subtracting(order).sorted()
    }

    private var presentTags: [String] {
        let present = Set(items.flatMap(\.tags))
        let ordered = store.settings.tags.filter { present.contains($0) }
        return ordered + present.subtracting(ordered).sorted()
    }

    private var filtered: [AnnotationItem] {
        items.filter { item in
            (colorFilter == nil || item.group == colorFilter) &&
            (tagFilter == nil || item.tags.contains(tagFilter ?? ""))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !items.isEmpty {
                filters
                Divider()
            }
            if items.isEmpty {
                ContentUnavailableView("Sin marcas todavía",
                                       systemImage: "highlighter",
                                       description: Text("Elige un color y pasa el Apple Pencil sobre el texto."))
            } else {
                List(filtered) { item in
                    Button { onSelect(item.page) } label: { row(item) }
                }
                .listStyle(.plain)
            }
        }
        .task(id: refreshToken) { items = Self.collect(pdf: pdf, store: store) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Todas", color: nil, selected: colorFilter == nil) { colorFilter = nil }
                    ForEach(groups, id: \.self) { g in
                        let c = store.settings.presets.first { $0.name == g }?.color
                        chip(g, color: c, selected: colorFilter == g) { colorFilter = colorFilter == g ? nil : g }
                    }
                }
            }
            if !presentTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Image(systemName: "tag").font(.caption).foregroundStyle(.secondary)
                        ForEach(presentTags, id: \.self) { t in
                            chip(t, color: nil, selected: tagFilter == t) { tagFilter = tagFilter == t ? nil : t }
                        }
                    }
                }
            }
            HStack {
                Text("\(filtered.count) marcas").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: markdown(), preview: SharePreview("Resumen de marcas")) {
                    Label("Exportar", systemImage: "square.and.arrow.up").font(.caption.weight(.semibold))
                }
            }
        }
        .padding(12)
    }

    private func row(_ item: AnnotationItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(item.color.withAlphaComponent(1)))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("p. \(item.pageIndex + 1)").font(.caption.weight(.semibold))
                    Text(item.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    ForEach(item.tags, id: \.self) { t in
                        Text(t)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                }
                Text(item.text.isEmpty ? "(\(item.kind.lowercased()))" : item.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private func chip(_ title: String, color: UIColor?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(Color(color)).frame(width: 9, height: 9)
                }
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill)))
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recolección

    static func collect(pdf: PDFDocument, store: SettingsStore) -> [AnnotationItem] {
        let textTypes: Set<String> = ["Highlight", "Underline", "StrikeOut", "Squiggly", "Square"]
        let kinds: [String: String] = [
            "Highlight": "Resaltado", "Underline": "Subrayado", "StrikeOut": "Tachado",
            "Squiggly": "Ondulado", "Square": "Recuadro", "FreeText": "Comentario",
            "Text": "Nota", "Ink": "Trazo", "Line": "Flecha", "Circle": "Círculo",
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
                    out.append(AnnotationItem(pageIndex: i, page: page, group: "Sello \(stamp)", action: nil,
                                              kind: "Sello", text: pageSnippet(page), color: a.color, tags: []))
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

                let preset = store.nearestPreset(to: a.color)
                let group: String
                switch type {
                case "FreeText", "Text": group = "Comentarios"
                case "Ink", "Line", "Circle": group = preset?.name ?? "Dibujos y flechas"
                default: group = preset?.name ?? "Otros"
                }
                out.append(AnnotationItem(pageIndex: i, page: page, group: group, action: preset?.action,
                                          kind: kind, text: text, color: a.color,
                                          tags: AnnotationTags.tags(of: a)))
            }
        }
        return out
    }

    /// Primer renglón con texto de la página (para identificar dónde está un sello).
    private static func pageSnippet(_ page: PDFPage) -> String {
        let text = page.string ?? ""
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count > 12 } ?? ""
        return String(line.prefix(120))
    }

    /// Resumen en Markdown agrupado por acción de repaso — listo para Anki o Notas.
    private func markdown() -> String {
        var md = "# Resumen de marcas\n"
        if let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            md += "_\(title)_\n"
        }
        let source = filtered
        for action in ReviewAction.allCases {
            let section = source.filter { ($0.action ?? .none) == action && !$0.group.hasPrefix("Sello") && $0.group != "Comentarios" }
            guard !section.isEmpty else { continue }
            md += "\n## \(action.sectionTitle)\n"
            for item in section {
                let tags = item.tags.isEmpty ? "" : " `" + item.tags.joined(separator: "` `") + "`"
                let text = item.text.isEmpty ? "(\(item.kind.lowercased()))" : item.text
                md += "- **p. \(item.pageIndex + 1)** — \(text)\(tags)\n"
            }
        }
        let comments = source.filter { $0.group == "Comentarios" }
        if !comments.isEmpty {
            md += "\n## Comentarios\n"
            for item in comments { md += "- **p. \(item.pageIndex + 1)** — \(item.text)\n" }
        }
        let stamps = source.filter { $0.group.hasPrefix("Sello") }
        if !stamps.isEmpty {
            md += "\n## Sellos\n"
            for item in stamps { md += "- **p. \(item.pageIndex + 1)** · \(item.group) — \(item.text)\n" }
        }
        return md
    }
}
