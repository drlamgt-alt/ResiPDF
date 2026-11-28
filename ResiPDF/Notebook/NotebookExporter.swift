import UIKit
import PencilKit

/// Exporta el cuaderno en varios formatos para compartir, imprimir o estudiar en otras apps.
enum NotebookExporter {
    enum Format: String, CaseIterable, Identifiable {
        case pdf, pdfPages, images, markdown, anki, text

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pdf: return "PDF completo"
            case .pdfPages: return "PDF solo con las hojas"
            case .images: return "Imágenes (PNG)"
            case .markdown: return "Guía en Markdown"
            case .anki: return "Tarjetas para Anki"
            case .text: return "Texto"
            }
        }

        var hint: String {
            switch self {
            case .pdf: return "Hojas, guía de estudio y anexos"
            case .pdfPages: return "Lo que escribiste a mano"
            case .images: return "Una imagen por hoja"
            case .markdown: return "Para Notas, Obsidian o Notion"
            case .anki: return "Preguntas → tarjetas (TSV)"
            case .text: return "Guía y anexos en texto plano"
            }
        }

        var symbol: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .pdfPages: return "doc"
            case .images: return "photo.on.rectangle"
            case .markdown: return "text.alignleft"
            case .anki: return "rectangle.on.rectangle.angled"
            case .text: return "doc.plaintext"
            }
        }
    }

    static func export(store: NotebookStore, format: Format) throws -> [URL] {
        guard let nb = store.notebook else { throw CocoaError(.fileNoSuchFile) }
        let base = "Cuaderno - " + NotebookStore.safeName(nb.bookTitle)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exportar", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        switch format {
        case .pdf:
            return [try pdf(nb, store: store, to: folder.appendingPathComponent(base + ".pdf"), includeGuide: true)]
        case .pdfPages:
            return [try pdf(nb, store: store, to: folder.appendingPathComponent(base + " (hojas).pdf"), includeGuide: false)]
        case .images:
            return try nb.pages.enumerated().compactMap { index, page in
                guard let data = render(page, store: store, scale: 2)?.pngData() else { return nil }
                let url = folder.appendingPathComponent(String(format: "%@ - hoja %02d.png", base, index + 1))
                try data.write(to: url)
                return url
            }
        case .markdown:
            let url = folder.appendingPathComponent(base + ".md")
            try markdown(nb).write(to: url, atomically: true, encoding: .utf8)
            return [url]
        case .anki:
            let url = folder.appendingPathComponent(base + " - Anki.txt")
            try anki(nb).write(to: url, atomically: true, encoding: .utf8)
            return [url]
        case .text:
            let url = folder.appendingPathComponent(base + ".txt")
            try plainText(nb).write(to: url, atomically: true, encoding: .utf8)
            return [url]
        }
    }

    // MARK: - Una hoja como imagen

    static func render(_ page: NotebookPage, store: NotebookStore?, scale: CGFloat) -> UIImage? {
        let size = Notebook.pageSize
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let ink = inkImage(page, rect: rect, scale: scale)
        return UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale),
                                       format: format).image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            drawPage(page, store: store, ink: ink, in: rect, context: ctx.cgContext)
        }
    }

    private static func inkImage(_ page: NotebookPage, rect: CGRect, scale: CGFloat) -> UIImage? {
        guard let drawing = try? PKDrawing(data: page.drawing), !drawing.strokes.isEmpty else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }

    private static func drawPage(_ page: NotebookPage, store: NotebookStore?, ink: UIImage?,
                                 in rect: CGRect, context: CGContext) {
        PaperRenderer.draw(page.paper, title: page.title, tint: page.tint, in: rect, context: context)
        for image in page.images {
            store?.image(named: image.file)?.draw(in: image.frame)
        }
        ink?.draw(in: rect)
    }

    // MARK: - PDF

    private static func pdf(_ nb: Notebook, store: NotebookStore, to url: URL, includeGuide: Bool) throws -> URL {
        let size = Notebook.pageSize
        let rect = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsPDFRenderer(bounds: rect)

        try renderer.writePDF(to: url) { ctx in
            for page in nb.pages {
                ctx.beginPage()
                drawPage(page, store: store, ink: inkImage(page, rect: rect, scale: 2), in: rect, context: ctx.cgContext)
            }
            guard includeGuide else { return }
            var pager = TextPager(context: ctx, size: size)

            // Guía de estudio por temas
            let sections = StudyGuide.sections(nb.studyMarks)
            if !sections.isEmpty {
                pager.newPage()
                pager.heading("Guía de estudio")
                for (n, section) in sections.enumerated() {
                    pager.subheading("\(n + 1). \(section.topic)")
                    for mark in section.marks {
                        let check = nb.reviewed.contains(mark.id) ? "☑︎" : "☐"
                        pager.paragraph("\(check) \(StudyGuide.label(for: mark.action)): \(mark.displayText)",
                                        note: note(mark))
                    }
                }
            }

            // Anexos
            for kind in AnnexKind.allCases {
                if kind == .figures {
                    guard !nb.figures.isEmpty else { continue }
                    pager.newPage()
                    pager.heading("Anexo \(kind.letter) · \(kind.title)")
                    for figure in nb.figures {
                        if let img = store.image(named: figure.file) {
                            pager.image(img, caption: figure.caption)
                        }
                    }
                    continue
                }
                let list = AnnexView.entries(kind, in: nb.marks)
                guard !list.isEmpty else { continue }
                pager.newPage()
                pager.heading("Anexo \(kind.letter) · \(kind.title)")
                for (n, mark) in list.enumerated() {
                    pager.paragraph("\(n + 1). \(mark.displayText)", note: note(mark))
                }
            }
        }
        return url
    }

    private static func note(_ mark: StudyMark) -> String {
        let tags = mark.tags.isEmpty ? "" : "  [" + mark.tags.joined(separator: ", ") + "]"
        return "p. \(mark.pageIndex + 1) · \(mark.topic)\(tags)"
    }

    // MARK: - Texto

    private static func markdown(_ nb: Notebook) -> String {
        var out = "# \(nb.bookTitle)\n\n"
        let sections = StudyGuide.sections(nb.studyMarks)
        if !sections.isEmpty {
            out += "## Guía de estudio\n\n"
            for (n, section) in sections.enumerated() {
                out += "### \(n + 1). \(section.topic)\n\n"
                for mark in section.marks {
                    let check = nb.reviewed.contains(mark.id) ? "x" : " "
                    let tags = mark.tags.map { "#\($0.replacingOccurrences(of: " ", with: "_"))" }.joined(separator: " ")
                    out += "- [\(check)] **\(StudyGuide.label(for: mark.action))** \(mark.displayText) _(p. \(mark.pageIndex + 1))_ \(tags)\n"
                }
                out += "\n"
            }
        }
        for kind in AnnexKind.allCases where kind != .figures {
            let list = AnnexView.entries(kind, in: nb.marks)
            guard !list.isEmpty else { continue }
            out += "## Anexo \(kind.letter) · \(kind.title)\n\n"
            for (n, mark) in list.enumerated() {
                out += "\(n + 1). \(mark.displayText) _(p. \(mark.pageIndex + 1))_\n"
            }
            out += "\n"
        }
        if !nb.figures.isEmpty {
            out += "## Anexo C · Figuras\n\n"
            for f in nb.figures { out += "- \(f.caption)\n" }
        }
        return out
    }

    private static func plainText(_ nb: Notebook) -> String {
        markdown(nb)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "_(", with: "(")
            .replacingOccurrences(of: ")_", with: ")")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "- [x]", with: "✓")
            .replacingOccurrences(of: "- [ ]", with: "•")
    }

    /// TSV para importar en Anki: anverso = la marca, reverso = tema y página, etiquetas = tus etiquetas.
    private static func anki(_ nb: Notebook) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
        }
        var out = "#separator:tab\n#html:false\n#tags column:3\n"
        let cards = nb.studyMarks.filter { $0.action == .question || $0.action == .memorize }
        for mark in cards {
            let front = clean(mark.displayText)
            let back = clean("\(mark.topic) · \(nb.bookTitle), p. \(mark.pageIndex + 1)")
            let tags = (["ResiPDF", StudyGuide.label(for: mark.action)] + mark.tags)
                .map { $0.replacingOccurrences(of: " ", with: "_") }
                .joined(separator: " ")
            out += "\(front)\t\(back)\t\(tags)\n"
        }
        return out
    }
}

