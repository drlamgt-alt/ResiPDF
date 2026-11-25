import UIKit

/// Tipo de papel de una hoja del cuaderno.
enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case cornell, lined, grid, dotted, blank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cornell: return "Cornell"
        case .lined: return "Rayado"
        case .grid: return "Cuadrícula"
        case .dotted: return "Puntos"
        case .blank: return "En blanco"
        }
    }

    var symbol: String {
        switch self {
        case .cornell: return "rectangle.split.3x1"
        case .lined: return "line.3.horizontal"
        case .grid: return "squareshape.split.3x3"
        case .dotted: return "circle.grid.3x3"
        case .blank: return "doc"
        }
    }
}

/// Imagen colocada sobre una hoja (coordenadas de la hoja, en puntos).
struct NotebookImage: Codable, Identifiable, Hashable {
    var id = UUID()
    var file: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var sourcePage: Int?

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.width
            height = newValue.height
        }
    }
}

/// Una hoja del cuaderno: papel, trazos del Pencil (PencilKit) e imágenes.
struct NotebookPage: Codable, Identifiable {
    var id = UUID()
    var title: String
    var paper: PaperStyle
    var drawing = Data()
    var images: [NotebookImage] = []
    var created = Date()
}

/// Figura recortada del PDF (va al Anexo C).
struct NotebookFigure: Codable, Identifiable, Hashable {
    var id = UUID()
    var file: String
    var sourcePage: Int
    var caption: String
    var created = Date()
}

/// Cuaderno de un libro.
struct Notebook: Codable {
    var bookTitle: String
    var pages: [NotebookPage]
    var figures: [NotebookFigure] = []
    var created = Date()
    var modified = Date()

    /// Tamaño lógico de cada hoja (proporción A4). Es igual en iPad mini y Pro,
    /// así los trazos se ven idénticos en todos los dispositivos.
    static let pageSize = CGSize(width: 820, height: 1160)
}

/// Anexos que se llenan solos con las marcas del libro.
enum AnnexKind: String, CaseIterable, Identifiable {
    case questions, memorize, figures, doubts, ideas

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .questions: return "A"
        case .memorize: return "B"
        case .figures: return "C"
        case .doubts: return "D"
        case .ideas: return "E"
        }
    }

    var title: String {
        switch self {
        case .questions: return "Preguntas de examen"
        case .memorize: return "Para memorizar"
        case .figures: return "Figuras"
        case .doubts: return "Dudas"
        case .ideas: return "Ideas principales"
        }
    }

    var shortTitle: String {
        switch self {
        case .questions: return "Preguntas"
        case .memorize: return "Memorizar"
        case .figures: return "Figuras"
        case .doubts: return "Dudas"
        case .ideas: return "Ideas"
        }
    }

    var symbol: String {
        switch self {
        case .questions: return "questionmark.bubble"
        case .memorize: return "brain.head.profile"
        case .figures: return "photo.on.rectangle"
        case .doubts: return "exclamationmark.bubble"
        case .ideas: return "lightbulb"
        }
    }

    /// Acción de repaso cuyas marcas alimentan este anexo.
    var action: ReviewAction? {
        switch self {
        case .questions: return .question
        case .memorize: return .memorize
        case .figures: return nil
        case .doubts: return .doubt
        case .ideas: return .summary
        }
    }
}
