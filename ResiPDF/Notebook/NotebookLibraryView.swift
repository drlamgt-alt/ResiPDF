import SwiftUI
import PencilKit

/// Un cuaderno guardado (para la biblioteca «Cuadernos»).
struct NotebookSummary: Identifiable {
    let id: URL                 // carpeta del cuaderno
    let notebook: Notebook
    let firstPage: UIImage?

    var title: String { notebook.bookTitle }
    var pageCount: Int { notebook.pages.count }
    var figureCount: Int { notebook.figures.count }
    var questionCount: Int { notebook.studyMarks.filter { $0.action == .question }.count }
    var studyCount: Int { notebook.studyMarks.count }
    var reviewedCount: Int { notebook.studyMarks.filter { notebook.reviewed.contains($0.id) }.count }
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
            return NotebookSummary(id: folder, notebook: nb, firstPage: nil)
        }
        .sorted { $0.notebook.modified > $1.notebook.modified }
    }
}

/// «Cuadernos»: todos tus cuadernos, de todos los libros, como en la biblioteca de GoodNotes.
/// Se puede abrir cada uno sin su libro (hojas, guía de estudio y anexos).
struct NotebookLibraryView: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var sync = SyncFolder.shared
    @State private var items: [NotebookSummary] = []
    @State private var loading = true
    @State private var query = ""
    @State private var sortByName = false
    @State private var toDelete: NotebookSummary?
    @State private var opened: NotebookSummary?
    @State private var exportFiles: ExportFiles?
    @State private var exportError = false

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 28)]

    private var visible: [NotebookSummary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(q) }
        return sortByName ? list.sorted { $0.title.localizedCompare($1.title) == .orderedAscending } : list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SyncStatusBanner()
                if loading && items.isEmpty {
                    ProgressView("Buscando cuadernos…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "Aún no hay cuadernos",
                        systemImage: "books.vertical",
                        description: Text("Abre un libro y toca 📖 «Cuaderno» en la barra superior. Cada libro tiene el suyo, con guía de estudio y anexos que se llenan solos.")
                    )
                    .padding(.top, 40)
                } else {
                    summaryStrip
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                        ForEach(visible) { item in
                            Button { opened = item } label: { NotebookCover(item: item) }
                                .buttonStyle(.plain)
                                .contextMenu { menu(item) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cuadernos")
        .searchable(text: $query, prompt: "Buscar cuaderno")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Ordenar", selection: $sortByName) {
                        Label("Recientes", systemImage: "clock").tag(false)
                        Label("Nombre", systemImage: "textformat").tag(true)
                    }
                } label: {
                    Label("Ordenar", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .refreshable { await reload(checkSync: true) }
        .task(id: sync.pulse) { await reload(checkSync: false) }
        .fullScreenCover(item: $opened, onDismiss: { Task { await reload(checkSync: false) } }) { item in
            NotebookReader(bookName: item.title)
                .environmentObject(settings)
        }
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
        .sheet(item: $exportFiles) { files in
            ShareSheet(items: files.urls)
        }
        .alert("No se pudo exportar el cuaderno", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Resumen de todo lo que estás estudiando.
    private var summaryStrip: some View {
        let questions = items.reduce(0) { $0 + $1.questionCount }
        let study = items.reduce(0) { $0 + $1.studyCount }
        let reviewed = items.reduce(0) { $0 + $1.reviewedCount }
        return HStack(spacing: 12) {
            stat("\(items.count)", "cuadernos", "books.vertical.fill", .blue)
            stat("\(questions)", "preguntas", "questionmark.circle.fill", .purple)
            stat(study == 0 ? "—" : "\(Int(Double(reviewed) / Double(study) * 100)) %", "repasado",
                 "checkmark.circle.fill", .green)
        }
    }

    private func stat(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.bold).monospacedDigit())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func menu(_ item: NotebookSummary) -> some View {
        Button { opened = item } label: { Label("Abrir", systemImage: "book") }
        Menu {
            ForEach(NotebookExporter.Format.allCases) { format in
                Button { export(item, format) } label: { Label(format.label, systemImage: format.symbol) }
            }
        } label: { Label("Exportar", systemImage: "square.and.arrow.up") }
        Menu {
            ForEach(Notebook.coverColors, id: \.self) { hex in
                Button { setCover(item, hex) } label: {
                    Label(hex == item.notebook.coverHex ? "Actual" : " ", systemImage: "circle.fill")
                }
                .tint(Color(UIColor(hex: hex)))
            }
        } label: { Label("Color de portada", systemImage: "paintpalette") }
        Divider()
        Button(role: .destructive) { toDelete = item } label: { Label("Eliminar cuaderno", systemImage: "trash") }
    }

    private func reload(checkSync: Bool) async {
        if checkSync { sync.checkNow() }
        loading = true
        let root = sync.notebooksRoot
        let found: [NotebookSummary] = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: NotebookLibrary.scan(root))
            }
        }
        items = found
        loading = false
    }

    private func export(_ item: NotebookSummary, _ format: NotebookExporter.Format) {
        let store = NotebookStore(bookName: item.title)
        do {
            exportFiles = ExportFiles(urls: try NotebookExporter.export(store: store, format: format))
        } catch {
            exportError = true
        }
    }

    private func setCover(_ item: NotebookSummary, _ hex: String) {
        let store = NotebookStore(bookName: item.title)
        store.setCover(hex)
        store.saveNow()
        Task { await reload(checkSync: false) }
    }

    private func delete(_ item: NotebookSummary) {
        try? CoordinatedFile.delete(item.id)
        items.removeAll { $0.id == item.id }
        toDelete = nil
    }
}

/// Portada de un cuaderno, al estilo de una libreta.
struct NotebookCover: View {
    let item: NotebookSummary

    var body: some View {
        let color = Color(UIColor(hex: item.notebook.coverHex))
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                // Lomo
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 14)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                        .environment(\.colorScheme, .light)
                    Spacer(minLength: 0)
                    if item.studyCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.reviewedCount) de \(item.studyCount) repasadas")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                            ProgressView(value: Double(item.reviewedCount), total: Double(max(item.studyCount, 1)))
                                .tint(.white)
                        }
                    }
                }
                .padding(.leading, 26)
                .padding([.top, .trailing, .bottom], 14)
            }
            .aspectRatio(0.74, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 8, x: 2, y: 5)

            HStack(spacing: 10) {
                Label("\(item.pageCount)", systemImage: "doc.text")
                if item.questionCount > 0 { Label("\(item.questionCount)", systemImage: "questionmark.circle") }
                if item.figureCount > 0 { Label("\(item.figureCount)", systemImage: "photo") }
                Spacer(minLength: 0)
                Text(item.notebook.modified, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Un cuaderno abierto sin su libro (desde «Cuadernos»).
struct NotebookReader: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: NotebookStore
    @StateObject private var editor = EditorState()

    init(bookName: String) {
        _store = StateObject(wrappedValue: NotebookStore(bookName: bookName))
    }

    var body: some View {
        NotebookView(store: store, editor: editor, settings: settings, pdf: nil,
                     fullScreen: .constant(true)) {
            store.saveNow()
            dismiss()
        }
        .overlay(alignment: .top) {
            if let text = editor.toast {
                Text(text)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: editor.toast)
    }
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
