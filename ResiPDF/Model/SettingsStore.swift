import SwiftUI

/// Acción asignable al doble toque / apretón del Apple Pencil.
enum PencilAction: String, Codable, CaseIterable, Identifiable {
    case quickPalette, previousTool, eraser, nextPreset, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quickPalette: return "Abrir colores junto al lápiz"
        case .previousTool: return "Volver a la herramienta anterior"
        case .eraser: return "Borrador ↔ herramienta actual"
        case .nextPreset: return "Siguiente color"
        case .none: return "Nada"
        }
    }
}

enum ButtonSize: String, Codable, CaseIterable, Identifiable {
    case compact, normal, large
    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .compact: return 36
        case .normal: return 44
        case .large: return 54
        }
    }
    var label: String {
        switch self {
        case .compact: return "Compacto"
        case .normal: return "Normal"
        case .large: return "Grande"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var profiles: [PresetProfile] = PresetProfile.builtIn
    var activeProfileID: UUID?
    var paletteOnLeft: Bool = true
    var paletteY: Double = 0.45
    var buttonSize: ButtonSize = .normal
    var highlightOpacity: Double = 0.45
    var penWidth: Double = 2.0
    var fingerDrawing: Bool = false
    var doubleTap: PencilAction = .previousTool
    var squeeze: PencilAction = .quickPalette
    var springLoaded: Bool = true
    var autoReturn: Bool = true
    var twoFingerUndo: Bool = true
    var stamps: [String] = ["Q", "❗", "⭐", "❓", "Dx", "Tx", "Cx", "Qx", "✔︎"]
    var currentStamp: String = "Q"

    init() {}

    // MARK: Perfil activo

    var activeIndex: Int {
        profiles.firstIndex { $0.id == activeProfileID } ?? 0
    }

    var activeProfile: PresetProfile {
        profiles.isEmpty ? PresetProfile(name: "Mi perfil", presets: []) : profiles[activeIndex]
    }

    /// Marcadores del perfil activo (lectura y escritura).
    var presets: [MarkPreset] {
        get { activeProfile.presets }
        set {
            if profiles.isEmpty {
                profiles = [PresetProfile(name: "Mi perfil", presets: newValue)]
            } else {
                profiles[activeIndex].presets = newValue
            }
        }
    }

    var activeProfileName: String {
        get { activeProfile.name }
        set { if !profiles.isEmpty { profiles[activeIndex].name = newValue } }
    }

    // MARK: Codable tolerante (si en el futuro se añaden opciones no se pierden las guardadas)

    enum CodingKeys: String, CodingKey {
        case profiles, activeProfileID, paletteOnLeft, paletteY, buttonSize, highlightOpacity, penWidth,
             fingerDrawing, doubleTap, squeeze, springLoaded, autoReturn, twoFingerUndo, stamps, currentStamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            let decoded: T? = (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
            return decoded ?? fallback
        }
        profiles = value(.profiles, d.profiles)
        activeProfileID = value(.activeProfileID, d.activeProfileID)
        paletteOnLeft = value(.paletteOnLeft, d.paletteOnLeft)
        paletteY = value(.paletteY, d.paletteY)
        buttonSize = value(.buttonSize, d.buttonSize)
        highlightOpacity = value(.highlightOpacity, d.highlightOpacity)
        penWidth = value(.penWidth, d.penWidth)
        fingerDrawing = value(.fingerDrawing, d.fingerDrawing)
        doubleTap = value(.doubleTap, d.doubleTap)
        squeeze = value(.squeeze, d.squeeze)
        springLoaded = value(.springLoaded, d.springLoaded)
        autoReturn = value(.autoReturn, d.autoReturn)
        twoFingerUndo = value(.twoFingerUndo, d.twoFingerUndo)
        stamps = value(.stamps, d.stamps)
        currentStamp = value(.currentStamp, d.currentStamp)
        if profiles.isEmpty { profiles = d.profiles }
    }
}

/// Preferencias globales (se guardan en el iPad, valen para todos los PDF).
final class SettingsStore: ObservableObject {
    private static let key = "ResiPDF.settings.v2"

    @Published var settings: AppSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = saved
        } else {
            settings = AppSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func preset(id: UUID) -> MarkPreset? {
        settings.presets.first { $0.id == id }
    }

    /// Marcador del perfil activo cuyo color es más parecido.
    func nearestPreset(to color: UIColor?) -> MarkPreset? {
        guard let color else { return nil }
        let best = settings.presets.min { $0.color.rgbDistance(to: color) < $1.color.rgbDistance(to: color) }
        guard let best, best.color.rgbDistance(to: color) < 0.25 else { return nil }
        return best
    }
}
