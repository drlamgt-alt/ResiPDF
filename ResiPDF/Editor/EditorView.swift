import SwiftUI
import PDFKit

struct EditorView: View {
    @ObservedObject var document: PDFFileDocument
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.undoManager) private var undoManager
    @StateObject private var editor = EditorState()

    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showSidebar = false
    @State private var sidebarTab: SidebarTab = .outline
    @State private var masksRevealed = false
    @State private var dockSize: CGSize = .zero
    @State private var showGoToPage = false
    @State private var goToPageText = ""

    // Cuaderno del libro
    @StateObject private var notebook: NotebookStore
    @State private var showNotebook = false
    @State private var notebookFull = false
    @State private var showNotebookPrompt = false
    @State private var promptIsAutomatic = false

    init(document: PDFFileDocument, bookName: String) {
        _document = ObservedObject(wrappedValue: document)
        _notebook = StateObject(wrappedValue: NotebookStore(bookName: bookName))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar && !(showNotebook && notebookFull) {
                SidebarView(pdf: document.pdf, editor: editor, store: store, initialTab: sidebarTab)
                    .frame(width: 320)
                    .transition(.move(edge: .leading))
                Divider()
            }
            if !(showNotebook && notebookFull) {
                ZStack {
                    canvas
                    DockView(editor: editor, undoManager: undoManager) { dockSize = $0 }
                }
            }
            if showNotebook {
                Divider()
                notebookPanel
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showNotebook)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: notebookFull)
        .alert("¿Crear un cuaderno para este libro?", isPresented: $showNotebookPrompt) {
            Button("Crear cuaderno") {
                notebook.create()
                showNotebook = true
            }
            if promptIsAutomatic {
                Button("No volver a preguntar") { notebook.promptDeclined = true }
            }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text("Hojas para escribir con el Pencil (plantilla Cornell) y anexos que se llenan solos con tus preguntas de examen, lo que hay que memorizar, figuras recortadas y dudas.")
        }
        .overlay(alignment: .top) { toastView }
        .animation(.easeOut(duration: 0.2), value: editor.toast)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSidebar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(pdf: document.pdf,
                       onSelect: { editor.go(to: $0) },
                       onPage: { editor.go(to: $0) })
        }
        .sheet(item: $editor.noteRequest) { request in
            NoteEditorSheet(request: request)
        }
        .alert("Ir a la página", isPresented: $showGoToPage) {
            TextField("Número de página", text: $goToPageText)
                .keyboardType(.numberPad)
            Button("Ir") {
                if let n = Int(goToPageText), let page = document.pdf.page(at: n - 1) { editor.go(to: page) }
                goToPageText = ""
            }
            Button("Cancelar", role: .cancel) { goToPageText = "" }
        } message: {
            Text("El libro tiene \(document.pdf.pageCount) páginas.")
        }
        .task(id: editor.tagRequest?.id) {
            // La barra de etiquetas se cierra sola si no se usa.
            guard let id = editor.tagRequest?.id else { return }
            // En el modo de capturas se deja visible para poder fotografiarla.
            if ProcessInfo.processInfo.arguments.contains("-demoTags") { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if editor.tagRequest?.id == id { withAnimation { editor.tagRequest = nil } }
        }
        .onAppear {
            // Al abrir un PDF ya queda listo el primer color: Pencil marca, dedo navega.
            if editor.tool == .navigate { editor.selectFirstPreset(store: store) }
            editor.onFigure = { image, pageIndex in saveFigure(image, pageIndex: pageIndex) }
            offerNotebookIfNeeded()
            openDemoScreenIfRequested()
        }
        .onDisappear { notebook.saveNow() }
        .onChange(of: store.settings.activeProfileID) { _, _ in
            editor.selectFirstPreset(store: store)
        }
    }

    // MARK: - Cuaderno

    private var notebookPanel: some View {
        NotebookView(store: notebook, editor: editor, settings: store, pdf: document.pdf,
                     fullScreen: $notebookFull) {
            notebook.saveNow()
            showNotebook = false
            notebookFull = false
        }
        .containerRelativeFrame(.horizontal) { width, _ in
            notebookFull ? width : max(360, width * 0.46)
        }
        .transition(.move(edge: .trailing))
    }

    private func toggleNotebook() {
        if notebook.exists {
            showNotebook.toggle()
        } else {
            promptIsAutomatic = false
            showNotebookPrompt = true
        }
    }

    /// Al abrir un libro sin cuaderno, ofrece crearlo (salvo que se haya dicho «No volver a preguntar»).
    private func offerNotebookIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("-demo"),
              !notebook.exists, !notebook.promptDeclined else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            promptIsAutomatic = true
            showNotebookPrompt = true
        }
    }

    private func saveFigure(_ image: UIImage, pageIndex: Int) {
        guard let figure = notebook.addFigure(image, sourcePage: pageIndex) else {
            editor.showToast("No se pudo guardar la figura")
            return
        }
        if showNotebook, let pageID = notebook.currentPageID {
            notebook.insert(figure, into: pageID)
            editor.showToast("Figura insertada en el cuaderno")
        } else {
            editor.showToast("Figura guardada en el cuaderno · Anexo C")
        }
    }

    // MARK: - Lienzo

    /// Espacio que el PDF deja libre para que el dock no tape el texto.
    private var dockInset: CGFloat {
        let edge = store.settings.dockEdge
        let thickness = edge.isVertical ? dockSize.width : dockSize.height
        guard thickness > 0 else { return 0 }
        // En horizontal, el nombre del color activo flota sobre el dock: se reserva su altura.
        let labelSpace: CGFloat = edge.isVertical ? 0 : 30
        return thickness + DockView.margin * 2 + labelSpace
    }

    private var canvas: some View {
        PDFCanvasView(document: document.pdf, editor: editor, store: store, undoManager: undoManager)
            .overlay { canvasOverlays }
            .overlay(alignment: .topTrailing) { pageChip }
            .padding(store.settings.dockEdge.edgeSet, dockInset)
            .animation(.spring(response: 0.3), value: dockInset)
    }

    /// Capas sobre el PDF (mismas coordenadas que la vista PDF).
    private var canvasOverlays: some View {
        ZStack {
            if let request = editor.tagRequest {
                GeometryReader { geo in
                    TagBar(request: request, tags: store.settings.tags) {
                        withAnimation { editor.tagRequest = nil }
                    }
                    .position(x: min(max(request.point.x, 170), max(geo.size.width - 170, 170)),
                              y: max(request.point.y - 46, 28))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .id(request.id)
            }
            if let point = editor.quickPalettePoint {
                QuickRing(center: point, editor: editor)
            }
        }
        .animation(.spring(response: 0.25), value: editor.tagRequest?.id)
        .animation(.spring(response: 0.25), value: editor.quickPalettePoint)
    }

    private var pageChip: some View {
        Button {
            showGoToPage = true
        } label: {
            Text("\(editor.currentPageIndex + 1) / \(document.pdf.pageCount)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Página \(editor.currentPageIndex + 1) de \(document.pdf.pageCount). Ir a otra página")
    }

    @ViewBuilder
    private var toastView: some View {
        if let text = editor.toast {
            Text(text)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Barra superior

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSidebar.toggle()
            } label: {
                Label("Barra lateral", systemImage: "sidebar.left")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showSearch = true } label: {
                Label("Buscar o ir a página", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Button { toggleNotebook() } label: {
                Label("Cuaderno", systemImage: showNotebook ? "book.pages.fill" : "book.pages")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button { editor.toggleFavorite?() } label: {
                Label("Página favorita", systemImage: editor.currentPageIsFavorite ? "star.fill" : "star")
            }

            patternMenu

            Menu {
                Button {
                    masksRevealed.toggle()
                    editor.setAllMasks(revealed: masksRevealed)
                } label: {
                    Label(masksRevealed ? "Cubrir tapas" : "Destapar tapas",
                          systemImage: masksRevealed ? "eye.slash" : "eye")
                }
                Picker("Lectura", selection: $store.settings.readingMode) {
                    ForEach(ReadingMode.allCases) { Text($0.label).tag($0) }
                }
                Button {
                    sidebarTab = .marks
                    showSidebar = true
                } label: {
                    Label("Ver y exportar marcas", systemImage: "list.bullet.rectangle")
                }
                Divider()
                Button { showSettings = true } label: {
                    Label("Preferencias", systemImage: "gearshape")
                }
            } label: {
                Label("Más", systemImage: "ellipsis.circle")
            }
        }
    }

    /// Cambio rápido de patrón de colores según el libro que estés leyendo.
    private var patternMenu: some View {
        Menu {
            Picker("Patrón de colores", selection: Binding(
                get: { store.settings.activeProfile.id },
                set: { store.settings.activeProfileID = $0 }
            )) {
                ForEach(store.settings.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
        } label: {
            Label(store.settings.activeProfile.name, systemImage: "paintpalette")
        }
    }

    // MARK: - Capturas automáticas (modo `-demo`)

    private func openDemoScreenIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if args.contains("-demoSettings") { showSettings = true }
            if args.contains("-demoMarks") { sidebarTab = .marks; showSidebar = true }
            if args.contains("-demoSidebar") { sidebarTab = .outline; showSidebar = true }
            if args.contains("-demoRing") {
                let bounds = editor.pdfView?.bounds ?? CGRect(x: 0, y: 0, width: 800, height: 1000)
                editor.quickPalettePoint = CGPoint(x: bounds.midX + 120, y: bounds.midY - 80)
            }
            if args.contains("-demoNotebook") || args.contains("-demoAnnex") {
                DemoNotebook.populate(notebook, pdf: document.pdf)
                if args.contains("-demoAnnex") { notebook.requestedSection = .annex(.questions) }
                showNotebook = true
            }
            if args.contains("-demoTags") {
                let bounds = editor.pdfView?.bounds ?? CGRect(x: 0, y: 0, width: 800, height: 1000)
                editor.tagRequest = TagRequest(groupID: "demo", point: CGPoint(x: bounds.midX, y: bounds.height * 0.42),
                                               tags: ["Dx"]) { _ in }
            }
        }
    }
}
