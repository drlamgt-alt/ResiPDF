import UIKit
import PDFKit

/// Medidas de la hoja (en puntos de la hoja, no de la pantalla).
struct PaperLayout {
    let size: CGSize
    var header: CGFloat { 90 }
    var lineSpacing: CGFloat { 34 }
    var gridSpacing: CGFloat { 28 }
    /// Columna izquierda del método Cornell (preguntas y palabras clave).
    var cueWidth: CGFloat { size.width * 0.30 }
    /// Inicio de la franja de resumen (Cornell).
    var summaryTop: CGFloat { size.height * 0.78 }
}

/// Dibuja el papel de una hoja. Se usa en pantalla y al exportar a PDF.
enum PaperRenderer {
    private static let line = UIColor(red: 0.72, green: 0.80, blue: 0.92, alpha: 1)
    private static let accent = UIColor(red: 0.86, green: 0.38, blue: 0.42, alpha: 0.85)
    private static let labelColor = UIColor(white: 0.55, alpha: 1)

    /// Secciones de la plantilla «Caso clínico» (título y número de renglones).
    static let clinicalSections: [(String, Int)] = [
        ("PACIENTE Y MOTIVO DE CONSULTA", 2),
        ("HISTORIA CLÍNICA", 4),
        ("EXPLORACIÓN FÍSICA", 3),
        ("ESTUDIOS · LABORATORIO E IMAGEN", 3),
        ("DIAGNÓSTICO Y DIFERENCIALES", 3),
        ("TRATAMIENTO · TÉCNICA QUIRÚRGICA", 4),
        ("COMPLICACIONES", 2),
        ("PERLAS PARA EL EXAMEN", 2),
    ]

    static func draw(_ paper: PaperStyle, title: String, tint: PaperTint = .white,
                     in rect: CGRect, context cg: CGContext) {
        let layout = PaperLayout(size: rect.size)
        tint.color.setFill()
        cg.fill(rect)

        if !title.isEmpty {
            (title as NSString).draw(at: CGPoint(x: 40, y: 32), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor(white: 0.25, alpha: 1),
            ])
        }

        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setLineWidth(1)

