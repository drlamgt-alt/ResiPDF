import UIKit
import PDFKit
import PencilKit

/// Cuaderno de ejemplo para las capturas: hoja Cornell con «escritura» del Pencil y una figura recortada.
enum DemoNotebook {
    static func populate(_ store: NotebookStore, pdf: PDFDocument) {
        store.resetForDemo()
        store.create()
        guard let pageID = store.pages.first?.id else { return }
        store.renamePage(pageID, to: "Apendicitis — clase 1")

        // Figura recortada: la sección «Diagnóstico» del capítulo.
        if let sel = pdf.findString("Diagnóstico", withOptions: []).first,
           let page = sel.pages.first {
            let top = sel.bounds(for: page).maxY + 6
            let rect = CGRect(x: 52, y: top - 112, width: 508, height: 112)
            if let image = FigureCropper.image(of: page, rect: rect),
               let figure = store.addFigure(image, sourcePage: pdf.index(for: page)) {
                store.insert(figure, into: pageID)
            }
        }

        let layout = PaperLayout(size: Notebook.pageSize)
        var strokes: [PKStroke] = []
        let ink = PKInk(.pen, color: UIColor(red: 0.10, green: 0.18, blue: 0.45, alpha: 1))
        let red = PKInk(.pen, color: UIColor(red: 0.80, green: 0.15, blue: 0.20, alpha: 1))

        // Columna de preguntas (Cornell)
        var y = layout.header + 2 * layout.lineSpacing - 8
        for words in [[40, 55, 30], [60, 45], [35, 50, 40], [70, 30]] {
            strokes += scribble(x: 18, y: y, words: words, ink: red)
            y += layout.lineSpacing * 2
        }
        // Notas (debajo de la figura)
        y = layout.header + 24 + 150 + layout.lineSpacing
        for words in [[60, 80, 45, 90], [50, 70, 110], [90, 40, 75, 60], [45, 95, 70], [80, 55, 100, 40], [70, 60]] {
            strokes += scribble(x: layout.cueWidth + 20, y: y, words: words, ink: ink)
            y += layout.lineSpacing
        }
        // Resumen
        y = layout.summaryTop + layout.lineSpacing + 2
        for words in [[70, 90, 60, 110, 80, 50], [95, 60, 85, 70]] {
            strokes += scribble(x: 24, y: y, words: words, ink: ink)
            y += layout.lineSpacing
        }
        store.updateDrawing(pageID, PKDrawing(strokes: strokes).dataRepresentation())
        store.addPage(.grid, after: pageID)
        store.currentPageID = pageID
        store.saveNow()
    }

    /// Simula palabras manuscritas con ondas cortas sobre un renglón.
    private static func scribble(x: CGFloat, y: CGFloat, words: [CGFloat], ink: PKInk) -> [PKStroke] {
        var strokes: [PKStroke] = []
        var cursor = x
        var seed: CGFloat = x * 0.37 + y * 0.11
        for width in words {
            var points: [PKStrokePoint] = []
            var t: CGFloat = 0
            while t <= width {
                seed += 0.9
                let amp = 5 + 3 * sin(seed * 1.7)
                let py = y - 8 - amp * sin(t / 3.2) + 2 * sin(t / 11)
                points.append(PKStrokePoint(location: CGPoint(x: cursor + t, y: py),
                                            timeOffset: TimeInterval(t) / 300,
                                            size: CGSize(width: 2.4, height: 2.4),
                                            opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
                t += 1.5
            }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            strokes.append(PKStroke(ink: ink, path: path))
            cursor += width + 14
        }
        return strokes
    }
}
