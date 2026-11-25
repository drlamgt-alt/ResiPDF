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

/// Un "marcador rápido": color + estilo + significado (ej. Morado = Pregunta de examen).
struct MarkPreset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var hex: String
    var style: MarkStyle

    var color: UIColor { UIColor(hex: hex) }
}

/// Conjunto de marcadores para un tipo de libro (Cirugía, Atlas de anatomía…).
struct PresetProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var presets: [MarkPreset]
}

extension PresetProfile {
    /// Perfiles predefinidos (ver GUIA_ESTUDIO.md).
    static var builtIn: [PresetProfile] { [surgery, anatomy, clinical, minimal] }

    /// Libros de cirugía (Schwartz, Sabiston, manuales, guías).
    static var surgery: PresetProfile {
        PresetProfile(name: "Cirugía", presets: [
            MarkPreset(name: "Concepto clave (high-yield)", hex: "#FFD400", style: .highlight),
            MarkPreset(name: "Pregunta de examen", hex: "#B57BFF", style: .highlight),
            MarkPreset(name: "Indicación quirúrgica / cuándo operar", hex: "#5EDC6E", style: .highlight),
            MarkPreset(name: "Técnica y pasos quirúrgicos", hex: "#5AC8FA", style: .highlight),
            MarkPreset(name: "Anatomía quirúrgica", hex: "#FF9F43", style: .highlight),
            MarkPreset(name: "Clasificaciones y escalas", hex: "#FF8AC8", style: .highlight),
            MarkPreset(name: "Complicaciones / red flags", hex: "#FF3B30", style: .underline),
            MarkPreset(name: "Cifras, dosis y tiempos", hex: "#00B8A9", style: .underline),
            MarkPreset(name: "No entiendo / repasar", hex: "#8E8E93", style: .underline),
        ])
    }

    /// Atlas y anatomía quirúrgica: código de color clásico de las láminas.
    static var anatomy: PresetProfile {
        PresetProfile(name: "Anatomía quirúrgica", presets: [
            MarkPreset(name: "Arteria", hex: "#FF3B30", style: .highlight),
            MarkPreset(name: "Vena", hex: "#5AC8FA", style: .highlight),
            MarkPreset(name: "Nervio (¡no lesionar!)", hex: "#FFD400", style: .highlight),
            MarkPreset(name: "Linfático / ganglios", hex: "#5EDC6E", style: .highlight),
            MarkPreset(name: "Plano / reparo quirúrgico", hex: "#FF9F43", style: .highlight),
            MarkPreset(name: "Pregunta de examen", hex: "#B57BFF", style: .highlight),
            MarkPreset(name: "Variante anatómica", hex: "#FF8AC8", style: .underline),
            MarkPreset(name: "No entiendo / repasar", hex: "#8E8E93", style: .underline),
        ])
    }

    /// Materias clínicas (medicina interna, pediatría, GyO…).
    static var clinical: PresetProfile {
        PresetProfile(name: "Clínico (ENARM)", presets: [
            MarkPreset(name: "Concepto clave (high-yield)", hex: "#FFD400", style: .highlight),
            MarkPreset(name: "Pregunta de examen", hex: "#B57BFF", style: .highlight),
            MarkPreset(name: "Diagnóstico", hex: "#5EDC6E", style: .highlight),
            MarkPreset(name: "Tratamiento", hex: "#5AC8FA", style: .highlight),
            MarkPreset(name: "Clínica / cuadro típico", hex: "#FF8AC8", style: .highlight),
            MarkPreset(name: "Epidemiología / factores de riesgo", hex: "#FF9F43", style: .underline),
            MarkPreset(name: "Cifras, dosis, alertas", hex: "#FF3B30", style: .underline),
            MarkPreset(name: "No entiendo / repasar", hex: "#8E8E93", style: .underline),
        ])
    }

    /// Para empezar o para lectura rápida.
    static var minimal: PresetProfile {
        PresetProfile(name: "Mínimo (4 colores)", presets: [
            MarkPreset(name: "Concepto clave", hex: "#FFD400", style: .highlight),
            MarkPreset(name: "Pregunta de examen", hex: "#B57BFF", style: .highlight),
            MarkPreset(name: "Cifras / alertas", hex: "#FF3B30", style: .underline),
            MarkPreset(name: "Repasar", hex: "#8E8E93", style: .underline),
        ])
    }
}

extension MarkPreset {
    /// Colores sugeridos para el editor de marcadores.
    static let swatches: [String] = [
        "#FFD400", "#B57BFF", "#5EDC6E", "#5AC8FA", "#FF8AC8", "#FF9F43",
        "#FF3B30", "#00B8A9", "#8E8E93", "#007AFF", "#AF52DE", "#A2845E",
    ]
}
