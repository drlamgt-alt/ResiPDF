import SwiftUI
import PencilKit

/// Vista transparente: deja pasar los toques que no caen sobre una imagen.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Hoja del cuaderno: papel + imágenes debajo y trazos de PencilKit encima.
/// La hoja tiene un tamaño fijo (`Notebook.pageSize`) y se escala al ancho disponible.
final class NotebookCanvasView: PKCanvasView {
    /// Deshacer propio: así los trazos del cuaderno no tocan el PDF.
    private let localUndo = UndoManager()
    override var undoManager: UndoManager? { localUndo }

    let paperHost = UIView()
    let paperView = PaperView()
    let imageHost = PassthroughView()
    private var imageViews: [UUID: UIImageView] = [:]
    private(set) var images: [NotebookImage] = []
    private var lastWidth: CGFloat = 0

    var onImageChanged: ((NotebookImage) -> Void)?
    var onImageDelete: ((UUID) -> Void)?
    var onGoToSource: ((Int) -> Void)?

    /// Modo «mover imágenes»: las imágenes quedan encima y se arrastran con el dedo.
    var moveMode = false {
        didSet {
            guard moveMode != oldValue else { return }
            drawingGestureRecognizer.isEnabled = !moveMode
            imageHost.isUserInteractionEnabled = moveMode
            for v in imageViews.values {
                v.layer.borderWidth = moveMode ? 2 : 0
            }
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        overrideUserInterfaceStyle = .light   // la tinta negra no se invierte en modo oscuro
        drawingPolicy = .pencilOnly
        contentInsetAdjustmentBehavior = .never
        alwaysBounceVertical = true
        showsHorizontalScrollIndicator = false

        let bounds = CGRect(origin: .zero, size: Notebook.pageSize)
        paperHost.bounds = bounds
        paperView.frame = bounds
        paperHost.addSubview(paperView)
        paperHost.isUserInteractionEnabled = false
        imageHost.bounds = bounds
        imageHost.isUserInteractionEnabled = false
        insertSubview(imageHost, at: 0)
        insertSubview(paperHost, at: 0)
        NotificationCenter.default.addObserver(self, selector: #selector(hideTools),
                                               name: Self.hideToolsNotification, object: nil)
    }

    /// La envía el PDF al empezar a marcar: la paleta del cuaderno se oculta para no tapar el dock.
    static let hideToolsNotification = Notification.Name("ResiPDF.ocultarPaletaCuaderno")

    @objc private func hideTools() {
        if isFirstResponder { resignFirstResponder() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            fitToWidth()
        }
        // Orden: papel al fondo; imágenes debajo de la tinta (o encima al moverlas).
        if moveMode {
            bringSubviewToFront(imageHost)
        } else {
            sendSubviewToBack(imageHost)
        }
        sendSubviewToBack(paperHost)
    }

    private func fitToWidth() {
        let size = Notebook.pageSize
        let scale = bounds.width / size.width
        minimumZoomScale = scale
        maximumZoomScale = scale
        zoomScale = scale
        contentSize = CGSize(width: size.width * scale, height: size.height * scale)
        let center = CGPoint(x: contentSize.width / 2, y: contentSize.height / 2)
        for host in [paperHost, imageHost] {
            host.transform = CGAffineTransform(scaleX: scale, y: scale)
            host.center = center
        }
        paperView.layer.contentsScale = (window?.screen.scale ?? 2) * scale
        paperView.setNeedsDisplay()
    }

    // MARK: - Imágenes

    func setImages(_ list: [NotebookImage], loader: (String) -> UIImage?) {
        let ids = Set(list.map(\.id))
        for (id, v) in imageViews where !ids.contains(id) {
            v.removeFromSuperview()
            imageViews[id] = nil
        }
        for item in list {
            let v = imageViews[item.id] ?? makeImageView(item, loader: loader)
            // La figura puede llegar más tarde desde iCloud.
            if v.image == nil { v.image = loader(item.file) }
            v.transform = .identity
            v.frame = item.frame
        }
        images = list
    }

    private func makeImageView(_ item: NotebookImage, loader: (String) -> UIImage?) -> UIImageView {
        let v = UIImageView(image: loader(item.file))
        v.contentMode = .scaleAspectFit
        v.isUserInteractionEnabled = true
        v.accessibilityIdentifier = item.id.uuidString
        v.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor
        v.layer.borderWidth = moveMode ? 2 : 0
        v.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
        v.addInteraction(UIContextMenuInteraction(delegate: self))
        imageHost.addSubview(v)
        imageViews[item.id] = v
        return v
    }

    private func item(for view: UIView?) -> NotebookImage? {
        guard let s = view?.accessibilityIdentifier, let id = UUID(uuidString: s) else { return nil }
        return images.first { $0.id == id }
    }

    private func commit(_ view: UIView) {
        guard var item = item(for: view) else { return }
        item.frame = view.frame
        if let i = images.firstIndex(where: { $0.id == item.id }) { images[i] = item }
        onImageChanged?(item)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let v = g.view else { return }
        let t = g.translation(in: imageHost)
        v.center = CGPoint(x: v.center.x + t.x, y: v.center.y + t.y)
        g.setTranslation(.zero, in: imageHost)
        if g.state == .ended { commit(v) }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let v = g.view else { return }
        let center = v.center
        let w = max(60, min(Notebook.pageSize.width, v.bounds.width * g.scale))
        let h = w * (v.bounds.height / max(v.bounds.width, 1))
        v.bounds.size = CGSize(width: w, height: h)
        v.center = center
        g.scale = 1
        if g.state == .ended { commit(v) }
    }
}

extension NotebookCanvasView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = item(for: interaction.view) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIMenuElement] = []
            if let page = item.sourcePage {
                actions.append(UIAction(title: "Ir a la p. \(page + 1) del libro",
                                        image: UIImage(systemName: "book")) { _ in self?.onGoToSource?(page) })
            }
            actions.append(UIAction(title: "Quitar de la hoja", image: UIImage(systemName: "trash"),
                                    attributes: .destructive) { _ in self?.onImageDelete?(item.id) })
            return UIMenu(children: actions)
        }
    }
}

