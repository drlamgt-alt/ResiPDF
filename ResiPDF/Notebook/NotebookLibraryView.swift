import SwiftUI
import PencilKit

/// Un cuaderno guardado (para la lista «Mis cuadernos»).
struct NotebookSummary: Identifiable {
    let id: URL                 // carpeta del cuaderno
    let notebook: Notebook
    let thumbnail: UIImage?

    var title: String { notebook.bookTitle }
    var pageCount: Int { notebook.pages.count }
    var figureCount: Int { notebook.figures.count }
}

enum NotebookLibrary {
    /// Lee todos los cuadernos de la carpeta (en segundo plano: iCloud puede tener que bajarlos).
    static func scan(_ root: URL) -> [NotebookSummary] {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])) ?? []
        return folders.compactMap { folder -> NotebookSummary? in
            guard folder.hasDirectoryPath,
                  let data = CoordinatedFile.read(folder.appendingPathComponent("cuaderno.json")),
                  let nb = try? JSONDecoder().decode(Notebook.self, from: data) else { return nil }
            return NotebookSummary(id: folder, notebook: nb, thumbnail: thumbnail(of: nb.pages.first))
        }
        .sorted { $0.notebook.modified > $1.notebook.modified }
    }

    /// Miniatura de la primera hoja: papel + tinta.
    static func thumbnail(of page: NotebookPage?) -> UIImage? {
        guard let page else { return nil }
        let size = Notebook.pageSize
        let rect = CGRect(origin: .zero, size: size)
        let scale: CGFloat = 0.25
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let ink: UIImage? = {
            guard let drawing = try? PKDrawing(data: page.drawing) else { return nil }
            var image: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: rect, scale: scale)
            }
            return image
        }()
        return UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale),
                                       format: format).image { ctx in
            ctx.cgContext.scaleBy(x: scale, y: scale)
            PaperRenderer.draw(page.paper, title: page.title, in: rect, context: ctx.cgContext)
            ink?.draw(in: rect)
        }
    }
}

/// «Mis cuadernos»: todos los cuadernos, de todos los libros, en la carpeta de sincronización.
struct NotebookLibraryView: View {
    @ObservedObject private var sync = SyncFolder.shared
    @State private var items: [NotebookSummary] = []
    @State private var loading = true
    @State private var toDelete: NotebookSummary?
    @State private var exportURL: URL?
    @State private var exportError = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SyncStatusBanner()
                if loading && items.isEmpty {
                    ProgressView("Buscando cuadernos…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Aún no hay cuadernos",
                        systemImage: "book.pages",
                        description: Text("Abre un libro y toca 📖 «Cuaderno» en la barra superior. Cada libro tiene el suyo.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                        ForEach(items) { item in
                            card(item)
                        }
                    }
                }
                Text("Un cuaderno se abre junto a su libro: abre el PDF y toca 📖. Para que aparezcan en tus otros iPads, guarda también los PDF en iCloud Drive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mis cuadernos")
        .refreshable { await reload(checkSync: true) }
        .task(id: sync.pulse) { await reload(checkSync: false) }
        .confirmationDialog(
            "¿Eliminar el cuaderno de «\(toDelete?.title ?? "")»?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Eliminar cuaderno", role: .destructive) {
                if let item = toDelete { delete(item) }
            }
        } message: {
            Text(sync.isConnected
                 ? "Se borran sus hojas y figuras en todos tus dispositivos. No se puede deshacer. El PDF y sus marcas no se tocan."
                 : "Se borran sus hojas y figuras. No se puede deshacer. El PDF y sus marcas no se tocan.")
        }
        .sheet(item: Binding(get: { exportURL.map(ExportedFile.init) }, set: { exportURL = $0?.url })) { file in
            ShareSheet(items: [file.url])
        }
        .alert("No se pudo exportar el cuaderno", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func card(_ item: NotebookSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumb = item.thumbnail {
                    Image(uiImage: thumb).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Color.white)
                        .aspectRatio(Notebook.pageSize.width / Notebook.pageSize.height, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button { export(item) } label: { Label("Exportar a PDF", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { toDelete = item } label: { Label("Eliminar cuaderno", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.45))
                        .padding(6)
                }
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 10) {
                Label("\(item.pageCount)", systemImage: "doc.text")
                if item.figureCount > 0 { Label("\(item.figureCount)", systemImage: "photo") }
                Spacer(minLength: 0)
                Text(item.notebook.modified, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func reload(checkSync: Bool) async {
        if checkSync { sync.checkNow() }
        loading = true
        let root = sync.notebooksRoot
        let found = await Task.detached(priority: .userInitiated) { NotebookLibrary.scan(root) }.value
        items = found
        loading = false
    }

    private func export(_ item: NotebookSummary) {
        let store = NotebookStore(bookName: item.title)
        do {
            exportURL = try NotebookExporter.export(store: store, items: [])
        } catch {
            exportError = true
        }
    }

    private func delete(_ item: NotebookSummary) {
        try? CoordinatedFile.delete(item.id)
        items.removeAll { $0.id == item.id }
        toDelete = nil
    }
}

private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Dónde se guardan los cuadernos y si se sincronizan.
struct SyncStatusBanner: View {
    @ObservedObject private var sync = SyncFolder.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sync.isConnected ? (sync.isICloud ? "checkmark.icloud.fill" : "folder.fill") : "ipad")
                .font(.title2)
                .foregroundStyle(sync.isConnected ? Color.accentColor : Color.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(sync.isConnected ? "Sincronizando en \(sync.displayName)" : "Solo en este iPad")
                    .font(.subheadline.weight(.semibold))
                Text(sync.isConnected
                     ? "Cuadernos, colores, patrones y etiquetas se comparten con tus otros dispositivos."
                     : "Elige una carpeta de iCloud Drive en Preferencias › Sincronización para tenerlos en todos tus iPads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
