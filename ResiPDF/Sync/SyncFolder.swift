import SwiftUI
import Combine

/// Carpeta compartida entre tus dispositivos (lo normal: iCloud Drive › ResiPDF).
///
/// Instalada con SideStore, la app no puede usar CloudKit ni un contenedor propio de iCloud
/// (eso exige la cuenta de desarrollador de pago). Pero sí puede leer y escribir en una carpeta
/// de iCloud Drive que elijas en Archivos: iCloud Drive la sincroniza sola con tus otros iPads.
/// Ahí se guardan los cuadernos (`Cuadernos/`) y tus colores, patrones y etiquetas (`ajustes.json`).
final class SyncFolder: ObservableObject {
    static let shared = SyncFolder()
    private static let bookmarkKey = "ResiPDF.sync.carpeta"

    /// Carpeta elegida (nil = todo se guarda solo en este iPad).
    @Published private(set) var url: URL?
    /// Cambia cada vez que conviene revisar si otro dispositivo escribió algo.
    @Published private(set) var pulse = 0
    @Published private(set) var lastCheck: Date?
    @Published var lastError: String?

    /// Antes de cambiar de carpeta, los cuadernos abiertos guardan lo pendiente.
    let willChangeRoot = PassthroughSubject<Void, Never>()

    /// Solo para las capturas: aparenta estar conectado a iCloud Drive.
    var demoLabel: String?

    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private init() {
        restore()
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.checkNow() })
        // Mientras la app está abierta, revisa cada 15 s (leer la fecha de un archivo cuesta poco).
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, self.url != nil,
                  UIApplication.shared.applicationState == .active else { return }
            self.checkNow()
        }
    }

    // MARK: - Rutas

    static var localRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var isConnected: Bool { url != nil || demoLabel != nil }
    var root: URL { url ?? Self.localRoot }
    var notebooksRoot: URL { root.appendingPathComponent("Cuadernos", isDirectory: true) }
    var settingsURL: URL? { url?.appendingPathComponent("ajustes.json") }

    var isICloud: Bool {
        if demoLabel != nil { return true }
        return url?.path.contains("Mobile Documents") == true
    }

    /// Nombre legible: «iCloud Drive › ResiPDF».
    var displayName: String {
        if let demoLabel { return demoLabel }
        guard let url else { return "En mi iPad › ResiPDF" }
        let parts = url.standardizedFileURL.pathComponents
        if let i = parts.firstIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + parts[(i + 1)...]).joined(separator: " › ")
        }
        if let i = parts.firstIndex(of: "Mobile Documents"), i + 2 < parts.count {
            // Carpeta de otra app dentro de iCloud Drive.
            return (["iCloud Drive"] + parts[(i + 2)...]).joined(separator: " › ")
        }
        return url.lastPathComponent
    }

    // MARK: - Elegir carpeta

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                      bookmarkDataIsStale: &stale) else {
            lastError = "No se encuentra la carpeta de sincronización. Vuelve a elegirla."
            return
        }
        _ = resolved.startAccessingSecurityScopedResource()
        if stale, let fresh = try? resolved.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        url = resolved
    }

    /// Conecta la carpeta elegida y copia allí los cuadernos que ya tenías en este iPad.
    func connect(_ picked: URL) {
        guard picked.startAccessingSecurityScopedResource() else {
            lastError = "ResiPDF no tiene permiso para usar esa carpeta."
            return
        }
        do {
            let data = try picked.bookmarkData()
            willChangeRoot.send()
            let localNotebooks = notebooksRoot
            if let old = url, old != picked { old.stopAccessingSecurityScopedResource() }
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            url = picked
            lastError = nil
            justConnected = true
            let copied = NotebookCopier.merge(from: localNotebooks, into: notebooksRoot)
            if copied > 0 { print("Cuadernos copiados a la carpeta: \(copied)") }
            checkNow()
        } catch {
            picked.stopAccessingSecurityScopedResource()
            lastError = "No se pudo usar esa carpeta: \(error.localizedDescription)"
        }
    }

    /// Deja de sincronizar: trae a este iPad una copia de los cuadernos y vuelve a guardar en local.
    func disconnect() {
        guard let old = url else { return }
        willChangeRoot.send()
        _ = NotebookCopier.merge(from: notebooksRoot, into: Self.localRoot.appendingPathComponent("Cuadernos"))
        old.stopAccessingSecurityScopedResource()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        url = nil
        checkNow()
    }

    /// Recién conectada: si la carpeta ya trae colores de otro iPad, se usan esos.
    private var justConnected = false

    func consumeJustConnected() -> Bool {
        defer { justConnected = false }
        return justConnected
    }

    func checkNow() {
        lastCheck = Date()
        pulse += 1
    }
}