/// Permite deshacer y rehacer desde la barra del cuaderno.
final class CanvasController: ObservableObject {
    weak var canvas: NotebookCanvasView?
    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
    /// Muestra u oculta la paleta de PencilKit (bolígrafos, colores, regla…).
    func toggleTools() {
        guard let canvas else { return }
        if canvas.isFirstResponder { canvas.resignFirstResponder() } else { canvas.becomeFirstResponder() }
    }
}

/// Puente SwiftUI ↔ hoja de PencilKit.
struct PageCanvas: UIViewRepresentable {
    let pageID: UUID
    @ObservedObject var store: NotebookStore
    let controller: CanvasController
    var moveMode: Bool
    var onGoToSource: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NotebookCanvasView {
        let canvas = NotebookCanvasView(frame: .zero)
        canvas.delegate = context.coordinator
        controller.canvas = canvas
        context.coordinator.store = store

        let picker = context.coordinator.picker
        picker.colorUserInterfaceStyle = .light
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: NotebookCanvasView, context: Context) {
        let c = context.coordinator
        c.store = store
        canvas.onImageChanged = { [weak store] image in store?.updateImage(image, on: pageID) }
        canvas.onImageDelete = { [weak store] id in store?.removeImage(id, from: pageID) }
        canvas.onGoToSource = onGoToSource
        canvas.moveMode = moveMode
        c.picker.setVisible(!moveMode, forFirstResponder: canvas)

        guard let page = store.page(pageID) else { return }
        // Recarga los trazos al cambiar de hoja o si llegó una versión nueva de otro iPad.
        if c.pageID != pageID || c.loadCount != store.loadCount {
            let newPage = c.pageID != pageID
            c.pageID = pageID
            c.loadCount = store.loadCount
            c.loading = true
            canvas.drawing = (try? PKDrawing(data: page.drawing)) ?? PKDrawing()
            c.loading = false
            canvas.undoManager?.removeAllActions()
            if newPage { canvas.setContentOffset(.zero, animated: false) }
        }
        canvas.paperView.paper = page.paper
        canvas.paperView.title = page.title
        canvas.paperView.tint = page.tint
        // Papel de noche: la tinta negra se ve blanca (y se guarda igual; al exportar vuelve a negro).
        let style: UIUserInterfaceStyle = page.tint.isDark ? .dark : .light
        if canvas.overrideUserInterfaceStyle != style { canvas.overrideUserInterfaceStyle = style }
        canvas.setImages(page.images) { store.image(named: $0) }
    }

    static func dismantleUIView(_ canvas: NotebookCanvasView, coordinator: Coordinator) {
        if let id = coordinator.pageID {
            coordinator.store?.updateDrawing(id, canvas.drawing.dataRepresentation())
            coordinator.store?.saveNow()
        }
        coordinator.picker.setVisible(false, forFirstResponder: canvas)
        coordinator.picker.removeObserver(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let picker = PKToolPicker()
        var pageID: UUID?
        var loadCount = -1
        var loading = false
        weak var store: NotebookStore?

        /// Al escribir en el cuaderno vuelve la paleta de PencilKit.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            if !canvasView.isFirstResponder { canvasView.becomeFirstResponder() }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !loading, let id = pageID else { return }
            store?.updateDrawing(id, canvasView.drawing.dataRepresentation())
        }
    }
}
