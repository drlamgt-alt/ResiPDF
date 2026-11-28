import SwiftUI
import PDFKit

/// Qué se ve en el cuaderno.
enum NotebookSection: Hashable {
    /// Guía de estudio por temas (se arma sola con las marcas).
    case guide
    /// Todas las hojas en miniatura (como en GoodNotes).
    case overview
    case page(UUID)
    case annex(AnnexKind)
}

struct ExportFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Cuaderno del libro (estilo GoodNotes). Se abre junto al PDF o solo, desde «Cuadernos».
struct NotebookView: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var editor: EditorState
    @ObservedObject var settings: SettingsStore
    /// nil cuando el cuaderno se abre sin su libro (desde «Cuadernos»).
    let pdf: PDFDocument?
    @Binding var fullScreen: Bool
    var onClose: () -> Void

    @State private var section: NotebookSection?
    @StateObject private var canvas = CanvasController()
    @State private var moveImages = false
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var exportFiles: ExportFiles?
    @State private var exporting = false

    private var standalone: Bool { pdf == nil }

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
            if case .page(let id) = newValue { store.currentPageID = id } else { moveImages = false }
        }
        .task(id: editor.annotationsVersion) {
            // Copia las marcas del libro al cuaderno: así la guía se ve también sin el PDF.
            guard let pdf else { return }
            let items = AnnotationBrowser.collect(pdf: pdf, store: settings)
            store.updateMarks(StudyGuide.build(items: items, pdf: pdf))
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
        .sheet(item: $exportFiles) { files in
            ShareSheet(items: files.urls)
        }
        .overlay {
            if exporting {
                ProgressView("Exportando…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Barra superior

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(UIColor(hex: store.notebook?.coverHex ?? "#3B6FD9")))
                    .frame(width: 14, height: 20)
                Text(store.bookName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if case .page(let id) = section {
                pageStepper(id)
                iconButton("pencil.tip.crop.circle", "Mostrar u ocultar bolígrafos") { canvas.toggleTools() }
                iconButton("arrow.uturn.backward", "Deshacer") { canvas.undo() }
                iconButton("arrow.uturn.forward", "Rehacer") { canvas.redo() }
                Button { moveImages.toggle() } label: {
                    Image(systemName: moveImages ? "hand.draw.fill" : "hand.draw")
                        .foregroundStyle(moveImages ? Color.accentColor : Color.primary)
                }
                .accessibilityLabel(moveImages ? "Terminar de mover imágenes" : "Mover imágenes")
            }
            addPageMenu
            exportMenu
            if !standalone {
                iconButton(fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                           fullScreen ? "Ver junto al libro" : "Cuaderno a pantalla completa") {
                    withAnimation(.spring(response: 0.35)) { fullScreen.toggle() }
                }
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

    /// ‹ 2 / 5 › para pasar de hoja como en un cuaderno.
    private func pageStepper(_ id: UUID) -> some View {
        let pages = store.pages
        let index = pages.firstIndex { $0.id == id } ?? 0
        return HStack(spacing: 6) {
            Button { section = .page(pages[max(index - 1, 0)].id) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
                .accessibilityLabel("Hoja anterior")
            Text("\(index + 1) / \(pages.count)")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
            Button { section = .page(pages[min(index + 1, pages.count - 1)].id) } label: { Image(systemName: "chevron.right") }
                .disabled(index >= pages.count - 1)
                .accessibilityLabel("Hoja siguiente")
        }
    }

    private var addPageMenu: some View {
        Menu {
            Section("Nueva hoja") {
                ForEach(PaperStyle.allCases) { paper in
                    Button {
                        var after: UUID?
                        if case .page(let id) = section { after = id }
                        if let id = store.addPage(paper, after: after) { section = .page(id) }
                    } label: {
                        Label(paper.label, systemImage: paper.symbol)
                        Text(paper.hint)
                    }
                }
            }
        } label: {
            Image(systemName: "doc.badge.plus")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Nueva hoja")
    }

    private var exportMenu: some View {
        Menu {
            Section("Exportar cuaderno") {
                ForEach(NotebookExporter.Format.allCases) { format in
                    Button { export(format) } label: {
                        Label(format.label, systemImage: format.symbol)
                        Text(format.hint)
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Exportar")
    }

    // MARK: - Hojas y anexos

    private var sectionStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(.guide, selected: section == .guide, highlight: true) {
                        Label("Guía de estudio", systemImage: "list.star")
                        countBadge(store.studyMarks.count, selected: section == .guide)
                    }
                    chip(.overview, selected: section == .overview) {
                        Label("Hojas", systemImage: "square.grid.2x2")
                    }
                    Divider().frame(height: 22).padding(.horizontal, 4)
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

    private func chip<L: View>(_ target: NotebookSection, selected: Bool, highlight: Bool = false,
                               @ViewBuilder label: () -> L) -> some View {
        Button { section = target } label: {
            HStack(spacing: 5) { label() }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor
                                           : (highlight ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill))))
                .foregroundStyle(selected ? Color.white : (highlight ? Color.accentColor : Color.primary))
        }
        .buttonStyle(.plain)
        .id(target)
    }

    @ViewBuilder
    private func countBadge(_ count: Int, selected: Bool) -> some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(selected ? Color.white.opacity(0.3) : Color(.systemGray4)))
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
        .contextMenu { PageMenu(page: page, store: store, onRename: startRename, onOpen: { section = .page($0) }) }
    }

    private func annexChip(_ kind: AnnexKind) -> some View {
        let selected = section == .annex(kind)
        let count = kind == .figures ? store.figures.count : AnnexView.entries(kind, in: store.marks).count
        let color = settings.settings.presets.first { $0.action == kind.action }?.color
        return Button { section = .annex(kind) } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle().fill(Color(color)).frame(width: 8, height: 8)
                } else {
                    Image(systemName: kind.symbol).font(.caption2)
                }
                Text("\(kind.letter) · \(kind.shortTitle)")
                countBadge(count, selected: selected)
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
        case .guide?:
            StudyGuideView(store: store, standalone: standalone, onGo: goToBookPage)
        case .overview?:
            PagesOverview(store: store, onOpen: { section = .page($0) }, onRename: startRename)
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
            AnnexView(kind: kind, store: store, presets: settings.settings.presets,
                      onGo: goToBookPage, onInsert: insertFigure)
        case nil:
            Color.clear
        }
    }

    // MARK: - Acciones

    private func startRename(_ page: NotebookPage) {
        renameText = page.title
        renamingID = page.id
    }

    private func selectInitialSection() {
        if let requested = store.requestedSection {
            store.requestedSection = nil
            section = requested
            return
        }
        guard section == nil else { return }
        if let id = store.currentPageID, store.page(id) != nil {
            section = .page(id)
        } else if standalone {
            section = .guide
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
        guard let pdf, let page = pdf.page(at: index) else {
            editor.showToast("Abre el libro para ir a la p. \(index + 1)")
            return
        }
        if fullScreen { withAnimation { fullScreen = false } }
        editor.go(to: page)
    }

    private func insertFigure(_ figure: NotebookFigure) {
        guard let pageID = store.currentPageID ?? store.pages.first?.id else { return }
        store.insert(figure, into: pageID)
        section = .page(pageID)
        editor.showToast("Figura insertada en la hoja")
    }

    private func export(_ format: NotebookExporter.Format) {
        store.saveNow()
        exporting = true
        DispatchQueue.main.async {
            defer { exporting = false }
            do {
                exportFiles = ExportFiles(urls: try NotebookExporter.export(store: store, format: format))
            } catch {
                editor.showToast("No se pudo exportar el cuaderno")
            }
        }
    }
}

/// Menú de una hoja (renombrar, plantilla, color, duplicar, mover, eliminar).
struct PageMenu: View {
    let page: NotebookPage
    @ObservedObject var store: NotebookStore
    var onRename: (NotebookPage) -> Void
    var onOpen: (UUID) -> Void

    var body: some View {
        Button { onRename(page) } label: { Label("Renombrar", systemImage: "pencil") }
        Menu {
            ForEach(PaperStyle.allCases) { paper in
                Button { store.setPaper(page.id, paper) } label: {
                    Label(paper.label, systemImage: paper == page.paper ? "checkmark" : paper.symbol)
                }
            }
        } label: { Label("Plantilla", systemImage: "doc.richtext") }
        Menu {
            ForEach(PaperTint.allCases) { tint in
                Button { store.setTint(page.id, tint) } label: {
                    Label(tint.label, systemImage: tint == page.tint ? "checkmark" : "circle.fill")
                }
            }
        } label: { Label("Color del papel", systemImage: "paintpalette") }
        Button {
            if let id = store.duplicatePage(page.id) { onOpen(id) }
        } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
        Button { store.movePage(page.id, by: -1) } label: { Label("Mover antes", systemImage: "arrow.left") }
        Button { store.movePage(page.id, by: 1) } label: { Label("Mover después", systemImage: "arrow.right") }
        if store.pages.count > 1 {
            Divider()
            Button(role: .destructive) { store.deletePage(page.id) } label: {
                Label("Eliminar hoja", systemImage: "trash")
            }
        }
    }
}

/// Todas las hojas en miniatura, como la vista de páginas de GoodNotes.
struct PagesOverview: View {
    @ObservedObject var store: NotebookStore
    var onOpen: (UUID) -> Void
    var onRename: (NotebookPage) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 22)], spacing: 26) {
                ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                    Button { onOpen(page.id) } label: {
                        VStack(spacing: 8) {
                            PageThumbnail(page: page, store: store, revision: store.revision)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                            Text("\(index + 1) · \(page.title)")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(page.paper.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { PageMenu(page: page, store: store, onRename: onRename, onOpen: onOpen) }
                }
                Menu {
                    ForEach(PaperStyle.allCases) { paper in
                        Button {
                            if let id = store.addPage(paper) { onOpen(id) }
                        } label: { Label(paper.label, systemImage: paper.symbol) }
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .aspectRatio(Notebook.pageSize.width / Notebook.pageSize.height, contentMode: .fit)
                        .overlay(Label("Nueva hoja", systemImage: "plus").font(.callout.weight(.semibold)))
                }
            }
            .padding(24)
        }
    }
}

/// Miniatura de una hoja (papel, imágenes y tinta).
struct PageThumbnail: View {
    let page: NotebookPage
    let store: NotebookStore?
    var revision: Int = 0
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Color(page.tint.color))
                    .aspectRatio(Notebook.pageSize.width / Notebook.pageSize.height, contentMode: .fit)
            }
        }
        .task(id: "\(page.id)-\(revision)-\(page.drawing.count)-\(page.paper.rawValue)-\(page.tint.rawValue)") {
            image = NotebookExporter.render(page, store: store, scale: 0.3)
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
