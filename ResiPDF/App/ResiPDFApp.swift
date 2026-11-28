import SwiftUI

/// Punto de entrada: con el argumento `-demo` abre un capítulo de ejemplo ya anotado
/// (se usa para generar capturas de pantalla automáticas en GitHub).
@main
enum AppLauncher {
    static func main() {
        if CommandLine.arguments.contains("-demo") {
            DemoApp.main()
        } else if #available(iOS 18.0, *) {
            ResiPDFAppWithHome.main()
        } else {
            ResiPDFApp.main()
        }
    }
}

/// iOS 17: el inicio es el explorador de Archivos. «Cuadernos» se abre desde un libro.
struct ResiPDFApp: App {
    @StateObject private var store = SettingsStore()

    var body: some Scene {
        // DocumentGroup abre el PDF directamente desde Archivos (iCloud Drive,
        // En mi iPad, Google Drive, etc.) y guarda los cambios en el MISMO archivo.
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            EditorView(document: file.document,
                       bookName: file.fileURL?.deletingPathExtension().lastPathComponent ?? "Sin título")
                .environmentObject(store)
        }
    }
}

/// iOS 18 o posterior: pantalla de inicio propia con el botón «Mis cuadernos»,
/// para entrar a los cuadernos sin abrir un libro.
@available(iOS 18.0, *)
struct ResiPDFAppWithHome: App {
    @StateObject private var store = SettingsStore()

    var body: some Scene {
        DocumentGroup(newDocument: { PDFFileDocument() }) { file in
            EditorView(document: file.document,
                       bookName: file.fileURL?.deletingPathExtension().lastPathComponent ?? "Sin título")
                .environmentObject(store)
        }

        DocumentGroupLaunchScene("ResiPDF") {
            OpenNotebooksButton()
        } background: {
            LinearGradient(colors: [Color(red: 0.16, green: 0.30, blue: 0.62), Color(red: 0.42, green: 0.27, blue: 0.70)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }

        WindowGroup("Cuadernos", id: NotebooksWindow.id) {
            NotebooksWindow()
                .environmentObject(store)
        }
    }
}

/// Botón de la pantalla de inicio.
struct OpenNotebooksButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: NotebooksWindow.id)
        } label: {
            Label("Mis cuadernos", systemImage: "books.vertical.fill")
        }
    }
}

/// Ventana con la biblioteca de cuadernos.
struct NotebooksWindow: View {
    static let id = "cuadernos"
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        NavigationStack {
            NotebookLibraryView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cerrar") { dismissWindow(id: Self.id) }
                    }
                }
        }
    }
}
