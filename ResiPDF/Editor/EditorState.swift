import SwiftUI
import PDFKit

enum Tool: Hashable {
    case navigate
    case preset(UUID)
    case pen, arrow, circle, note, stamp, mask, eraser
}

struct NoteRequest: Identifiable {
    let id = UUID()
    var initialText: String
    var isEditing: Bool
    let onSave: (String) -> Void
    let onDelete: () -> Void
}

/// Estado del editor de un documento (herramienta activa, color, avisos).
final class EditorState: ObservableObject {
    @Published var tool: Tool = .navigate
    @Published var currentHex: String = "#FFD400"
    @Published var toast: String?
    @Published var noteRequest: NoteRequest?
    /// Punto (coordenadas de la vista PDF) donde mostrar la rueda de colores junto al lápiz.
    @Published var quickPalettePoint: CGPoint?
    /// Paleta plegada (ocupa menos espacio a un lado del PDF).
    @Published var paletteCollapsed = false

    private(set) var previousTool: Tool = .navigate
    /// Última posición del Pencil, para abrir la rueda de colores ahí.
    var lastPencilPoint: CGPoint?
    weak var pdfView: PDFView?
    private var toastWork: DispatchWorkItem?

    func select(_ newTool: Tool, store: SettingsStore, announce: Bool = true) {
        if newTool != tool { previousTool = tool }
        tool = newTool
        var message: String
        switch newTool {
        case .preset(let id):
            guard let p = store.preset(id: id) else { return }
            currentHex = p.hex
            message = "\(p.style.label) · \(p.name)"
        case .navigate: message = "Navegar (el Pencil no anota)"
        case .pen: message = "Lápiz libre"
        case .arrow: message = "Flecha"
        case .circle: message = "Círculo / óvalo"
        case .note: message = "Comentario: toca donde quieras"
        case .stamp: message = "Sello «\(store.settings.currentStamp)»: toca para colocar"
        case .mask: message = "Tapa: arrastra sobre lo que quieras ocultar"
        case .eraser: message = "Borrador"
        }
        if announce { showToast(message) }
    }

    func perform(_ action: PencilAction, store: SettingsStore) {
        switch action {
        case .none:
            break
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
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
        showToast(revealed ? "Tapas destapadas" : "Tapas cubiertas: ¡a evaluarte!")
    }
}
