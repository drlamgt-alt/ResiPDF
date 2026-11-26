import SwiftUI

/// App de demostración: abre directamente un capítulo de ejemplo ya anotado,
/// sin pasar por el explorador de archivos. Solo se usa con el argumento `-demo`.
struct DemoApp: App {
    @StateObject private var store = SettingsStore()
    @StateObject private var document = DemoContent.makeDocument()

    init() {
        // En las capturas se muestra como si ya estuviera sincronizando con iCloud Drive.
        SyncFolder.shared.demoLabel = "iCloud Drive › ResiPDF"
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                EditorView(document: document, bookName: "Apendicitis aguda")
                    .navigationTitle("Apendicitis aguda.pdf")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(store)
        }
    }
}
