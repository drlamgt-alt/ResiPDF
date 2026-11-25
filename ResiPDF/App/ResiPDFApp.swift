import SwiftUI

@main
struct ResiPDFApp: App {
    @StateObject private var store = SettingsStore()

    var body: some Scene {
        // DocumentGroup abre el PDF directamente desde Archivos (iCloud Drive,
        // En mi iPad, Google Drive, etc.) y guarda los cambios en el MISMO archivo.
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            EditorView(document: file.document)
                .environmentObject(store)
        }
    }
}