// MARK: - Lectura y escritura coordinadas

/// En iCloud Drive hay que leer y escribir «coordinado»: así iOS descarga el archivo si aún
/// no está en el iPad y no lo pisa mientras lo está sincronizando.
enum CoordinatedFile {
    static func read(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { u in
            result = try? Data(contentsOf: u)
        }
        return result
    }

    static func write(_ data: Data, to url: URL) throws {
        var error: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { u in
            do {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: u, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let e = error ?? writeError { throw e }
    }

    static func delete(_ url: URL) throws {
        var error: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { u in
            do { try FileManager.default.removeItem(at: u) } catch { deleteError = error }
        }
        if let e = error ?? deleteError { throw e }
    }

    static func modificationDate(_ url: URL) -> Date? {
        var u = url
        u.removeAllCachedResourceValues()
        return try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// true si el archivo ya está en el iPad (o no es de iCloud): se puede leer sin esperar.
    static func isLocal(_ url: URL) -> Bool {
        var u = url
        u.removeAllCachedResourceValues()
        guard let values = try? u.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                           .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true else { return true }
        return values.ubiquitousItemDownloadingStatus == .current
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - Copiar cuadernos entre carpetas

enum NotebookCopier {
    /// Copia cada cuaderno de `source` a `destination` si allí no existe o es más antiguo.
    /// Las figuras que falten también se copian. Devuelve cuántos cuadernos copió.
    @discardableResult
    static func merge(from source: URL, into destination: URL) -> Int {
        let fm = FileManager.default
        guard source.standardizedFileURL != destination.standardizedFileURL,
              let books = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else { return 0 }
        var copied = 0
        for book in books where book.hasDirectoryPath {
            let srcJSON = book.appendingPathComponent("cuaderno.json")
            guard let srcData = CoordinatedFile.read(srcJSON),
                  let srcNB = try? JSONDecoder().decode(Notebook.self, from: srcData) else { continue }
            let dstBook = destination.appendingPathComponent(book.lastPathComponent, isDirectory: true)
            let dstJSON = dstBook.appendingPathComponent("cuaderno.json")
            if let dstData = CoordinatedFile.read(dstJSON),
               let dstNB = try? JSONDecoder().decode(Notebook.self, from: dstData),
               dstNB.modified >= srcNB.modified {
                continue
            }
            // Figuras primero, para que el cuaderno nunca apunte a imágenes que aún no existen.
            let srcFigures = book.appendingPathComponent("figuras", isDirectory: true)
            let dstFigures = dstBook.appendingPathComponent("figuras", isDirectory: true)
            for file in (try? fm.contentsOfDirectory(at: srcFigures, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? [] {
                let target = dstFigures.appendingPathComponent(file.lastPathComponent)
                if CoordinatedFile.exists(target) { continue }
                if let data = CoordinatedFile.read(file) { try? CoordinatedFile.write(data, to: target) }
            }
            if (try? CoordinatedFile.write(srcData, to: dstJSON)) != nil { copied += 1 }
        }
        return copied
    }
}
