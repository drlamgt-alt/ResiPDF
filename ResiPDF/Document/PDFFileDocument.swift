import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Documento PDF editado "in place": se lee del archivo original y el
/// autoguardado de SwiftUI escribe las anotaciones de vuelta en ese archivo.
/// Las anotaciones son estándar PDF, así que se ven en Preview, Adobe, GoodNotes, etc.
final class PDFFileDocument: ReferenceFileDocument {
    typealias Snapshot = Data

    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    let pdf: PDFDocument

    init() {
        let doc = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        doc.insert(page, at: 0)
        pdf = doc
    }

    init(pdf: PDFDocument) {
        self.pdf = pdf
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let doc = PDFDocument(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        pdf = doc
    }

    func snapshot(contentType: UTType) throws -> Data {
        // Las tapas de autoevaluación siempre se guardan tapadas.
        let revealed = MaskStyle.coverAll(in: pdf)
        defer { revealed.forEach { MaskStyle.setRevealed($0, true) } }
        guard let data = pdf.dataRepresentation() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
