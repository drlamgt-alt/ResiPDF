import SwiftUI

/// Guarda el cuaderno de un libro en «En mi iPad › ResiPDF › Cuadernos › <libro>».
/// - `cuaderno.json`: hojas, trazos e imágenes colocadas.
/// - `figuras/`: figuras recortadas del PDF (PNG).
final class NotebookStore: ObservableObject {
    let bookName: String
    let folder: URL

    /// Cambia cuando cambia la estructura (hojas, imágenes, figuras).
    /// Los trazos del Pencil NO lo cambian, para no redibujar la vista en cada trazo.
    @Published private(set) var revision = 0
    private(set) var notebook: Notebook?
    /// Última hoja abierta (para insertar figuras en ella).
    var currentPageID: UUID?
    /// Sección que debe abrirse la próxima vez que se muestre el cuaderno.
    var requestedSection: NotebookSection?

    private var saveWork: DispatchWorkItem?
    private let imageCache = NSCache<NSString, UIImage>()

    static var rootFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Cuadernos", isDirectory: true)
    }

    init(bookName: String) {
        self.bookName = bookName
        folder = Self.rootFolder.appendingPathComponent(Self.safeName(bookName), isDirectory: true)
        load()
    }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sin título" : String(cleaned.prefix(120))
    }

    private var fileURL: URL { folder.appendingPathComponent("cuaderno.json") }
    private var figuresFolder: URL { folder.appendingPathComponent("figuras", isDirectory: true) }

    var exists: Bool { notebook != nil }
    var pages: [NotebookPage] { notebook?.pages ?? [] }
    var figures: [NotebookFigure] { notebook?.figures ?? [] }

    // MARK: - Pregunta al abrir un libro

    private var declineKey: String { "ResiPDF.notebook.noPreguntar." + bookName }

    var promptDeclined: Bool {
        get { UserDefaults.standard.bool(forKey: declineKey) }
        set { UserDefaults.standard.set(newValue, forKey: declineKey) }
    }

    // MARK: - Carga y guardado

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let nb = try? JSONDecoder().decode(Notebook.self, from: data) else {
            notebook = nil
            return
        }
        notebook = nb
        revision += 1
    }

    func create() {
        guard notebook == nil else { return }
        notebook = Notebook(bookTitle: bookName, pages: [NotebookPage(title: "Notas", paper: .cornell)])
        revision += 1
        saveNow()
    }

    /// Borra el cuaderno del disco (solo lo usa el modo de demostración).
    func resetForDemo() {
        try? FileManager.default.removeItem(at: folder)
        notebook = nil
        revision += 1
    }

    private func mutate(structural: Bool = true, _ change: (inout Notebook) -> Void) {
        guard var nb = notebook else { return }
        change(&nb)
        nb.modified = Date()
        notebook = nb
        if structural { revision += 1 }
        scheduleSave()
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        guard let nb = notebook else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(nb)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("No se pudo guardar el cuaderno: \(error)")
        }
    }

    // MARK: - Hojas

    func page(_ id: UUID) -> NotebookPage? {
        notebook?.pages.first { $0.id == id }
    }

    @discardableResult
    func addPage(_ paper: PaperStyle, after id: UUID? = nil) -> UUID? {
        var newID: UUID?
        mutate { nb in
            let page = NotebookPage(title: "Hoja \(nb.pages.count + 1)", paper: paper)
            newID = page.id
            if let id, let i = nb.pages.firstIndex(where: { $0.id == id }) {
                nb.pages.insert(page, at: i + 1)
            } else {
                nb.pages.append(page)
            }
        }
        return newID
    }

    func deletePage(_ id: UUID) {
        mutate { nb in
            guard nb.pages.count > 1 else { return }
            nb.pages.removeAll { $0.id == id }
        }
    }

    func renamePage(_ id: UUID, to title: String) {
        mutate { nb in
            if let i = nb.pages.firstIndex(where: { $0.id == id }) { nb.pages[i].title = title }
        }
    }

    func setPaper(_ id: UUID, _ paper: PaperStyle) {
        mutate { nb in
            if let i = nb.pages.firstIndex(where: { $0.id == id }) { nb.pages[i].paper = paper }
        }
    }

    func updateDrawing(_ id: UUID, _ data: Data) {
        mutate(structural: false) { nb in
            if let i = nb.pages.firstIndex(where: { $0.id == id }) { nb.pages[i].drawing = data }
        }
    }

    // MARK: - Imágenes en hojas

    func updateImage(_ image: NotebookImage, on pageID: UUID) {
        mutate(structural: false) { nb in
            guard let p = nb.pages.firstIndex(where: { $0.id == pageID }),
                  let i = nb.pages[p].images.firstIndex(where: { $0.id == image.id }) else { return }
            nb.pages[p].images[i] = image
        }
    }

    func removeImage(_ imageID: UUID, from pageID: UUID) {
        mutate { nb in
            guard let p = nb.pages.firstIndex(where: { $0.id == pageID }) else { return }
            nb.pages[p].images.removeAll { $0.id == imageID }
        }
    }

    /// Coloca una figura en una hoja (en la zona de notas si es Cornell).
    func insert(_ figure: NotebookFigure, into pageID: UUID) {
        guard let img = image(named: figure.file) else { return }
        mutate { nb in
            guard let p = nb.pages.firstIndex(where: { $0.id == pageID }) else { return }
            let layout = PaperLayout(size: Notebook.pageSize)
            let left = nb.pages[p].paper == .cornell ? layout.cueWidth + 24 : 60
            let maxWidth = min(Notebook.pageSize.width - left - 40, 420)
            let aspect = img.size.height / max(img.size.width, 1)
            let width = min(maxWidth, img.size.width)
            let offset = CGFloat(nb.pages[p].images.count % 6) * 36
            let frame = CGRect(x: left + offset, y: layout.header + 24 + offset,
                               width: width, height: width * aspect)
            nb.pages[p].images.append(NotebookImage(file: figure.file,
                                                    x: frame.minX, y: frame.minY,
                                                    width: frame.width, height: frame.height,
                                                    sourcePage: figure.sourcePage))
        }
    }

    // MARK: - Figuras (Anexo C)

    /// Guarda una figura recortada del PDF. Crea el cuaderno si aún no existe.
    @discardableResult
    func addFigure(_ image: UIImage, sourcePage: Int) -> NotebookFigure? {
        if notebook == nil { create() }
        guard let data = image.pngData() else { return nil }
        let file = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: figuresFolder, withIntermediateDirectories: true)
            try data.write(to: figuresFolder.appendingPathComponent(file), options: .atomic)
        } catch {
            print("No se pudo guardar la figura: \(error)")
            return nil
        }
        imageCache.setObject(image, forKey: file as NSString)
        let figure = NotebookFigure(file: file, sourcePage: sourcePage,
                                    caption: "Figura de la p. \(sourcePage + 1)")
        mutate { $0.figures.append(figure) }
        return figure
    }

    func deleteFigure(_ id: UUID) {
        mutate { nb in nb.figures.removeAll { $0.id == id } }
    }

    func image(named file: String) -> UIImage? {
        if let cached = imageCache.object(forKey: file as NSString) { return cached }
        guard let img = UIImage(contentsOfFile: figuresFolder.appendingPathComponent(file).path) else { return nil }
        imageCache.setObject(img, forKey: file as NSString)
        return img
    }
}
