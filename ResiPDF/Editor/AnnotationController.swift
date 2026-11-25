import UIKit
import PDFKit

/// Una anotación junto con la página donde vive (para deshacer/rehacer).
struct PlacedAnnotation {
    let page: PDFPage
    let annotation: PDFAnnotation
}

/// Motor de anotación:
/// - Apple Pencil anota; el dedo desplaza y hace zoom (rechazo de palma).
/// - Resaltar/Subrayar/Tachar/Recuadro se AJUSTAN AL TEXTO.
/// - Si la página es escaneada (sin texto), se dibuja un trazo recto equivalente.
/// - Lápiz, flecha, círculo, sello, comentario, tapa de autoevaluación y borrador.
/// - Toque con 2 dedos = deshacer, 3 dedos = rehacer.
/// - Todo se registra en el UndoManager => deshacer/rehacer + autoguardado.
final class AnnotationController: NSObject, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    var editor: EditorState!
    var store: SettingsStore!
    weak var undoManager: UndoManager?

    private weak var pdfView: PDFView?
    private let stroke = StrokeGestureRecognizer()
    private let maskTap = UITapGestureRecognizer()
    private let undoTap = UITapGestureRecognizer()
    private let redoTap = UITapGestureRecognizer()
    private let hover = UIHoverGestureRecognizer()
    private let preview = CAShapeLayer()
    /// Punto del color activo bajo la punta del Pencil (iPad con hover).
    private let hoverDot = CAShapeLayer()

    private enum Mode {
        case none
        case mark(MarkPreset)
        case pen(UIColor)
        case arrow(UIColor)
        case circle(UIColor)
        case note(UIColor)
        case stamp(UIColor, String)
        case mask
        case eraser
        case crop
    }

    // Estado del trazo en curso
    private var mode: Mode = .none
    private var startPoint: CGPoint = .zero
    private var startPage: PDFPage?
    private var points: [CGPoint] = []
    private var tempMarks: [PDFAnnotation] = []
    private var tempText = ""

    /// Grosor (en puntos PDF) del resaltado "a mano" para páginas escaneadas.
    private static let fallbackHighlightHeight: CGFloat = 12
    private static let noteFont = UIFont.systemFont(ofSize: 11)
    private static let stampFont = UIFont.boldSystemFont(ofSize: 13)
    static let groupPrefix = "resi:"
    static let stampPrefix = "resistamp:"

    private var ownRecognizers: [UIGestureRecognizer] { [stroke, maskTap, undoTap, redoTap, hover] }
    static let favoriteSymbol = "⭐"

    // MARK: - Configuración

    func attach(to view: PDFView) {
        pdfView = view

        stroke.addTarget(self, action: #selector(handleStroke(_:)))
        stroke.delegate = self
        stroke.cancelsTouchesInView = true
        view.addGestureRecognizer(stroke)

        // Toque (dedo o Pencil) sobre una tapa => destapar / tapar
        maskTap.addTarget(self, action: #selector(handleMaskTap(_:)))
        maskTap.delegate = self
        maskTap.cancelsTouchesInView = false
        maskTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                                     NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        view.addGestureRecognizer(maskTap)

        // Toque con 2 dedos = deshacer, 3 dedos = rehacer
        undoTap.numberOfTouchesRequired = 2
        undoTap.addTarget(self, action: #selector(handleUndoTap))
        undoTap.delegate = self
        undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(undoTap)

        redoTap.numberOfTouchesRequired = 3
        redoTap.addTarget(self, action: #selector(handleRedoTap))
        redoTap.delegate = self
        redoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(redoTap)
        undoTap.require(toFail: redoTap)

        preview.fillColor = nil
        preview.lineCap = .round
        preview.lineJoin = .round
        preview.zPosition = 1_000
        view.layer.addSublayer(preview)

        hoverDot.zPosition = 1_001
        hoverDot.isHidden = true
        hoverDot.lineWidth = 1.5
        hoverDot.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        view.layer.addSublayer(hoverDot)
        hover.addTarget(self, action: #selector(handleHover(_:)))
        view.addGestureRecognizer(hover)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)

        editor.toggleFavorite = { [weak self] in self?.toggleFavoriteOnCurrentPage() }

        let nc = NotificationCenter.default
        for name in [Notification.Name.PDFViewPageChanged,
                     .PDFViewDocumentChanged,
                     .PDFViewScaleChanged,
                     .PDFViewVisiblePagesChanged] {
            nc.addObserver(self, selector: #selector(viewDidChange), name: name, object: view)
        }
        applyInputMode()
        DispatchQueue.main.async { [weak self] in self?.updatePageState() }
    }

    @objc private func viewDidChange() {
        applyInputMode()
        DispatchQueue.main.async { [weak self] in self?.updatePageState() }
    }

    /// Página actual y si es favorita (para el indicador y la estrella).
    private func updatePageState() {
        guard let view = pdfView, let doc = view.document, let page = view.currentPage else { return }
        let index = doc.index(for: page)
        if editor.currentPageIndex != index { editor.currentPageIndex = index }
        let favorite = favoriteStamp(on: page) != nil
        if editor.currentPageIsFavorite != favorite { editor.currentPageIsFavorite = favorite }
    }

    // MARK: - Hover del Pencil (iPad Pro M2+ / Pencil Pro)

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        guard let view = pdfView, store.settings.pencilHover, editor.tool != .navigate else {
            hoverDot.isHidden = true
            return
        }
        switch g.state {
        case .began, .changed:
            // zOffset > 0 solo con el Pencil sobre la pantalla (no con ratón o trackpad).
            guard g.zOffset > 0 else { hoverDot.isHidden = true; return }
            let p = g.location(in: view)
            let color: UIColor
            switch currentMode() {
            case .mark(let preset): color = preset.color
            case .eraser: color = .systemGray
            case .mask: color = MaskStyle.border
            default: color = UIColor(hex: editor.currentHex)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hoverDot.frame = view.bounds
            hoverDot.path = UIBezierPath(ovalIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)).cgPath
            hoverDot.fillColor = color.cgColor
            hoverDot.isHidden = false
            CATransaction.commit()
        default:
            hoverDot.isHidden = true
        }
    }

    /// Con una herramienta activa: el Pencil anota y los gestos internos de
    /// PDFView (selección de texto, scroll) solo responden al dedo.
    func applyInputMode() {
        guard let view = pdfView, let editor = editor, let store = store else { return }
        let annotating = editor.tool != .navigate
        let finger = store.settings.fingerDrawing

        var types = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        if finger { types.append(NSNumber(value: UITouch.TouchType.direct.rawValue)) }
        stroke.allowedTouchTypes = types
        stroke.isEnabled = annotating
        undoTap.isEnabled = store.settings.twoFingerUndo
        redoTap.isEnabled = store.settings.twoFingerUndo

        configureBuiltInGestures(in: view, annotating: annotating, fingerDrawing: finger)
    }

    private func configureBuiltInGestures(in v: UIView, annotating: Bool, fingerDrawing: Bool) {
        let all: [NSNumber] = [UITouch.TouchType.direct, .indirect, .pencil, .indirectPointer]
            .map { NSNumber(value: $0.rawValue) }
        let noPencil: [NSNumber] = [UITouch.TouchType.direct, .indirect, .indirectPointer]
            .map { NSNumber(value: $0.rawValue) }
        let own = ownRecognizers

        for g in v.gestureRecognizers ?? [] where !own.contains(where: { $0 === g }) {
            g.allowedTouchTypes = annotating ? noPencil : all
        }
        if let scroll = v as? UIScrollView {
            // Si se anota con el dedo, el desplazamiento pasa a ser con dos dedos.
            scroll.panGestureRecognizer.minimumNumberOfTouches = (annotating && fingerDrawing) ? 2 : 1
        }
        for sub in v.subviews {
            configureBuiltInGestures(in: sub, annotating: annotating, fingerDrawing: fingerDrawing)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === stroke { return other.view is UIScrollView }
        return gestureRecognizer === maskTap || gestureRecognizer === undoTap || gestureRecognizer === redoTap
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // La tapa con Pencil mientras se anota la gestiona el trazo.
        if gestureRecognizer === maskTap, touch.type == .pencil, stroke.isEnabled { return false }
        return true
    }

    // MARK: - Gestos rápidos

    @objc private func handleMaskTap(_ g: UITapGestureRecognizer) {
        guard let view = pdfView else { return }
        _ = toggleMask(at: g.location(in: view), in: view)
    }

    @objc private func handleUndoTap() {
        guard let um = undoManager, um.canUndo else { return }
        let name = um.undoActionName
        um.undo()
        editor.showToast(name.isEmpty ? "Deshacer" : "Deshacer: \(name)")
    }

    @objc private func handleRedoTap() {
        guard let um = undoManager, um.canRedo else { return }
        let name = um.redoActionName
        um.redo()
        editor.showToast(name.isEmpty ? "Rehacer" : "Rehacer: \(name)")
    }

    // MARK: - Apple Pencil: doble toque y apretón (Pencil Pro)

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        editor.perform(store.settings.doubleTap, store: store)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction,
                           didReceiveTap tap: UIPencilInteraction.Tap) {
        if let location = tap.hoverPose?.location { editor.lastPencilPoint = location }
        editor.perform(store.settings.doubleTap, store: store)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction,
                           didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        if let location = squeeze.hoverPose?.location { editor.lastPencilPoint = location }
        editor.perform(store.settings.squeeze, store: store)
    }

    // MARK: - Trazo

    @objc private func handleStroke(_ g: StrokeGestureRecognizer) {
        guard let view = pdfView else { return }
        switch g.state {
        case .began:
            begin(at: g.location(in: view), in: view)
        case .changed:
            move(to: g.takeSamples(), in: view)
        case .ended:
            move(to: g.takeSamples(), in: view)
            finish(in: view)
        case .cancelled, .failed:
            cancel()
        default:
            break
        }
    }

    private func currentMode() -> Mode {
        let color = UIColor(hex: editor.currentHex)
        switch editor.tool {
        case .navigate: return .none
        case .preset(let id):
            if let p = store.preset(id: id) { return .mark(p) }
            return .none
        case .pen: return .pen(color)
        case .arrow: return .arrow(color)
        case .circle: return .circle(color)
        case .note: return .note(color)
        case .stamp: return .stamp(color, store.settings.currentStamp)
        case .mask: return .mask
        case .eraser: return .eraser
        case .crop: return .crop
        }
    }

    private func begin(at p: CGPoint, in view: PDFView) {
        if editor.quickPalettePoint != nil { editor.quickPalettePoint = nil }
        if editor.tagRequest != nil { editor.tagRequest = nil }
        hoverDot.isHidden = true
        mode = currentMode()
        startPoint = p
        points = [p]
        editor.lastPencilPoint = p
        startPage = view.page(for: p, nearest: true)
        tempMarks = []
        tempText = ""
        preview.frame = view.bounds
        preview.fillColor = nil
        preview.lineDashPattern = nil
        setPreview(nil)

        let scale = view.scaleFactor
        switch mode {
        case .pen(let c), .arrow(let c), .circle(let c):
            preview.strokeColor = c.cgColor
            preview.lineWidth = CGFloat(store.settings.penWidth) * scale
        case .mark(let preset):
            let isHighlight = preset.style == .highlight
            let alpha = isHighlight ? CGFloat(store.settings.highlightOpacity) : 1
            preview.strokeColor = preset.color.withAlphaComponent(alpha).cgColor
            preview.lineWidth = (isHighlight ? Self.fallbackHighlightHeight : 1.5) * scale
        case .mask:
            preview.strokeColor = MaskStyle.border.cgColor
            preview.fillColor = MaskStyle.fill.withAlphaComponent(0.85).cgColor
            preview.lineWidth = 1
        case .crop:
            preview.strokeColor = UIColor.systemBlue.cgColor
            preview.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
            preview.lineWidth = 1.5
            preview.lineDashPattern = [6, 4]
        case .eraser:
            erase(at: p, in: view)
        default:
            break
        }
    }

    private func move(to newPoints: [CGPoint], in view: PDFView) {
        guard let end = newPoints.last else { return }
        points.append(contentsOf: newPoints)
        editor.lastPencilPoint = end
        switch mode {
        case .mark(let preset):
            if hypot(end.x - startPoint.x, end.y - startPoint.y) > 3 {
                updateMarkPreview(preset, to: end, in: view)
            }
        case .pen:
            setPreview(Self.polyline(points).cgPath)
        case .arrow:
            setPreview(arrowPath(from: startPoint, to: end, lineWidth: preview.lineWidth).cgPath)
        case .circle:
            setPreview(UIBezierPath(ovalIn: Self.rect(startPoint, end)).cgPath)
        case .mask, .crop:
            setPreview(UIBezierPath(rect: Self.rect(startPoint, end)).cgPath)
        case .eraser:
            for pt in newPoints { erase(at: pt, in: view) }
        default:
            break
        }
    }

    private func finish(in view: PDFView) {
        defer {
            setPreview(nil)
            mode = .none
            startPage = nil
            tempMarks = []
            points = []
        }
        guard let page = startPage else { return }
        let end = points.last ?? startPoint
        let moved = hypot(end.x - startPoint.x, end.y - startPoint.y) > 6

        // Un toque (sin arrastrar) sobre una tapa la destapa, con cualquier herramienta de marcado.
        if !moved {
            switch mode {
            case .mark, .pen, .arrow, .circle, .mask:
                removeTempMarks()
                _ = toggleMask(at: end, in: view)
                return
            default:
                break
            }
        }

        switch mode {
        case .mark(let preset):
            if !tempMarks.isEmpty {
                commitTextMarks(on: page, near: end)
            } else if let ann = makeFallbackMark(preset, from: startPoint, to: end, page: page, view: view) {
                let group = Self.groupPrefix + UUID().uuidString
                ann.setValue("\(group)#0", forAnnotationKey: .name)
                add(ann, to: page, actionName: preset.style.label)
                offerTags(group: group, page: page, at: end)
            }
        case .pen(let color):
            if let ann = makeInk(viewPoints: points, page: page, view: view, color: color,
                                 width: CGFloat(store.settings.penWidth)) {
                add(ann, to: page, actionName: "Trazo")
            }
        case .arrow(let color):
            let ann = makeArrow(from: startPoint, to: end, page: page, view: view, color: color,
                                width: CGFloat(store.settings.penWidth))
            add(ann, to: page, actionName: "Flecha")
            editor.finishOneShot(store: store)
        case .circle(let color):
            let ann = PDFAnnotation(bounds: pageRect(startPoint, end, page: page, view: view),
                                    forType: .circle, withProperties: nil)
            ann.color = color
            ann.border = Self.border(CGFloat(store.settings.penWidth))
            ann.userName = "ResiPDF"
            add(ann, to: page, actionName: "Círculo")
            editor.finishOneShot(store: store)
        case .mask:
            let ann = PDFAnnotation(bounds: pageRect(startPoint, end, page: page, view: view),
                                    forType: .square, withProperties: nil)
            ann.color = MaskStyle.border
            ann.interiorColor = MaskStyle.fill
            ann.border = Self.border(0.5)
            ann.setValue(MaskStyle.prefix + UUID().uuidString, forAnnotationKey: .name)
            ann.userName = "ResiPDF"
            add(ann, to: page, actionName: "Tapa")
        case .stamp(let color, let text):
            addStamp(text, at: end, page: page, view: view, color: color)
            editor.finishOneShot(store: store)
        case .note(let color):
            handleNoteTap(at: end, page: page, color: color, in: view)
        case .crop:
            guard moved else { break }
            let rect = pageRect(startPoint, end, page: page, view: view)
            if let image = FigureCropper.image(of: page, rect: rect), let doc = view.document {
                editor.onFigure?(image, doc.index(for: page))
            }
            editor.finishOneShot(store: store)
        default:
            break
        }
    }

    private func cancel() {
        removeTempMarks()
        setPreview(nil)
        mode = .none
        startPage = nil
        points = []
    }

    private func add(_ ann: PDFAnnotation, to page: PDFPage, actionName: String) {
        page.addAnnotation(ann)
        registerAdded([PlacedAnnotation(page: page, annotation: ann)], actionName: actionName)
    }

    // MARK: - Tapas

    /// Destapa / tapa la tapa que haya en ese punto. Devuelve true si había una.
    private func toggleMask(at viewPoint: CGPoint, in view: PDFView) -> Bool {
        guard let page = view.page(for: viewPoint, nearest: false) else { return false }
        let p = view.convert(viewPoint, to: page)
        guard let mask = page.annotations.last(where: { MaskStyle.isMask($0) && $0.bounds.contains(p) }) else {
            return false
        }
        MaskStyle.setRevealed(mask, !MaskStyle.isRevealed(mask))
        return true
    }

    // MARK: - Marcas ajustadas al texto

    private func updateMarkPreview(_ preset: MarkPreset, to end: CGPoint, in view: PDFView) {
        guard let page = startPage else { return }
        removeTempMarks()
        let a = view.convert(startPoint, to: page)
        let b = view.convert(end, to: page)

        if let selection = page.selection(from: a, to: b),
           let text = selection.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setPreview(nil)
            tempText = text
            for line in selection.selectionsByLine() {
                let r = line.bounds(for: page)
                guard r.width > 0.5, r.height > 0.5 else { continue }
                let ann = makeMarkup(preset, bounds: r)
                page.addAnnotation(ann)
                tempMarks.append(ann)
            }
        } else {
            // Sin texto (PDF escaneado): vista previa de un trazo recto.
            tempText = ""
            setPreview(Self.polyline(straightPoints(from: startPoint, to: end)).cgPath)
        }
    }

    private func commitTextMarks(on page: PDFPage, near point: CGPoint) {
        let group = Self.groupPrefix + UUID().uuidString
        defer { offerTags(group: group, page: page, at: point) }
        for (i, ann) in tempMarks.enumerated() {
            ann.setValue("\(group)#\(i)", forAnnotationKey: .name)
            ann.userName = "ResiPDF"
        }
        tempMarks.first?.contents = tempText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let placed = tempMarks.map { PlacedAnnotation(page: page, annotation: $0) }
        registerAdded(placed, actionName: "Marcar")
    }

    private func removeTempMarks() {
        for ann in tempMarks { ann.page?.removeAnnotation(ann) }
        tempMarks = []
    }

    private func makeMarkup(_ preset: MarkPreset, bounds r: CGRect) -> PDFAnnotation {
        let ann: PDFAnnotation
        switch preset.style {
        case .highlight:
            ann = PDFAnnotation(bounds: r, forType: .highlight, withProperties: nil)
            ann.color = preset.color.withAlphaComponent(CGFloat(store.settings.highlightOpacity))
        case .underline:
            ann = PDFAnnotation(bounds: r, forType: .underline, withProperties: nil)
            ann.color = preset.color
        case .strikeOut:
            ann = PDFAnnotation(bounds: r, forType: .strikeOut, withProperties: nil)
            ann.color = preset.color
        case .box:
            let box = PDFAnnotation(bounds: r.insetBy(dx: -1.5, dy: -1), forType: .square, withProperties: nil)
            box.color = preset.color
            box.border = Self.border(1.2)
            return box
        }
        // QuadPoints (relativos al origen de bounds) para compatibilidad con Adobe/Preview.
        ann.quadrilateralPoints = [
            NSValue(cgPoint: CGPoint(x: 0, y: r.height)),
            NSValue(cgPoint: CGPoint(x: r.width, y: r.height)),
            NSValue(cgPoint: CGPoint(x: 0, y: 0)),
            NSValue(cgPoint: CGPoint(x: r.width, y: 0)),
        ]
        return ann
    }

    /// Para páginas sin texto: resaltado/subrayado como trazo recto.
    private func makeFallbackMark(_ preset: MarkPreset, from s: CGPoint, to e: CGPoint,
                                  page: PDFPage, view: PDFView) -> PDFAnnotation? {
        let path = straightPoints(from: s, to: e)
        switch preset.style {
        case .highlight:
            return makeInk(viewPoints: path, page: page, view: view,
                           color: preset.color.withAlphaComponent(CGFloat(store.settings.highlightOpacity)),
                           width: Self.fallbackHighlightHeight)
        case .underline, .strikeOut:
            return makeInk(viewPoints: path, page: page, view: view, color: preset.color, width: 1.5)
        case .box:
            let box = PDFAnnotation(bounds: pageRect(s, e, page: page, view: view), forType: .square, withProperties: nil)
            box.color = preset.color
            box.border = Self.border(1.2)
            return box
        }
    }

    // MARK: - Lápiz y flechas

    private func makeInk(viewPoints: [CGPoint], page: PDFPage, view: PDFView,
                         color: UIColor, width: CGFloat) -> PDFAnnotation? {
        var pts: [CGPoint] = []
        for vp in viewPoints {
            let p = view.convert(vp, to: page)
            if let last = pts.last, hypot(p.x - last.x, p.y - last.y) < 0.4 { continue }
            pts.append(p)
        }
        guard pts.count > 1 else { return nil }

        let xs = pts.map(\.x), ys = pts.map(\.y)
        let bounds = CGRect(x: xs.min()!, y: ys.min()!,
                            width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            .insetBy(dx: -width * 2, dy: -width * 2)

        let local = pts.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) }
        let ann = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        ann.border = Self.border(width)
        ann.color = color
        ann.add(Self.polyline(local))
        ann.userName = "ResiPDF"
        return ann
    }

    private func makeArrow(from s: CGPoint, to e: CGPoint, page: PDFPage, view: PDFView,
                           color: UIColor, width: CGFloat) -> PDFAnnotation {
        let a = view.convert(s, to: page)
        let b = view.convert(e, to: page)
        let pad = max(12, width * 6)
        let bounds = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                            width: abs(a.x - b.x), height: abs(a.y - b.y))
            .insetBy(dx: -pad, dy: -pad)
        let ann = PDFAnnotation(bounds: bounds, forType: .line, withProperties: nil)
        ann.startPoint = CGPoint(x: a.x - bounds.minX, y: a.y - bounds.minY)
        ann.endPoint = CGPoint(x: b.x - bounds.minX, y: b.y - bounds.minY)
        ann.startLineStyle = .none
        ann.endLineStyle = .closedArrow
        ann.color = color
        ann.interiorColor = color
        ann.border = Self.border(width)
        ann.userName = "ResiPDF"
        return ann
    }

    // MARK: - Sellos

    private func addStamp(_ text: String, at viewPoint: CGPoint, page: PDFPage, view: PDFView, color: UIColor) {
        let p = view.convert(viewPoint, to: page)
        let ann = Self.makeStamp(text, centeredAt: p, color: color)
        add(ann, to: page, actionName: "Sello")
    }

    static func makeStamp(_ text: String, centeredAt p: CGPoint, color: UIColor) -> PDFAnnotation {
        let size = (text as NSString).size(withAttributes: [.font: stampFont])
        let w = ceil(size.width) + 12
        let h = ceil(size.height) + 6
        let ann = PDFAnnotation(bounds: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h),
                                forType: .freeText, withProperties: nil)
        ann.contents = text
        ann.font = stampFont
        ann.fontColor = .black
        ann.color = color.withAlphaComponent(0.35)
        ann.alignment = .center
        ann.border = border(0.8)
        ann.setValue(stampPrefix + UUID().uuidString, forAnnotationKey: .name)
        ann.userName = "ResiPDF"
        return ann
    }

    // MARK: - Páginas favoritas (sello ⭐ en la esquina)

    private func favoriteStamp(on page: PDFPage) -> PDFAnnotation? {
        page.annotations.first { Self.isStamp($0) && $0.contents == Self.favoriteSymbol }
    }

    private func toggleFavoriteOnCurrentPage() {
        guard let page = pdfView?.currentPage else { return }
        if let star = favoriteStamp(on: page) {
            removeAnnotations([PlacedAnnotation(page: page, annotation: star)], actionName: "Quitar favorita")
            editor.showToast("Página quitada de favoritas")
        } else {
            let b = page.bounds(for: .cropBox)
            let star = Self.makeStamp(Self.favoriteSymbol, centeredAt: CGPoint(x: b.maxX - 26, y: b.maxY - 22),
                                      color: UIColor(hex: "#FFC94D"))
            add(star, to: page, actionName: "Página favorita")
            editor.showToast("Página añadida a favoritas")
        }
        updatePageState()
    }

    // MARK: - Etiquetas (Dx, Tx, Cx…)

    private func offerTags(group: String, page: PDFPage, at viewPoint: CGPoint) {
        let request = TagRequest(groupID: group, point: viewPoint, tags: []) { [weak self] tags in
            self?.setTags(tags, group: group, page: page)
        }
        editor.lastTagTarget = request
        if store.settings.autoTagBar && !store.settings.tags.isEmpty {
            editor.tagRequest = request
        }
    }

    func setTags(_ tags: [String], group: String, page: PDFPage) {
        let members = page.annotations.filter { Self.groupID(of: $0) == group }
        guard let first = members.first else { return }
        let old = AnnotationTags.tags(of: first)
        members.forEach { AnnotationTags.setTags(tags, on: $0) }
        undoManager?.registerUndo(withTarget: self) { target in
            target.setTags(old, group: group, page: page)
        }
        undoManager?.setActionName("Etiquetas")
        if editor.lastTagTarget?.groupID == group { editor.lastTagTarget?.tags = tags }
        editor.annotationsVersion += 1
    }

    static func isStamp(_ a: PDFAnnotation) -> Bool {
        (a.value(forAnnotationKey: .name) as? String)?.hasPrefix(stampPrefix) == true
    }

    // MARK: - Comentarios

    private func handleNoteTap(at viewPoint: CGPoint, page: PDFPage, color: UIColor, in view: PDFView) {
        let p = view.convert(viewPoint, to: page)
        if let existing = page.annotation(at: p), existing.type == "FreeText", !Self.isStamp(existing) {
            let old = existing.contents ?? ""
            editor.noteRequest = NoteRequest(
                initialText: old,
                isEditing: true,
                onSave: { [weak self] text in self?.updateNote(existing, on: page, text: text, oldText: old) },
                onDelete: { [weak self] in
                    self?.removeAnnotations([PlacedAnnotation(page: page, annotation: existing)],
                                            actionName: "Borrar comentario")
                }
            )
            return
        }
        editor.noteRequest = NoteRequest(
            initialText: "",
            isEditing: false,
            onSave: { [weak self] text in self?.addNote(text: text, topLeft: p, page: page, color: color) },
            onDelete: {}
        )
    }

    private func addNote(text: String, topLeft p: CGPoint, page: PDFPage, color: UIColor) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let ann = PDFAnnotation(bounds: noteBounds(for: t, topLeft: p, page: page),
                                forType: .freeText, withProperties: nil)
        ann.contents = t
        ann.font = Self.noteFont
        ann.fontColor = .black
        ann.color = color.withAlphaComponent(0.25)
        ann.alignment = .left
        ann.userName = "ResiPDF"
        ann.border = Self.border(0.8)
        add(ann, to: page, actionName: "Comentario")
        editor.finishOneShot(store: store)
    }

    private func updateNote(_ ann: PDFAnnotation, on page: PDFPage, text: String, oldText: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            removeAnnotations([PlacedAnnotation(page: page, annotation: ann)], actionName: "Borrar comentario")
            return
        }
        let topLeft = CGPoint(x: ann.bounds.minX, y: ann.bounds.maxY)
        ann.contents = t
        ann.bounds = noteBounds(for: t, topLeft: topLeft, page: page)
        undoManager?.registerUndo(withTarget: self) { target in
            target.updateNote(ann, on: page, text: oldText, oldText: t)
        }
        undoManager?.setActionName("Editar comentario")
    }

    private func noteBounds(for text: String, topLeft p: CGPoint, page: PDFPage) -> CGRect {
        let maxWidth: CGFloat = 220
        let size = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.noteFont],
            context: nil
        ).size
        let w = ceil(size.width) + 14
        let h = ceil(size.height) + 10
        // En coordenadas PDF el eje Y crece hacia arriba.
        var r = CGRect(x: p.x, y: p.y - h, width: w, height: h)
        let pb = page.bounds(for: .cropBox)
        if r.maxX > pb.maxX { r.origin.x = pb.maxX - w - 4 }
        if r.minY < pb.minY { r.origin.y = pb.minY + 4 }
        return r
    }

    // MARK: - Borrador

    private func erase(at viewPoint: CGPoint, in view: PDFView) {
        guard let page = view.page(for: viewPoint, nearest: false) else { return }
        let p = view.convert(viewPoint, to: page)
        guard let hit = page.annotation(at: p), Self.isErasable(hit) else { return }
        let victims = groupMembers(of: hit, on: page).map { PlacedAnnotation(page: page, annotation: $0) }
        removeAnnotations(victims, actionName: "Borrar")
    }

    static func isErasable(_ a: PDFAnnotation) -> Bool {
        !["Link", "Widget", "Popup"].contains(a.type ?? "")
    }

    static func groupID(of a: PDFAnnotation) -> String? {
        guard let name = a.value(forAnnotationKey: .name) as? String, name.hasPrefix(groupPrefix) else { return nil }
        return name.components(separatedBy: "#").first
    }

    private func groupMembers(of a: PDFAnnotation, on page: PDFPage) -> [PDFAnnotation] {
        guard let g = Self.groupID(of: a) else { return [a] }
        return page.annotations.filter { Self.groupID(of: $0) == g }
    }

    // MARK: - Deshacer / rehacer (también marca el documento como modificado => autoguardado)

    private func registerAdded(_ items: [PlacedAnnotation], actionName: String) {
        editor.annotationsVersion += 1
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { target in
            target.removeAnnotations(items, actionName: actionName)
        }
        um.setActionName(actionName)
    }

    func removeAnnotations(_ items: [PlacedAnnotation], actionName: String) {
        for item in items { item.page.removeAnnotation(item.annotation) }
        editor.annotationsVersion += 1
        updatePageState()
        undoManager?.registerUndo(withTarget: self) { target in
            target.addAnnotations(items, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    func addAnnotations(_ items: [PlacedAnnotation], actionName: String) {
        for item in items { item.page.addAnnotation(item.annotation) }
        registerAdded(items, actionName: actionName)
        updatePageState()
    }

    // MARK: - Geometría y vista previa

    private func setPreview(_ path: CGPath?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.path = path
        CATransaction.commit()
    }

    private static func border(_ width: CGFloat) -> PDFBorder {
        let b = PDFBorder()
        b.lineWidth = width
        return b
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func pageRect(_ s: CGPoint, _ e: CGPoint, page: PDFPage, view: PDFView) -> CGRect {
        Self.rect(view.convert(s, to: page), view.convert(e, to: page))
    }

    /// Si el trazo es casi horizontal, se endereza (subrayado limpio).
    private func straightPoints(from s: CGPoint, to e: CGPoint) -> [CGPoint] {
        if abs(e.y - s.y) < 14 { return [s, CGPoint(x: e.x, y: s.y)] }
        return [s, e]
    }

    private func arrowPath(from s: CGPoint, to e: CGPoint, lineWidth: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: s)
        path.addLine(to: e)
        let angle = atan2(e.y - s.y, e.x - s.x)
        let head = max(12, lineWidth * 5)
        for delta in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
            path.move(to: e)
            path.addLine(to: CGPoint(x: e.x + head * cos(angle + delta), y: e.y + head * sin(angle + delta)))
        }
        return path
    }

    static func polyline(_ pts: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }
}
