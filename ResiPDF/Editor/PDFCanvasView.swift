import SwiftUI
import PDFKit

/// Envuelve PDFView (UIKit) para SwiftUI.
struct PDFCanvasView: UIViewRepresentable {
    let document: PDFDocument
    @ObservedObject var editor: EditorState
    @ObservedObject var store: SettingsStore
    var undoManager: UndoManager?

    func makeCoordinator() -> AnnotationController {
        AnnotationController()
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .systemGroupedBackground
        view.document = document
        Self.applyReadingMode(store.settings.readingMode, to: view)

        let controller = context.coordinator
        controller.editor = editor
        controller.store = store
        controller.undoManager = undoManager
        controller.attach(to: view)
        editor.pdfView = view
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let controller = context.coordinator
        controller.editor = editor
        controller.store = store
        controller.undoManager = undoManager
        if view.document !== document { view.document = document }
        Self.applyReadingMode(store.settings.readingMode, to: view)
        controller.applyInputMode()
    }

    static func applyReadingMode(_ mode: ReadingMode, to view: PDFView) {
        switch mode {
        case .continuous:
            guard view.isUsingPageViewController || view.displayMode != .singlePageContinuous else { return }
            view.usePageViewController(false, withViewOptions: nil)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
        case .paged:
            guard !view.isUsingPageViewController else { return }
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.usePageViewController(true, withViewOptions: nil)
        }
        view.autoScales = true
    }
}
