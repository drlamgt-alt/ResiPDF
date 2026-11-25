import SwiftUI
import PDFKit

/// Qué se ve en el cuaderno: una hoja escrita o un anexo automático.
enum NotebookSection: Hashable {
    case page(UUID)
    case annex(AnnexKind)
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Cuaderno del libro (estilo GoodNotes), junto al PDF.
struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var editor: EditorState
    @ObservedObject var settings: SettingsStore
    let pdf: PDFDocument
    @Binding var fullScreen: Bool
    var onClose: () -> Void

    @State private var section: NotebookSection?
    @StateObject private var canvas = CanvasController()
    @State private var moveImages = false
    @State private var items: [AnnotationItem] = []
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var exportFile: ExportFile?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sectionStrip
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray5))
        }
        .background(Color(.secondarySystemBackground))
        .onAppear(perform: selectInitialSection)
        .onChange(of: store.revision) { _, _ in validateSection() }
        .onChange(of: section) { _, newValue in
            if case .page(let id) = newValue { store.currentPageID = id }
            if case .annex = newValue { moveImages = false }
        }
        .task(id: editor.annotationsVersion) {
            items = AnnotationBrowser.collect(pdf: pdf, store: settings)
        }
        .onDisappear { store.saveNow() }
        .alert("Nombre de la hoja", isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField("Título", text: $renameText)
            Button("Guardar") {
                if let id = renamingID { store.renamePage(id, to: renameText) }
                renamingID = nil
            }
            Button("Cancelar", role: .cancel) { renamingID = nil }
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: - Barra superior

    private var header: some View {
        HStack(spacing: 14) {
            Label("Cuaderno", systemImage: "book.pages")
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 0)
            if isPageSection {
                iconButton("arrow.uturn.backward", "Deshacer") { canvas.undo() }
                iconButton("arrow.uturn.forward", "Rehacer") { canvas.redo() }
                Button { moveImages.toggle() } label: {
                    Image(systemName: moveImages ? "hand.draw.fill" : "hand.draw")
                        .foregroundStyle(moveImages ? Color.accentColor : Color.primary)
                }
                .accessibilityLabel(moveImages ? "Terminar de mover imágenes" : "Mover imágenes")
            }
            addPageMenu
            iconButton("square.and.arrow.up", "Exportar cuaderno a PDF") { export() }
            iconButton(fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                       fullScreen ? "Ver junto al libro" : "Cuaderno a pantalla completa") {
                withAnimation(.spring(response: 0.35)) { fullScreen.toggle() }
            }
            iconButton("xmark", "Cerrar cuaderno") { onClose() }
        }
        .font(.body.weight(.medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .accessibilityLabel(label)
    }

    private var addPageMenu: some View {
        Menu {
            ForEach(PaperStyle.allCases) { paper in
                Button {
                    var after: UUID?
                    if case .page(let id) = section { after = id }
                    if let id = store.addPage(paper, after: after) { section = .page(id) }
                } label: {
                    Label("Hoja \(paper.label.lowercased())", systemImage: paper.symbol)
                }
            }
        } label: {
            Image(systemName: "doc.badge.plus")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Nueva hoja")
    }

    // MARK: - Hojas y anexos

    private var sectionStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        pageChip(page, number: index + 1)
                            .id(NotebookSection.page(page.id))
                    }
                    Divider().frame(height: 22).padding(.horizontal, 4)
                    Text("ANEXOS")
                        .font(.caption2.weight(.bold))
                        .kerning(0.8)
                        .foregroundStyle(.secondary)
                    ForEach(AnnexKind.allCases) { kind in
                        annexChip(kind)
                            .id(NotebookSection.annex(kind))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: section) { _, newValue in
                if let newValue { withAnimation { proxy.scrollTo(newValue, anchor: .center) } }
            }
        }
    }

    private func pageChip(_ page: NotebookPage, number: Int) -> some View {
        let selected = section == .page(page.id)
        return Button { section = .page(page.id) } label: {
            HStack(spacing: 5) {
                Image(systemName: page.paper.symbol).font(.caption2)
                Text("\(number) · \(page.title)").lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = page.title
                renamingID = page.id
            } label: { Label("Renombrar", systemImage: "pencil") }
            Menu {
                ForEach(PaperStyle.allCases) { paper in
                    Button { store.setPaper(page.id, paper) } label: {
                        Label(paper.label, systemImage: paper == page.paper ? "checkmark" : paper.symbol)
                    }
                }
            } label: { Label("Tipo de papel", systemImage: "doc.richtext") }
            if store.pages.count > 1 {
                Button(role: .destructive) { store.deletePage(page.id) } label: {
                    Label("Eliminar hoja", systemImage: "trash")
                }
            }
        }
    }

    private func annexChip(_ kind: AnnexKind) -> some View {
        let selected = section == .annex(kind)
        let count = kind == .figures ? store.figures.count : items.filter { $0.action == kind.action }.count
        let color = settings.settings.presets.first { $0.action == kind.action }?.color
        return Button { section = .annex(kind) } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(Color(color)).frame(width: 8, height: 8)
                } else {
                    Image(systemName: kind.symbol).font(.caption2)
                }
                Text("\(kind.letter) · \(kind.shortTitle)")
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.3) : Color(.systemGray4)))
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        switch section {
        case .page(let id)?:
            PageCanvas(pageID: id, store: store, controller: canvas, moveMode: moveImages) { goToBookPage($0) }
                .padding(12)
                .overlay(alignment: .bottom) {
                    if moveImages {
                        Text("Arrastra o pellizca las imágenes · mantén pulsada una para quitarla")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.bottom, 20)
                    }
                }
        case .annex(let kind)?:
            AnnexView(kind: kind, items: items, store: store, presets: settings.settings.presets,
                      onGo: goToBookPage, onInsert: insertFigure)
        case nil:
            Color.clear
        }
    }

    private var isPageSection: Bool {
        if case .page = section { return true }
        return false
    }

    // MARK: - Acciones

    private func selectInitialSection() {
        if let requested = store.requestedSection {
            store.requestedSection = nil
            section = requested
            return
        }
        guard section == nil else { return }
        if let id = store.currentPageID, store.page(id) != nil {
            section = .page(id)
        } else if let first = store.pages.first {
            section = .page(first.id)
        }
    }

    private func validateSection() {
        if case .page(let id) = section, store.page(id) == nil {
            section = store.pages.first.map { .page($0.id) }
        }
        if section == nil { selectInitialSection() }
    }

    private func goToBookPage(_ index: Int) {
        guard let page = pdf.page(at: index) else { return }
        if fullScreen { withAnimation { fullScreen = false } }
        editor.go(to: page)
    }

    private func insertFigure(_ figure: NotebookFigure) {
        guard let pageID = store.currentPageID ?? store.pages.first?.id else { return }
        store.insert(figure, into: pageID)
        section = .page(pageID)
        editor.showToast("Figura insertada en la hoja")
    }

    private func export() {
        store.saveNow()
        do {
            exportFile = ExportFile(url: try NotebookExporter.export(store: store, items: items))
        } catch {
            editor.showToast("No se pudo exportar el cuaderno")
        }
    }
}

/// Hoja de compartir del sistema (AirDrop, Archivos, imprimir…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
