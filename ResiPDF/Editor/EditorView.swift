import SwiftUI
import PDFKit

struct EditorView: View {
    @ObservedObject var document: PDFFileDocument
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.undoManager) private var undoManager
    @StateObject private var editor = EditorState()
    @State private var showSettings = false
    @State private var showList = false
    @State private var showSearch = false
    @State private var masksRevealed = false

    var body: some View {
        ZStack {
            PDFCanvasView(document: document.pdf, editor: editor, store: store, undoManager: undoManager)
                .padding(store.settings.paletteOnLeft ? .leading : .trailing, paletteInset)
                .ignoresSafeArea(edges: .bottom)
                .animation(.spring(response: 0.3), value: paletteInset)

            FloatingPalette(editor: editor, undoManager: undoManager)

            if let point = editor.quickPalettePoint {
                QuickRing(center: CGPoint(x: point.x + (store.settings.paletteOnLeft ? paletteInset : 0), y: point.y),
                          editor: editor)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay(alignment: .top) {
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
        .animation(.easeOut(duration: 0.2), value: editor.toast)
        .animation(.spring(response: 0.25), value: editor.quickPalettePoint)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showSearch = true } label: {
                    Label("Buscar / ir a página", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)

                Button {
                    masksRevealed.toggle()
                    editor.setAllMasks(revealed: masksRevealed)
                } label: {
                    Label(masksRevealed ? "Cubrir tapas" : "Destapar tapas",
                          systemImage: masksRevealed ? "eye.slash" : "eye")
                }

                profileMenu

                Button { showList = true } label: {
                    Label("Anotaciones", systemImage: "list.bullet.rectangle")
                }
                Button { showSettings = true } label: {
                    Label("Preferencias", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $showList) {
            AnnotationListView(pdf: document.pdf, store: store) { page in
                editor.go(to: page)
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView(pdf: document.pdf,
                       onSelect: { editor.go(to: $0) },
                       onPage: { editor.go(to: $0) })
        }
        .sheet(item: $editor.noteRequest) { request in
            NoteEditorSheet(request: request)
        }
        .onAppear {
            // Al abrir un PDF ya queda listo el primer marcador: Pencil marca, dedo navega.
            if editor.tool == .navigate { editor.selectFirstPreset(store: store) }
            openDemoScreenIfRequested()
        }
        .onChange(of: store.settings.activeProfileID) { _, _ in
            editor.selectFirstPreset(store: store)
        }
    }

    /// Espacio que el PDF deja libre para que la paleta no tape el texto.
    private var paletteInset: CGFloat {
        FloatingPalette.reservedWidth(buttonSize: store.settings.buttonSize.points,
                                      collapsed: editor.paletteCollapsed)
    }

    /// Solo para las capturas automáticas (modo `-demo`).
    private func openDemoScreenIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if args.contains("-demoSettings") { showSettings = true }
            if args.contains("-demoList") { showList = true }
            if args.contains("-demoRing") {
                let bounds = editor.pdfView?.bounds ?? CGRect(x: 0, y: 0, width: 800, height: 1000)
                editor.quickPalettePoint = CGPoint(x: bounds.midX + 120, y: bounds.midY - 80)
            }
        }
    }

    /// Cambio rápido de perfil (Cirugía, Anatomía…) según el libro que estés leyendo.
    private var profileMenu: some View {
        Menu {
            Picker("Perfil de colores", selection: Binding(
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
}