        switch paper {
        case .blank:
            break
        case .lined:
            horizontalLines(cg, from: layout.header, to: rect.maxY - 40, x0: 0, x1: rect.maxX, spacing: layout.lineSpacing)
            cg.setStrokeColor(accent.cgColor)
            cg.move(to: CGPoint(x: 70, y: layout.header - 20))
            cg.addLine(to: CGPoint(x: 70, y: rect.maxY))
            cg.strokePath()
        case .grid:
            cg.setStrokeColor(line.withAlphaComponent(0.6).cgColor)
            var x = layout.gridSpacing
            while x < rect.maxX {
                cg.move(to: CGPoint(x: x, y: layout.header))
                cg.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += layout.gridSpacing
            }
            var y = layout.header
            while y < rect.maxY {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += layout.gridSpacing
            }
            cg.strokePath()
        case .dotted:
            cg.setFillColor(line.cgColor)
            var y = layout.header
            while y < rect.maxY {
                var x = layout.gridSpacing
                while x < rect.maxX {
                    cg.fillEllipse(in: CGRect(x: x - 1.3, y: y - 1.3, width: 2.6, height: 2.6))
                    x += layout.gridSpacing
                }
                y += layout.gridSpacing
            }
        case .cornell:
            let cue = layout.cueWidth
            let summary = layout.summaryTop
            horizontalLines(cg, from: layout.header + layout.lineSpacing, to: summary - 8,
                            x0: 0, x1: rect.maxX, spacing: layout.lineSpacing)
            horizontalLines(cg, from: summary + layout.lineSpacing + 10, to: rect.maxY - 20,
                            x0: 0, x1: rect.maxX, spacing: layout.lineSpacing)
            cg.setStrokeColor(accent.cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: 0, y: layout.header))
            cg.addLine(to: CGPoint(x: rect.maxX, y: layout.header))
            cg.move(to: CGPoint(x: cue, y: layout.header))
            cg.addLine(to: CGPoint(x: cue, y: summary))
            cg.move(to: CGPoint(x: 0, y: summary))
            cg.addLine(to: CGPoint(x: rect.maxX, y: summary))
            cg.strokePath()
            label("PREGUNTAS Y CLAVES", at: CGPoint(x: 16, y: layout.header + 8))
            label("NOTAS", at: CGPoint(x: cue + 14, y: layout.header + 8))
            label("RESUMEN CON TUS PALABRAS", at: CGPoint(x: 16, y: summary + 8))
        case .clinicalCase:
            var y = layout.header
            for (name, lines) in clinicalSections {
                cg.setStrokeColor(accent.cgColor)
                cg.setLineWidth(1.2)
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: rect.maxX, y: y))
                cg.strokePath()
                label(name, at: CGPoint(x: 18, y: y + 7))
                let first = y + 26 + layout.lineSpacing
                horizontalLines(cg, from: first, to: first + CGFloat(lines) * layout.lineSpacing - 1,
                                x0: 18, x1: rect.maxX - 18, spacing: layout.lineSpacing)
                y = first + CGFloat(lines - 1) * layout.lineSpacing + 14
            }
        case .qa:
            let block: CGFloat = layout.lineSpacing * 5 + 22
            var y = layout.header + 10
            var n = 1
            while y + block <= rect.maxY - 10 {
                // Pregunta
                cg.setFillColor(accent.withAlphaComponent(0.12).cgColor)
                cg.fill(CGRect(x: 16, y: y, width: rect.width - 32, height: layout.lineSpacing * 2))
                label("P\(n)", at: CGPoint(x: 24, y: y + 6))
                horizontalLines(cg, from: y + layout.lineSpacing, to: y + layout.lineSpacing * 2 + 1,
                                x0: 60, x1: rect.maxX - 24, spacing: layout.lineSpacing)
                // Respuesta (para taparla y autoevaluarte)
                let r = y + layout.lineSpacing * 2 + 6
                label("R", at: CGPoint(x: 26, y: r + 6))
                cg.setStrokeColor(line.cgColor)
                cg.setLineDash(phase: 0, lengths: [4, 4])
                cg.stroke(CGRect(x: 16, y: r, width: rect.width - 32, height: layout.lineSpacing * 3))
                cg.setLineDash(phase: 0, lengths: [])
                horizontalLines(cg, from: r + layout.lineSpacing, to: r + layout.lineSpacing * 3 - 1,
                                x0: 60, x1: rect.maxX - 24, spacing: layout.lineSpacing)
                y += block
                n += 1
            }
        }
    }

    private static func horizontalLines(_ cg: CGContext, from y0: CGFloat, to y1: CGFloat,
                                        x0: CGFloat, x1: CGFloat, spacing: CGFloat) {
        cg.setStrokeColor(line.cgColor)
        cg.setLineWidth(1)
        var y = y0
        while y < y1 {
            cg.move(to: CGPoint(x: x0, y: y))
            cg.addLine(to: CGPoint(x: x1, y: y))
            y += spacing
        }
        cg.strokePath()
    }

    private static func label(_ text: String, at point: CGPoint) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: labelColor,
            .kern: 0.8,
        ])
    }
}

/// Vista con el papel de la hoja (debajo de los trazos).
final class PaperView: UIView {
    var paper: PaperStyle = .cornell { didSet { if paper != oldValue { setNeedsDisplay() } } }
    var title: String = "" { didSet { if title != oldValue { setNeedsDisplay() } } }
    var tint: PaperTint = .white { didSet { if tint != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        PaperRenderer.draw(paper, title: title, tint: tint, in: bounds, context: cg)
    }
}

/// Recorta una zona de una página del PDF como imagen nítida.
enum FigureCropper {
    static func image(of page: PDFPage, rect: CGRect, scale: CGFloat = 3) -> UIImage? {
        let r = rect.standardized.intersection(page.bounds(for: .mediaBox))
        guard !r.isNull, r.width > 8, r.height > 8 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let px = CGSize(width: (r.width * scale).rounded(), height: (r.height * scale).rounded())
        return UIGraphicsImageRenderer(size: px, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: px))
            let cg = ctx.cgContext
            // Coordenadas PDF (origen abajo a la izquierda) → imagen (origen arriba).
            cg.translateBy(x: 0, y: px.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -r.minX, y: -r.minY)
            page.draw(with: .mediaBox, to: cg)
        }
    }
}
