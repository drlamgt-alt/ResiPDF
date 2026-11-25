import SwiftUI

/// Punto de entrada: con el argumento `-demo` abre un capítulo de ejemplo ya anotado
/// (se usa para generar capturas de pantalla automáticas en GitHub).
@main
enum AppLauncher {
    static func main() {
        if CommandLine.arguments.contains("-demo") {
            DemoApp.main()
        } else {
            ResiPDFApp.main()
        }
    }
}

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
