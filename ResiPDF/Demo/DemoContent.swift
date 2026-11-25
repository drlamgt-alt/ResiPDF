import UIKit
import PDFKit

/// Capítulo de ejemplo (texto propio) con anotaciones del perfil «Cirugía»,
/// para mostrar cómo se ve la app.
enum DemoContent {

    private enum Block {
        case title(String)
        case subtitle(String)
        case heading(String)
        case body(String)
    }

    private static let pages: [[Block]] = [
        [
            .title("Apendicitis aguda"),
            .subtitle("Capítulo de ejemplo · ResiPDF"),
            .heading("Epidemiología"),
            .body("La apendicitis aguda es la urgencia quirúrgica abdominal más frecuente en el mundo. Afecta con mayor frecuencia a personas entre los 10 y los 30 años, con un ligero predominio en varones. El riesgo de padecerla a lo largo de la vida se estima en alrededor del 7 a 8 %."),
            .heading("Anatomía quirúrgica"),
            .body("El apéndice nace de la cara posteromedial del ciego, en el punto donde convergen las tres tenias del colon. Su irrigación depende de la arteria apendicular, rama de la arteria ileocólica, que discurre por el borde libre del mesoapéndice. La posición retrocecal es la más común y puede retrasar el diagnóstico."),
            .heading("Cuadro clínico"),
            .body("El cuadro típico comienza con dolor periumbilical difuso que, en las siguientes horas, migra a la fosa ilíaca derecha. Se acompaña de anorexia, náusea y fiebre de bajo grado. A la exploración destaca el dolor en el punto de McBurney y el signo de Blumberg (rebote) positivo."),
            .heading("Diagnóstico"),
            .body("El diagnóstico es fundamentalmente clínico. La escala de Alvarado ayuda a estratificar el riesgo: una puntuación de 7 o más sugiere apendicitis probable. La ecografía es el estudio inicial en niños y embarazadas; la tomografía con contraste es el estudio de mayor sensibilidad en adultos."),
        ],
        [
            .heading("Tratamiento"),
            .body("El tratamiento de elección es la apendicectomía, preferentemente laparoscópica. Debe administrarse profilaxis antibiótica dentro de los 60 minutos previos a la incisión. Los pasos clave son la identificación de la base apendicular, la ligadura de la arteria apendicular y la sección del apéndice sobre la base."),
            .heading("Complicaciones"),
            .body("La perforación es la complicación más grave y se asocia a peritonitis generalizada. Ante un plastrón o absceso apendicular bien delimitado, el manejo inicial puede ser antibioticoterapia y drenaje percutáneo, con apendicectomía de intervalo. La infección del sitio quirúrgico es la complicación postoperatoria más frecuente."),
            .heading("Puntos clave para el examen"),
            .body("Dolor que migra de periumbilical a fosa ilíaca derecha. Alvarado de 7 o más: apendicitis probable. Ecografía en niños y embarazadas; tomografía en adultos. Profilaxis antibiótica 60 minutos antes de la incisión."),
        ],
    ]

    static func makeDocument() -> PDFFileDocument {
        let pdf = PDFDocument(data: renderPDF()) ?? PDFDocument()
        annotate(pdf)
        return PDFFileDocument(pdf: pdf)
    }

    // MARK: - Generar el PDF

    private static func attributes(for block: Block) -> (String, [NSAttributedString.Key: Any], CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let serif = UIFont(name: "Georgia", size: 12.5) ?? UIFont.systemFont(ofSize: 12.5)
        switch block {
        case .title(let t):
            return (t, [.font: UIFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: UIColor.black], 4)
        case .subtitle(let t):
            return (t, [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.darkGray], 22)
        case .heading(let t):
            return (t, [.font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                        .foregroundColor: UIColor(red: 0.20, green: 0.16, blue: 0.45, alpha: 1)], 6)
        case .body(let t):
            return (t, [.font: serif, .foregroundColor: UIColor.black, .paragraphStyle: paragraph], 16)
        }
    }

