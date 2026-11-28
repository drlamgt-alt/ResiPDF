import UIKit

/// Plantilla de una hoja del cuaderno.
enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case cornell, clinicalCase, qa, lined, grid, dotted, blank

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cornell: return "Cornell"
        case .clinicalCase: return "Caso clínico"
        case .qa: return "Preguntas y respuestas"
        case .lined: return "Rayado"
        case .grid: return "Cuadrícula"
        case .dotted: return "Puntos"
        case .blank: return "En blanco"
        }
    }

    var symbol: String {
        switch self {
        case .cornell: return "rectangle.split.3x1"
        case .clinicalCase: return "stethoscope"
        case .qa: return "questionmark.square.dashed"
        case .lined: return "line.3.horizontal"
        case .grid: return "squareshape.split.3x3"
        case .dotted: return "circle.grid.3x3"
        case .blank: return "doc"
        }
    }

    /// Para qué sirve (se muestra al elegir plantilla).
    var hint: String {
        switch self {
        case .cornell: return "Notas, preguntas clave y resumen"
        case .clinicalCase: return "Paciente, Dx, Tx y complicaciones"
        case .qa: return "Autoevaluación: tapa la respuesta"
        case .lined: return "Apuntes libres"
        case .grid: return "Esquemas y tablas"
        case .dotted: return "Mapas y diagramas"
        case .blank: return "Dibujos y anatomía"
        }
    }
}

/// Color del papel.
enum PaperTint: String, Codable, CaseIterable, Identifiable {
    case white, cream, blue, green, gray, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: return "Blanco"
        case .cream: return "Crema"
        case .blue: return "Azul suave"
        case .green: return "Verde suave"
        case .gray: return "Gris claro"
        case .night: return "Noche"
        }
    }

    var color: UIColor {
        switch self {
        case .white: return .white
        case .cream: return UIColor(red: 0.992, green: 0.972, blue: 0.918, alpha: 1)
        case .blue: return UIColor(red: 0.937, green: 0.957, blue: 0.992, alpha: 1)
        case .green: return UIColor(red: 0.937, green: 0.976, blue: 0.945, alpha: 1)
        case .gray: return UIColor(white: 0.95, alpha: 1)
        case .night: return UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
        }
    }

    /// Papel oscuro: la tinta del Pencil se muestra clara (PencilKit la adapta sola).
    var isDark: Bool { self == .night }
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
    var tint: PaperTint = .white
    var drawing = Data()
    var images: [NotebookImage] = []
    var created = Date()

    init(title: String, paper: PaperStyle, tint: PaperTint = .white) {
        self.title = title
        self.paper = paper
        self.tint = tint
    }

    enum CodingKeys: String, CodingKey { case id, title, paper, tint, drawing, images, created }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Hoja"
        paper = (try? c.decodeIfPresent(PaperStyle.self, forKey: .paper)) ?? .lined
        tint = (try? c.decodeIfPresent(PaperTint.self, forKey: .tint)) ?? .white
        drawing = try c.decodeIfPresent(Data.self, forKey: .drawing) ?? Data()
        images = (try? c.decodeIfPresent([NotebookImage].self, forKey: .images)) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

/// Figura recortada del PDF (va al Anexo C).
struct NotebookFigure: Codable, Identifiable, Hashable {
    var id = UUID()
    var file: String
    var sourcePage: Int
    var caption: String
    var created = Date()
}

/// Copia de una marca del libro guardada en el cuaderno. Así la guía de estudio y los anexos
/// se ven también sin abrir el PDF (en «Cuadernos» y en tus otros dispositivos).
struct StudyMark: Codable, Hashable, Identifiable {
    var id: String
    var pageIndex: Int
    var action: ReviewAction?
    var group: String
    var kind: String
    var text: String
    var hex: String
    var tags: [String]
    /// Tema del libro al que pertenece (capítulo o sección del índice).
    var topic: String

    var color: UIColor { UIColor(hex: hex) }
    var displayText: String { text.isEmpty ? "(\(kind.lowercased()))" : text }
}

/// Cuaderno de un libro.
struct Notebook: Codable {
    var bookTitle: String
    var pages: [NotebookPage]
    var figures: [NotebookFigure] = []
    var marks: [StudyMark] = []
    /// Marcas que ya repasaste (por id).
    var reviewed: Set<String> = []
    var coverHex: String = "#3B6FD9"
    var created = Date()
    var modified = Date()

    /// Tamaño lógico de cada hoja (proporción A4). Es igual en iPad mini y Pro,
    /// así los trazos se ven idénticos en todos los dispositivos.
    static let pageSize = CGSize(width: 820, height: 1160)

    static let coverColors = ["#3B6FD9", "#C2413A", "#2E8B57", "#7B4FC9", "#D98A1F", "#2F3B4C", "#C2477E", "#1F8A8A"]

    init(bookTitle: String, pages: [NotebookPage]) {
        self.bookTitle = bookTitle
        self.pages = pages
        let sum = bookTitle.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        coverHex = Self.coverColors[sum % Self.coverColors.count]
    }

    enum CodingKeys: String, CodingKey {
        case bookTitle, pages, figures, marks, reviewed, coverHex, created, modified
    }

    /// Tolerante: los cuadernos guardados con versiones anteriores siguen abriéndose.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookTitle = try c.decode(String.self, forKey: .bookTitle)
        pages = try c.decode([NotebookPage].self, forKey: .pages)
        figures = (try? c.decodeIfPresent([NotebookFigure].self, forKey: .figures)) ?? []
        marks = (try? c.decodeIfPresent([StudyMark].self, forKey: .marks)) ?? []
        reviewed = (try? c.decodeIfPresent(Set<String>.self, forKey: .reviewed)) ?? []
        coverHex = (try? c.decodeIfPresent(String.self, forKey: .coverHex)) ?? "#3B6FD9"
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
    }

    /// Marcas que van a la guía de estudio (sin sellos ni comentarios sueltos).
    var studyMarks: [StudyMark] {
        marks.filter { $0.action != nil && $0.action != ReviewAction.none && !$0.group.hasPrefix("Sello") }
    }
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
