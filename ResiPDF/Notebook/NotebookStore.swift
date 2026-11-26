import SwiftUI
import Combine

/// Guarda el cuaderno de un libro en «<carpeta de sincronización> › Cuadernos › <libro>»
/// (o «En mi iPad › ResiPDF › Cuadernos › <libro>» si no hay carpeta elegida).
/// - `cuaderno.json`: hojas, trazos e imágenes colocadas.
/// - `figuras/`: figuras recortadas del PDF (PNG).
///
/// Si otro iPad cambia el cuaderno, se recarga solo (al volver a la app y cada 15 s).
final class NotebookStore: ObservableObject {
    let bookName: String

    /// Cambia cuando cambia la estructura (hojas, imágenes, figuras).
    /// Los trazos del Pencil NO lo cambian, para no redibujar la vista en cada trazo.
    @Published private(set) var revision = 0
    /// true mientras se descarga el cuaderno de iCloud.
    @Published private(set) var isLoading = false
    private(set) var notebook: Notebook?
    /// Sube cada vez que el cuaderno se lee del disco (p. ej. cambios de otro iPad):
    /// la hoja abierta vuelve a cargar sus trazos.
    private(set) var loadCount = 0
    /// Última hoja abierta (para insertar figuras en ella).
    var currentPageID: UUID?
    /// Sección que debe abrirse la próxima vez que se muestre el cuaderno.
    var requestedSection: NotebookSection?

    private var saveWork: DispatchWorkItem?
    private var hasUnsavedChanges = false
    /// Fecha del archivo la última vez que lo leímos o escribimos nosotros.
    private var knownFileDate: Date?
    private let imageCache = NSCache<NSString, UIImage>()
    private var pendingImages: Set<String> = []
    private var bag: Set<AnyCancellable> = []
    private let io = DispatchQueue(label: "ResiPDF.cuaderno.io", qos: .userInitiated)

    init(bookName: String) {
        self.bookName = bookName
        load()
        let sync = SyncFolder.shared
        sync.willChangeRoot.sink { [weak self] in self?.saveNow() }.store(in: &bag)
        sync.$pulse.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkForExternalChanges() }
            .store(in: &bag)
    }

    static func safeName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Sin título" : String(cleaned.prefix(120))
    }

    /// Se calcula cada vez: si eliges otra carpeta de sincronización, el cuaderno la sigue.
    var folder: URL {
        SyncFolder.shared.notebooksRoot.appendingPathComponent(Self.safeName(bookName), isDirectory: true)
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

    // MARK: - Carga

    /// Lee el cuaderno. Si ya está en el iPad, al instante; si iCloud aún lo está bajando, en segundo plano.
    func load() {
        let url = fileURL
        if CoordinatedFile.isLocal(url) {
            apply(CoordinatedFile.read(url), date: CoordinatedFile.modificationDate(url), from: url)
            return
        }
        isLoading = true
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        io.async { [weak self] in
            let data = CoordinatedFile.read(url)
            let date = CoordinatedFile.modificationDate(url)
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.apply(data, date: date, from: url)
            }
        }
    }

    private func apply(_ data: Data?, date: Date?, from url: URL) {
        guard url == fileURL else { return }   // cambió la carpeta mientras se leía
        guard let data, let nb = try? JSONDecoder().decode(Notebook.self, from: data) else {
            if notebook != nil {
                // La carpeta cambió y aquí no hay cuaderno: se guarda el actual en la nueva.
                saveNow()
            }
            return
        }
        // Nunca se reemplaza un cuaderno por una versión más antigua.
        if let current = notebook, current.modified > nb.modified {
            saveNow()
            return
        }
        notebook = nb
        knownFileDate = date
        hasUnsavedChanges = false
        imageCache.removeAllObjects()
        if let id = currentPageID, !nb.pages.contains(where: { $0.id == id }) { currentPageID = nil }
        loadCount += 1
        revision += 1
    }

    /// Si otro dispositivo guardó una versión nueva, la carga.
    func checkForExternalChanges() {
        let url = fileURL
        guard !isLoading else { return }
        let date = CoordinatedFile.modificationDate(url)
        if notebook == nil {
            if date != nil { load() }   // el cuaderno se creó en otro iPad
            return
        }
        guard let date else {
            saveNow()                   // carpeta nueva y vacía: se guarda aquí
            return
        }
        if let known = knownFileDate, date.timeIntervalSince(known) < 0.5 { return }
        if hasUnsavedChanges { saveNow() }   // gana lo último que escribiste en este iPad
        else { load() }
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
        knownFileDate = nil
        revision += 1
    }

    // MARK: - Guardado

    private func mutate(structural: Bool = true, _ change: (inout Notebook) -> Void) {
        guard var nb = notebook else { return }
        change(&nb)
        nb.modified = Date()
        notebook = nb
        hasUnsavedChanges = true
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
            let data = try JSONEncoder().encode(nb)
            try CoordinatedFile.write(data, to: fileURL)
            knownFileDate = CoordinatedFile.modificationDate(fileURL)
            hasUnsavedChanges = false
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
            try CoordinatedFile.write(data, to: figuresFolder.appendingPathComponent(file))
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

    /// Devuelve la figura si ya está en el iPad. Si iCloud aún la está bajando, devuelve nil
    /// y redibuja el cuaderno cuando llegue.
    func image(named file: String) -> UIImage? {
        if let cached = imageCache.object(forKey: file as NSString) { return cached }
        let url = figuresFolder.appendingPathComponent(file)
        if CoordinatedFile.isLocal(url) {
            guard let data = CoordinatedFile.read(url), let img = UIImage(data: data) else { return nil }
            imageCache.setObject(img, forKey: file as NSString)
            return img
        }
        guard !pendingImages.contains(file) else { return nil }
        pendingImages.insert(file)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        io.async { [weak self] in
            let img = CoordinatedFile.read(url).flatMap(UIImage.init(data:))
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingImages.remove(file)
                if let img {
                    self.imageCache.setObject(img, forKey: file as NSString)
                    self.revision += 1
                }
            }
        }
        return nil
    }
}