    private static func renderPDF() -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage()
                var y: CGFloat = 64
                for block in page {
                    let (text, attrs, spacing) = attributes(for: block)
                    let string = NSAttributedString(string: text, attributes: attrs)
                    let size = string.boundingRect(with: CGSize(width: 492, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                   context: nil).size
                    let rect = CGRect(x: 60, y: y, width: 492, height: ceil(size.height))
                    string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    y += ceil(size.height) + spacing
                }
            }
        }
    }

    // MARK: - Anotaciones de ejemplo

    private static func annotate(_ pdf: PDFDocument) {
        let p = PresetProfile.surgery.presets
        // 0 clave · 1 pregunta · 2 indicación · 3 técnica · 4 anatomía · 5 escalas
        // 6 complicaciones · 7 cifras · 8 repasar
        mark(pdf, "la urgencia quirúrgica abdominal más frecuente", p[0])
        mark(pdf, "entre los 10 y los 30 años", p[7])
        let artery = mark(pdf, "arteria apendicular, rama de la arteria ileocólica", p[4])
        let retrocecal = mark(pdf, "La posición retrocecal es la más común", p[8])
        mark(pdf, "migra a la fosa ilíaca derecha", p[0])
        mark(pdf, "signo de Blumberg", p[5])
        mark(pdf, "La escala de Alvarado", p[5])
        let question = mark(pdf, "una puntuación de 7 o más sugiere apendicitis probable", p[1])
        mark(pdf, "El tratamiento de elección es la apendicectomía", p[2])
        mark(pdf, "dentro de los 60 minutos previos a la incisión", p[7])
        mark(pdf, "la ligadura de la arteria apendicular", p[3])
        mark(pdf, "La perforación es la complicación más grave", p[6])
        mark(pdf, "La infección del sitio quirúrgico", p[6])
        mark(pdf, "apendicectomía de intervalo", p[2])

        guard let page1 = pdf.page(at: 0) else { return }

        // Flecha en el margen: arteria apendicular → posición retrocecal
        if let a = artery, let b = retrocecal {
            let start = CGPoint(x: 572, y: a.page.midY)
            let end = CGPoint(x: 572, y: b.page.midY + 4)
            let bounds = CGRect(x: 552, y: min(start.y, end.y) - 12, width: 40, height: abs(start.y - end.y) + 24)
            let arrow = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
            arrow.startPoint = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
            arrow.endPoint = CGPoint(x: end.x - bounds.minX, y: end.y - bounds.minY)
            arrow.endLineStyle = .closedArrow
            arrow.color = p[4].color
            arrow.interiorColor = p[4].color
            arrow.border = border(2)
            page1.addAnnotation(arrow)
        }

        // Sello «Q» junto a la pregunta de examen
        if let q = question {
            let stamp = PDFAnnotation(bounds: CGRect(x: 22, y: q.page.midY - 9, width: 26, height: 18),
                                      forType: .freeText, withProperties: nil)
            stamp.contents = "Q"
            stamp.font = UIFont.boldSystemFont(ofSize: 13)
            stamp.fontColor = .black
            stamp.color = p[1].color.withAlphaComponent(0.35)
            stamp.alignment = .center
            stamp.border = border(0.8)
            stamp.setValue(AnnotationController.stampPrefix + "demo", forAnnotationKey: .name)
            page1.addAnnotation(stamp)
        }

        // Círculo alrededor de «McBurney»
        if let sel = pdf.findString("McBurney", withOptions: .caseInsensitive).first,
           let page = sel.pages.first {
            let r = sel.bounds(for: page).insetBy(dx: -6, dy: -5)
            let circle = PDFAnnotation(bounds: r, forType: .circle, withProperties: nil)
            circle.color = p[6].color
            circle.border = border(1.6)
            page.addAnnotation(circle)
        }

        // Comentario (mnemotecnia)
        let note = PDFAnnotation(bounds: CGRect(x: 330, y: 70, width: 222, height: 44),
                                 forType: .freeText, withProperties: nil)
        note.contents = "Alvarado = MANTRELS (Migración, Anorexia, Náusea, Tenderness FID, Rebote, Elevación T°, Leucocitosis, Shift)"
        note.font = UIFont.systemFont(ofSize: 9)
        note.fontColor = .black
        note.color = p[0].color.withAlphaComponent(0.25)
        note.alignment = .left
        note.border = border(0.8)
        page1.addAnnotation(note)

        // Tapa de autoevaluación sobre la cifra en «Puntos clave»
        if let sel = pdf.findString("7 o más: apendicitis probable", withOptions: .caseInsensitive).first,
           let page = sel.pages.first {
            for line in sel.selectionsByLine() {
                let mask = PDFAnnotation(bounds: line.bounds(for: page).insetBy(dx: -2, dy: -1),
                                         forType: .square, withProperties: nil)
                mask.color = MaskStyle.border
                mask.interiorColor = MaskStyle.fill
                mask.border = border(0.5)
                mask.setValue(MaskStyle.prefix + UUID().uuidString, forAnnotationKey: .name)
                page.addAnnotation(mask)
            }
        }
    }

    private struct Marked {
        let page: CGRect
    }

    /// Marca una frase con el estilo del marcador. Devuelve el rectángulo que ocupa.
    @discardableResult
    private static func mark(_ pdf: PDFDocument, _ phrase: String, _ preset: MarkPreset) -> Marked? {
        guard let sel = pdf.findString(phrase, withOptions: .caseInsensitive).first,
              let page = sel.pages.first else { return nil }
        var union = CGRect.null
        let group = AnnotationController.groupPrefix + UUID().uuidString
        for (i, line) in sel.selectionsByLine().enumerated() {
            let r = line.bounds(for: page)
            let type: PDFAnnotationSubtype
            switch preset.style {
            case .highlight: type = .highlight
            case .underline: type = .underline
            case .strikeOut: type = .strikeOut
            case .box: type = .square
            }
            let a = PDFAnnotation(bounds: r, forType: type, withProperties: nil)
            a.color = preset.style == .highlight ? preset.color.withAlphaComponent(0.45) : preset.color
            if type != .square {
                a.quadrilateralPoints = [
                    NSValue(cgPoint: CGPoint(x: 0, y: r.height)),
                    NSValue(cgPoint: CGPoint(x: r.width, y: r.height)),
                    NSValue(cgPoint: CGPoint(x: 0, y: 0)),
                    NSValue(cgPoint: CGPoint(x: r.width, y: 0)),
                ]
            }
            a.setValue("\(group)#\(i)", forAnnotationKey: .name)
            if i == 0 { a.contents = phrase }
            page.addAnnotation(a)
            union = union.union(r)
        }
        return union.isNull ? nil : Marked(page: union)
    }

    private static func border(_ width: CGFloat) -> PDFBorder {
        let b = PDFBorder()
        b.lineWidth = width
        return b
    }
}
