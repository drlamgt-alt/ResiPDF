import UIKit
import PencilKit

/// Exporta el cuaderno completo (hojas + anexos) a un PDF para compartir o imprimir.
enum NotebookExporter {
    static func export(store: NotebookStore, items: [AnnotationItem]) throws -> URL {
        guard let nb = store.notebook else { throw CocoaError(.fileNoSuchFile) }
        let size = Notebook.pageSize
        let rect = CGRect(origin: .zero, size: size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cuaderno - \(NotebookStore.safeName(nb.bookTitle)).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: rect)

        try renderer.writePDF(to: url) { ctx in
            // Hojas escritas a mano
            for page in nb.pages {
                ctx.beginPage()
                PaperRenderer.draw(page.paper, title: page.title, in: rect, context: ctx.cgContext)
                for image in page.images {
                    store.image(named: image.file)?.draw(in: image.frame)
                }
                if let drawing = try? PKDrawing(data: page.drawing) {
                    var ink: UIImage?
                    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                        ink = drawing.image(from: rect, scale: 2)
                    }
                    ink?.draw(in: rect)
                }
            }

            // Anexos
            var pager = TextPager(context: ctx, size: size)
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
                let list = items.filter { $0.action == kind.action && !$0.group.hasPrefix("Sello") && $0.group != "Comentarios" }
                guard !list.isEmpty else { continue }
                pager.newPage()
                pager.heading("Anexo \(kind.letter) · \(kind.title)")
                for (n, item) in list.enumerated() {
                    let text = item.text.isEmpty ? "(\(item.kind.lowercased()))" : item.text
                    let tags = item.tags.isEmpty ? "" : "  [" + item.tags.joined(separator: ", ") + "]"
                    pager.paragraph("\(n + 1). \(text)", note: "p. \(item.pageIndex + 1)\(tags)")
                }
            }
        }
        return url
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
