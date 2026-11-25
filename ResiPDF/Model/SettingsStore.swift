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
        case .compact: return 30
        case .normal: return 36
        case .large: return 44
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

/// Borde de la pantalla donde se pega el dock de colores.
enum DockEdge: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right, top
    var id: String { rawValue }
    var isVertical: Bool { self == .left || self == .right }
    var label: String {
        switch self {
        case .bottom: return "Abajo"
        case .left: return "Izquierda"
        case .right: return "Derecha"
        case .top: return "Arriba"
        }
    }
}

enum ReadingMode: String, Codable, CaseIterable, Identifiable {
    case continuous, paged
    var id: String { rawValue }
    var label: String {
        switch self {
        case .continuous: return "Continuo"
        case .paged: return "Página a página"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var profiles: [PresetProfile] = PresetProfile.builtIn
    var activeProfileID: UUID?
    var dockEdge: DockEdge = .bottom
    var dockOffset: Double = 0.5
    var buttonSize: ButtonSize = .normal
    var highlightOpacity: Double = 0.45
    var penWidth: Double = 2.0
    var fingerDrawing: Bool = false
    var doubleTap: PencilAction = .previousTool
    var squeeze: PencilAction = .quickPalette
    var pencilHover: Bool = true
    var springLoaded: Bool = true
    var autoReturn: Bool = true
    var twoFingerUndo: Bool = true
    var stamps: [String] = ["Q", "❗", "⭐", "❓", "✔︎"]
    var currentStamp: String = "Q"
    var tags: [String] = ["Dx", "Tx", "Cx", "Qx", "Anatomía", "Clasificación", "Fisiopato", "Epidemio"]
    var autoTagBar: Bool = true
    var readingMode: ReadingMode = .continuous

    init() {}

    // MARK: Patrón activo

    var activeIndex: Int {
        profiles.firstIndex { $0.id == activeProfileID } ?? 0
    }

    var activeProfile: PresetProfile {
        profiles.isEmpty ? PresetProfile(name: "Mi patrón", presets: []) : profiles[activeIndex]
    }

    /// Marcadores del patrón activo (lectura y escritura).
    var presets: [MarkPreset] {
        get { activeProfile.presets }
        set {
            if profiles.isEmpty {
                profiles = [PresetProfile(name: "Mi patrón", presets: newValue)]
            } else {
                profiles[activeIndex].presets = newValue
            }
        }
    }

    var activeProfileName: String {
        get { activeProfile.name }
        set { if !profiles.isEmpty { profiles[activeIndex].name = newValue } }
    }

    // MARK: Codable tolerante (las opciones nuevas no borran las guardadas)

    enum CodingKeys: String, CodingKey {
        case profiles, activeProfileID, dockEdge, dockOffset, buttonSize, highlightOpacity, penWidth,
             fingerDrawing, doubleTap, squeeze, pencilHover, springLoaded, autoReturn, twoFingerUndo,
             stamps, currentStamp, tags, autoTagBar, readingMode
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
        dockEdge = value(.dockEdge, d.dockEdge)
        dockOffset = value(.dockOffset, d.dockOffset)
        buttonSize = value(.buttonSize, d.buttonSize)
        highlightOpacity = value(.highlightOpacity, d.highlightOpacity)
        penWidth = value(.penWidth, d.penWidth)
        fingerDrawing = value(.fingerDrawing, d.fingerDrawing)
        doubleTap = value(.doubleTap, d.doubleTap)
        squeeze = value(.squeeze, d.squeeze)
        pencilHover = value(.pencilHover, d.pencilHover)
        springLoaded = value(.springLoaded, d.springLoaded)
        autoReturn = value(.autoReturn, d.autoReturn)
        twoFingerUndo = value(.twoFingerUndo, d.twoFingerUndo)
        stamps = value(.stamps, d.stamps)
        currentStamp = value(.currentStamp, d.currentStamp)
        tags = value(.tags, d.tags)
        autoTagBar = value(.autoTagBar, d.autoTagBar)
        readingMode = value(.readingMode, d.readingMode)
        if profiles.isEmpty { profiles = d.profiles }
    }
}

/// Preferencias globales (se guardan en el iPad, valen para todos los PDF).
final class SettingsStore: ObservableObject {
    private static let key = "ResiPDF.settings.v3"

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

    /// Marcador del patrón activo cuyo color es más parecido.
    func nearestPreset(to color: UIColor?) -> MarkPreset? {
        guard let color else { return nil }
        let best = settings.presets.min { $0.color.rgbDistance(to: color) < $1.color.rgbDistance(to: color) }
        guard let best, best.color.rgbDistance(to: color) < 0.25 else { return nil }
        return best
    }

    /// Limpia un texto para usarlo como etiqueta.
    static func sanitizeTag(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