/// Escribe texto e imágenes en páginas del PDF, pasando de página cuando no cabe.
private struct TextPager {
    let context: UIGraphicsPDFRendererContext
    let size: CGSize
    let margin: CGFloat = 56
    var y: CGFloat = 0

    init(context: UIGraphicsPDFRendererContext, size: CGSize) {
        self.context = context
        self.size = size
    }

    private var width: CGFloat { size.width - margin * 2 }

    mutating func newPage() {
        context.beginPage()
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        y = margin
    }

    private mutating func ensure(_ height: CGFloat) {
        if y + height > size.height - margin { newPage() }
    }

    mutating func heading(_ text: String) {
        let s = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: UIColor.black,
        ])
        draw(s, spacing: 18)
    }

    mutating func subheading(_ text: String) {
        let s = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor(red: 0.2, green: 0.35, blue: 0.7, alpha: 1),
        ])
        ensure(60)
        y += 8
        draw(s, spacing: 10)
    }

    mutating func paragraph(_ text: String, note: String) {
        let s = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.black,
        ])
        s.append(NSAttributedString(string: "\n" + note, attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.gray,
        ]))
        draw(s, spacing: 12)
    }

    mutating func image(_ img: UIImage, caption: String) {
        let w = min(width, 520)
        let h = w * img.size.height / max(img.size.width, 1)
        ensure(h + 30)
        img.draw(in: CGRect(x: margin, y: y, width: w, height: h))
        y += h + 6
        let s = NSAttributedString(string: caption, attributes: [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.gray,
        ])
        draw(s, spacing: 18)
    }

    private mutating func draw(_ s: NSAttributedString, spacing: CGFloat) {
        let bounds = s.boundingRect(with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let h = ceil(bounds.height)
        ensure(h)
        s.draw(with: CGRect(x: margin, y: y, width: width, height: h),
               options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + spacing
    }
}
