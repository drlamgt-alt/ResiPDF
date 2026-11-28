import UIKit

/// Estilo de marca que se ajusta al texto (snap) al arrastrar el Pencil.
enum MarkStyle: String, Codable, CaseIterable, Identifiable {
    case highlight, underline, strikeOut, box

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highlight: return "Resaltar"
        case .underline: return "Subrayar"
        case .strikeOut: return "Tachar"
        case .box: return "Recuadro"
        }
    }

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikeOut: return "strikethrough"
        case .box: return "rectangle"
        }
    }
}

/// Qué harás con lo marcado al repasar. Es el corazón del sistema:
/// el color indica una ACCIÓN de estudio, no solo un tema (ver GUIA_ESTUDIO.md).
enum ReviewAction: String, Codable, CaseIterable, Identifiable {
    case summary, question, memorize, connect, doubt, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: return "Idea principal"
        case .question: return "Pregunta de examen"
        case .memorize: return "Memorizar literal"
        case .connect: return "Conexión"
        case .doubt: return "No lo entendí"
        case .none: return "Sin acción"
        }
    }

    /// Qué hace la app con este color.
    var destination: String {
        switch self {
        case .summary: return "Va al resumen"
        case .question: return "Se vuelve pregunta"
        case .memorize: return "Se tapa en modo examen"
        case .connect: return "Únelo con una flecha"
        case .doubt: return "Va a la lista de dudas"
        case .none: return "Solo marca"
        }
    }

    var symbol: String {
        switch self {
        case .summary: return "text.alignleft"
        case .question: return "questionmark.bubble"
        case .memorize: return "brain.head.profile"
        case .connect: return "link"
        case .doubt: return "questionmark.circle"
        case .none: return "circle.dashed"
        }
    }

    /// Título de la sección al agrupar o exportar.
    var sectionTitle: String {
        switch self {
        case .summary: return "Ideas principales"
        case .question: return "Preguntas de examen"
        case .memorize: return "Para memorizar"
        case .connect: return "Conexiones"
        case .doubt: return "Dudas"
        case .none: return "Otras marcas"
        }
    }

    var order: Int { ReviewAction.allCases.firstIndex(of: self) ?? 99 }
}

/// Un marcador: color + estilo + significado + acción de repaso.
struct MarkPreset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var hex: String
    var style: MarkStyle
    var action: ReviewAction
    /// Qué va con este color, explicado en una frase (se muestra en la leyenda).
    var detail: String

    var color: UIColor { UIColor(hex: hex) }

    init(id: UUID = UUID(), name: String, hex: String, style: MarkStyle,
         action: ReviewAction = .none, detail: String = "") {
        self.id = id
        self.name = name
        self.hex = hex
        self.style = style
        self.action = action
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey { case id, name, hex, style, action, detail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Marcador"
        hex = (try? c.decode(String.self, forKey: .hex)) ?? "#FFC94D"
        style = (try? c.decode(MarkStyle.self, forKey: .style)) ?? .highlight
        action = (try? c.decode(ReviewAction.self, forKey: .action)) ?? .none
        detail = (try? c.decode(String.self, forKey: .detail)) ?? ""
    }
}

/// Conjunto de marcadores (un «patrón de colores») para un tipo de libro.
struct PresetProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var presets: [MarkPreset]
}

extension PresetProfile {
    /// Patrones predefinidos. El primero es el recomendado.
    static var builtIn: [PresetProfile] { [resident, activeStudy, surgery, anatomy, clinical] }

    static let residentName = "Residente de cirugía (7 colores)"

    /// Recomendado: 7 colores. Cada color es una ACCIÓN de repaso (qué harás con eso),
    /// no un tema: subrayar solo ayuda si después te obliga a recordar (Dunlosky 2013,
    /// efecto de evocación de Roediger y Karpicke 2006). Los temas (Dx, Tx, Cx…) van en etiquetas.
    /// Los 5 primeros son los de uso diario; los 2 últimos, de uso ocasional.
    static var resident: PresetProfile {
        PresetProfile(name: residentName, presets: [
            MarkPreset(name: "Idea principal", hex: "#FFC94D", style: .highlight, action: .summary,
                       detail: "Lo esencial del párrafo: lo que dirías si te preguntan «¿de qué trata?». Máximo una por párrafo."),
            MarkPreset(name: "Pregunta de examen", hex: "#B9A6FF", style: .highlight, action: .question,
                       detail: "Lo que te preguntarían en el examen o en el pase de visita. Va a la guía de estudio y a Anki."),
            MarkPreset(name: "Memorizar exacto", hex: "#FF5A5F", style: .underline, action: .memorize,
                       detail: "Cifras, dosis, criterios, escalas y clasificaciones: lo que hay que saber al pie de la letra."),
            MarkPreset(name: "Conducta y tratamiento", hex: "#5FCB8D", style: .highlight, action: .connect,
                       detail: "Qué haces con el paciente: indicación quirúrgica, técnica, manejo. Únelo con lo que ya sabes."),
            MarkPreset(name: "Definición", hex: "#6FB7FF", style: .underline, action: .summary,
                       detail: "Definiciones y conceptos base que sostienen el tema."),
            MarkPreset(name: "Alerta clínica", hex: "#FF9F43", style: .box, action: .memorize,
                       detail: "Complicaciones, contraindicaciones y errores graves: lo que no puedes olvidar en quirófano."),
            MarkPreset(name: "No lo entendí", hex: "#A1A1AA", style: .underline, action: .doubt,
                       detail: "Para preguntar al adjunto o revisar en otra fuente. Va a la lista de dudas."),
        ])
    }

