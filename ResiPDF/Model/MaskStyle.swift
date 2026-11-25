import UIKit
import PDFKit

/// "Tapas" para autoevaluación (como cinta adhesiva sobre las etiquetas de un atlas):
/// se dibuja un rectángulo opaco y un toque lo destapa / vuelve a tapar.
/// Al guardar, todas las tapas se guardan TAPADAS.
enum MaskStyle {
    static let prefix = "resimask:"
    static let fill = UIColor(hex: "#E9DFC4")
    static let border = UIColor(hex: "#B8A77A")

    static func isMask(_ a: PDFAnnotation) -> Bool {
        (a.value(forAnnotationKey: .name) as? String)?.hasPrefix(prefix) == true
    }

    static func isRevealed(_ a: PDFAnnotation) -> Bool {
        a.interiorColor == nil
    }

    static func setRevealed(_ a: PDFAnnotation, _ revealed: Bool) {
        a.interiorColor = revealed ? nil : fill
    }

    static func allMasks(in pdf: PDFDocument) -> [PDFAnnotation] {
        var out: [PDFAnnotation] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            out.append(contentsOf: page.annotations.filter(isMask))
        }
        return out
    }

    /// Tapa todas y devuelve las que estaban destapadas (para restaurarlas tras guardar).
    static func coverAll(in pdf: PDFDocument) -> [PDFAnnotation] {
        let revealed = allMasks(in: pdf).filter(isRevealed)
        revealed.forEach { setRevealed($0, false) }
        return revealed
    }

    static func setAll(in pdf: PDFDocument, revealed: Bool) {
        allMasks(in: pdf).forEach { setRevealed($0, revealed) }
    }
}
