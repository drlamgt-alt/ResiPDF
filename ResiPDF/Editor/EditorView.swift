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

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(pdf: document.pdf, editor: editor, store: store, initialTab: sidebarTab)
                    .frame(width: 320)
                    .transition(.move(edge: .leading))
                Divider()
            }
            ZStack {
                canvas
                DockView(editor: editor, undoManager: undoManager) { dockSize = $0 }
            }
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
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if editor.tagRequest?.id == id { withAnimation { editor.tagRequest = nil } }
        }
        .onAppear {
            // Al abrir un PDF ya queda listo el primer color: Pencil marca, dedo navega.
            if editor.tool == .navigate { editor.selectFirstPreset(store: store) }
            openDemoScreenIfRequested()
        }
        .onChange(of: store.settings.activeProfileID) { _, _ in
            editor.selectFirstPreset(store: store)
        }
    }

    // MARK: - Lienzo

    /// Espacio que el PDF deja libre para que el dock no tape el texto.
    private var dockInset: CGFloat {
        let edge = store.settings.dockEdge
        let thickness = edge.isVertical ? dockSize.width : dockSize.height
        return thickness > 0 ? thickness + DockView.margin * 2 : 0
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
            if args.contains("-demoTags") {
                let bounds = editor.pdfView?.bounds ?? CGRect(x: 0, y: 0, width: 800, height: 1000)
                editor.tagRequest = TagRequest(groupID: "demo", point: CGPoint(x: bounds.midX, y: bounds.height * 0.42),
                                               tags: ["Dx"]) { _ in }
            }
        }
    }
}