    /// Recomendado: 5 colores, cada uno ligado a una acción de repaso.
    /// El tema clínico (Dx, Tx, Cx…) va en etiquetas, no en más colores.
    static var activeStudy: PresetProfile {
        PresetProfile(name: "Estudio activo (5 colores)", presets: [
            MarkPreset(name: "Idea principal", hex: "#FFC94D", style: .highlight, action: .summary),
            MarkPreset(name: "Pregunta de examen", hex: "#B9A6FF", style: .highlight, action: .question),
            MarkPreset(name: "Memorizar literal", hex: "#FF5A5F", style: .underline, action: .memorize),
            MarkPreset(name: "Conexión", hex: "#6FD49A", style: .highlight, action: .connect),
            MarkPreset(name: "No lo entendí", hex: "#A1A1AA", style: .underline, action: .doubt),
        ])
    }

    /// Libros de cirugía por tema (Schwartz, Sabiston, manuales).
    static var surgery: PresetProfile {
        PresetProfile(name: "Cirugía por tema (9 colores)", presets: [
            MarkPreset(name: "Concepto clave", hex: "#FFC94D", style: .highlight, action: .summary),
            MarkPreset(name: "Pregunta de examen", hex: "#B9A6FF", style: .highlight, action: .question),
            MarkPreset(name: "Indicación quirúrgica", hex: "#6FD49A", style: .highlight, action: .summary),
            MarkPreset(name: "Técnica y pasos", hex: "#7CC4FF", style: .highlight, action: .summary),
            MarkPreset(name: "Anatomía quirúrgica", hex: "#FFB067", style: .highlight, action: .summary),
            MarkPreset(name: "Clasificaciones y escalas", hex: "#FF9ECF", style: .highlight, action: .memorize),
            MarkPreset(name: "Complicaciones", hex: "#FF5A5F", style: .underline, action: .question),
            MarkPreset(name: "Cifras, dosis y tiempos", hex: "#2EC4B6", style: .underline, action: .memorize),
            MarkPreset(name: "No lo entendí", hex: "#A1A1AA", style: .underline, action: .doubt),
        ])
    }

    /// Atlas: código de color clásico de las láminas.
    static var anatomy: PresetProfile {
        PresetProfile(name: "Atlas de anatomía", presets: [
            MarkPreset(name: "Arteria", hex: "#FF5A5F", style: .highlight, action: .memorize),
            MarkPreset(name: "Vena", hex: "#7CC4FF", style: .highlight, action: .memorize),
            MarkPreset(name: "Nervio (no lesionar)", hex: "#FFC94D", style: .highlight, action: .memorize),
            MarkPreset(name: "Linfático", hex: "#6FD49A", style: .highlight, action: .memorize),
            MarkPreset(name: "Plano o reparo", hex: "#FFB067", style: .highlight, action: .summary),
            MarkPreset(name: "Pregunta de examen", hex: "#B9A6FF", style: .highlight, action: .question),
            MarkPreset(name: "No lo entendí", hex: "#A1A1AA", style: .underline, action: .doubt),
        ])
    }

    /// Materias clínicas.
    static var clinical: PresetProfile {
        PresetProfile(name: "Clínico (8 colores)", presets: [
            MarkPreset(name: "Concepto clave", hex: "#FFC94D", style: .highlight, action: .summary),
            MarkPreset(name: "Pregunta de examen", hex: "#B9A6FF", style: .highlight, action: .question),
            MarkPreset(name: "Diagnóstico", hex: "#6FD49A", style: .highlight, action: .summary),
            MarkPreset(name: "Tratamiento", hex: "#7CC4FF", style: .highlight, action: .summary),
            MarkPreset(name: "Cuadro clínico", hex: "#FF9ECF", style: .highlight, action: .summary),
            MarkPreset(name: "Epidemiología", hex: "#FFB067", style: .underline, action: .summary),
            MarkPreset(name: "Cifras y dosis", hex: "#FF5A5F", style: .underline, action: .memorize),
            MarkPreset(name: "No lo entendí", hex: "#A1A1AA", style: .underline, action: .doubt),
        ])
    }
}

extension MarkPreset {
    /// Colores sugeridos: tonos que funcionan como resaltador sin tapar el texto.
    static let swatches: [String] = [
        "#FFC94D", "#B9A6FF", "#FF5A5F", "#6FD49A", "#A1A1AA", "#7CC4FF",
        "#FFB067", "#FF9ECF", "#2EC4B6", "#9AD34B", "#5B8DEF", "#C9A27A",
    ]
}
