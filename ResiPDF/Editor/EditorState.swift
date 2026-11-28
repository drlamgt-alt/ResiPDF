import SwiftUI
import PDFKit

enum Tool: Hashable {
    case navigate
    case preset(UUID)
    case pen, arrow, circle, note, stamp, mask, eraser, crop
}

struct NoteRequest: Identifiable {
    let id = UUID()
    var initialText: String
    var isEditing: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void
}

/// Petición para etiquetar (Dx, Tx, Cx…) la marca recién hecha.
struct TagRequest: Identifiable {
    let id = UUID()
    let groupID: String
    /// Punto en coordenadas de la vista PDF donde mostrar la barra.
    let point: CGPoint
    var tags: [String]
    let apply: ([String]) -> Void
    /// Marcador con el que se hizo (para resaltarlo en la barra).
    var presetID: UUID? = nil
    /// Cambia el color/estilo de la marca recién hecha con un toque.
    var recolor: ((MarkPreset) -> Void)? = nil
    /// Borra la marca recién hecha.
    var delete: (() -> Void)? = nil
}

/// Estado del editor de un documento (herramienta activa, color, avisos, página).
final class EditorState: ObservableObject {
    @Published var tool: Tool = .navigate
    @Published var currentHex: String = "#FFC94D"
    @Published var toast: String?
    @Published var noteRequest: NoteRequest?
    /// Punto (coordenadas de la vista PDF) donde mostrar la rueda de colores junto al lápiz.
    @Published var quickPalettePoint: CGPoint?
    /// Dónde está el dedo mientras se desliza sobre la rueda (mantener pulsado con el dedo).
    @Published var ringPointer: CGPoint?
    @Published var tagRequest: TagRequest?
    @Published var dockCollapsed = false
    /// Doble toque del Pencil: el mismo color pasa de resaltar a subrayar (y al revés).
    @Published var styleSwap = false
    @Published var currentPageIndex = 0
    @Published var currentPageIsFavorite = false
    /// Aumenta cada vez que cambian las anotaciones (para refrescar listas).
    @Published var annotationsVersion = 0

    /// Última marca hecha: el botón de etiquetas del dock la etiqueta.
    var lastTagTarget: TagRequest?
    private(set) var previousTool: Tool = .navigate
    /// Última posición del Pencil, para abrir la rueda de colores ahí.
    var lastPencilPoint: CGPoint?
    weak var pdfView: PDFView?
    /// Lo asigna el motor de anotación.
    var toggleFavorite: (() -> Void)?
    /// Recibe cada figura recortada del PDF (imagen e índice de página) para el cuaderno.
    var onFigure: ((UIImage, Int) -> Void)?
    private var toastWork: DispatchWorkItem?

    func select(_ newTool: Tool, store: SettingsStore, announce: Bool = true) {
        if newTool != tool { previousTool = tool }
        tool = newTool
        let message: String
        switch newTool {
        case .preset(let id):
            guard let p = store.preset(id: id) else { return }
            currentHex = p.hex
            message = "\(p.name) · \(p.action.destination)"
        case .navigate: message = "Navegar (el Pencil no anota)"
        case .pen: message = "Lápiz libre"
        case .arrow: message = "Flecha"
        case .circle: message = "Círculo"
        case .note: message = "Comentario: toca donde quieras"
        case .stamp: message = "Sello «\(store.settings.currentStamp)»: toca para colocar"
        case .mask: message = "Tapa: arrastra sobre lo que quieras ocultar"
        case .eraser: message = "Borrador"
        case .crop: message = "Recortar: enmarca la figura con el Pencil"
        }
        if announce { showToast(message) }
    }

    func perform(_ action: PencilAction, store: SettingsStore) {
        switch action {
        case .none:
            break
        case .toggleStyle:
            toggleStyle(store: store)
        case .quickPalette:
            if quickPalettePoint != nil {
                quickPalettePoint = nil
            } else {
                let fallback = pdfView.map { CGPoint(x: $0.bounds.midX, y: $0.bounds.midY) } ?? CGPoint(x: 300, y: 300)
                quickPalettePoint = lastPencilPoint ?? fallback
            }
        case .previousTool:
            select(previousTool, store: store)
        case .eraser:
            select(tool == .eraser ? previousTool : .eraser, store: store)
        case .nextPreset:
            let presets = store.settings.presets
            guard !presets.isEmpty else { return }
            var idx = 0
            if case .preset(let id) = tool, let i = presets.firstIndex(where: { $0.id == id }) {
                idx = (i + 1) % presets.count
            }
            select(.preset(presets[idx].id), store: store)
        }
    }

    /// Estilo con el que se marca de verdad (teniendo en cuenta el doble toque).
    func effectiveStyle(of preset: MarkPreset) -> MarkStyle {
        guard styleSwap else { return preset.style }
        switch preset.style {
        case .highlight: return .underline
        case .underline: return .highlight
        default: return preset.style
        }
    }

    func toggleStyle(store: SettingsStore) {
        if case .preset = tool {} else { selectFirstPreset(store: store) }
        styleSwap.toggle()
        if case .preset(let id) = tool, let p = store.preset(id: id) {
            showToast("\(effectiveStyle(of: p).label) · \(p.name)")
        } else {
            showToast(styleSwap ? "Subrayar con el mismo color" : "Resaltar con el mismo color")
        }
    }

    /// Tras una flecha, círculo, sello o comentario, vuelve al marcador que se estaba usando.
    func finishOneShot(store: SettingsStore) {
        guard store.settings.autoReturn, case .preset = previousTool else { return }
        select(previousTool, store: store, announce: false)
    }

    func selectFirstPreset(store: SettingsStore) {
        if let first = store.settings.presets.first {
            select(.preset(first.id), store: store)
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func go(to page: PDFPage) {
        pdfView?.go(to: page)
    }

    func go(to selection: PDFSelection) {
        guard let view = pdfView else { return }
        view.go(to: selection)
        view.highlightedSelections = [selection]
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak view] in
            view?.highlightedSelections = nil
        }
    }

    func setAllMasks(revealed: Bool) {
        guard let pdf = pdfView?.document else { return }
        MaskStyle.setAll(in: pdf, revealed: revealed)
        showToast(revealed ? "Tapas destapadas" : "Tapas cubiertas: a evaluarte")
    }
}
