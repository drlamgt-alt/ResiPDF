import SwiftUI
import PDFKit

enum SidebarTab: String, CaseIterable, Identifiable {
    case outline = "Índice"
    case pages = "Páginas"
    case marks = "Marcas"
    case favorites = "Favoritas"
    var id: String { rawValue }
}

/// Barra lateral de navegación: índice del libro, miniaturas, marcas y páginas favoritas.
struct SidebarView: View {
    let pdf: PDFDocument
    @ObservedObject var editor: EditorState
    @ObservedObject var store: SettingsStore
    @State private var tab: SidebarTab

    init(pdf: PDFDocument, editor: EditorState, store: SettingsStore, initialTab: SidebarTab = .outline) {
        self.pdf = pdf
        self.editor = editor
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $tab) {
                ForEach(SidebarTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            switch tab {
            case .outline:
                OutlineList(pdf: pdf, editor: editor)
            case .pages:
                ThumbnailGrid(pdf: pdf, editor: editor)
            case .marks:
                AnnotationBrowser(pdf: pdf, store: store, refreshToken: editor.annotationsVersion) { page in
                    editor.go(to: page)
                }
            case .favorites:
                FavoritesList(pdf: pdf, editor: editor)
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Índice

private struct OutlineNode: Identifiable {
    let id = UUID()
    let title: String
    let page: PDFPage?
    let pageIndex: Int?
    var children: [OutlineNode]?
}

private struct OutlineList: View {
    let pdf: PDFDocument
    @ObservedObject var editor: EditorState
    @State private var nodes: [OutlineNode] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded && nodes.isEmpty {
                ContentUnavailableView("Este PDF no tiene índice",
                                       systemImage: "list.bullet.indent",
                                       description: Text("Usa «Páginas» o la búsqueda para moverte por el libro."))
            } else {
                List(nodes, children: \.children) { node in
                    Button {
                        if let page = node.page { editor.go(to: page) }
                    } label: {
                        HStack {
                            Text(node.title)
                                .font(.subheadline)
                                .foregroundStyle(isCurrent(node) ? Color.accentColor : Color.primary)
                                .lineLimit(2)
                            Spacer()
                            if let i = node.pageIndex {
                                Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .task {
            if let root = pdf.outlineRoot { nodes = Self.build(root, pdf: pdf) }
            loaded = true
        }
    }

    private func isCurrent(_ node: OutlineNode) -> Bool {
        node.pageIndex == editor.currentPageIndex
    }

    private static func build(_ outline: PDFOutline, pdf: PDFDocument) -> [OutlineNode] {
        (0..<outline.numberOfChildren).compactMap { i in
            guard let child = outline.child(at: i) else { return nil }
            let kids = build(child, pdf: pdf)
            let page = child.destination?.page
            return OutlineNode(title: child.label ?? "—",
                               page: page,
                               pageIndex: page.map { pdf.index(for: $0) },
                               children: kids.isEmpty ? nil : kids)
        }
    }
}

// MARK: - Miniaturas

private struct ThumbnailGrid: View {
    let pdf: PDFDocument
    @ObservedObject var editor: EditorState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 14)], spacing: 16) {
                    ForEach(0..<pdf.pageCount, id: \.self) { i in
                        ThumbnailCell(pdf: pdf, index: i, isCurrent: i == editor.currentPageIndex)
                            .id(i)
                            .onTapGesture {
                                if let page = pdf.page(at: i) { editor.go(to: page) }
                            }
                    }
                }
                .padding(14)
            }
            .onAppear { proxy.scrollTo(editor.currentPageIndex, anchor: .center) }
        }
    }
}

private struct ThumbnailCell: View {
    let pdf: PDFDocument
    let index: Int
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(Color(.tertiarySystemFill)).aspectRatio(0.77, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? Color.accentColor : Color(.separator), lineWidth: isCurrent ? 3 : 0.5)
            )
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            Text("\(index + 1)")
                .font(.caption2.monospacedDigit().weight(isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
        }
        .task {
            image = pdf.page(at: index)?.thumbnail(of: CGSize(width: 200, height: 260), for: .cropBox)
        }
    }
}

// MARK: - Favoritas

private struct FavoritePage: Identifiable {
    let index: Int
    let title: String
    var id: Int { index }
}

private struct FavoritesList: View {
    let pdf: PDFDocument
    @ObservedObject var editor: EditorState
    @State private var pages: [FavoritePage] = []

    var body: some View {
        VStack(spacing: 0) {
            Button {
                editor.toggleFavorite?()
            } label: {
                Label(editor.currentPageIsFavorite ? "Quitar esta página" : "Añadir esta página",
                      systemImage: editor.currentPageIsFavorite ? "star.slash" : "star")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(12)

            if pages.isEmpty {
                ContentUnavailableView("Sin páginas favoritas",
                                       systemImage: "star",
                                       description: Text("Marca con ⭐ algoritmos, tablas y páginas clave para volver rápido."))
            } else {
                List(pages) { item in
                    Button {
                        if let page = pdf.page(at: item.index) { editor.go(to: page) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Página \(item.index + 1)").font(.subheadline.weight(.semibold))
                                Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task(id: editor.annotationsVersion) { pages = collect() }
    }

    private func collect() -> [FavoritePage] {
        var out: [FavoritePage] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let isFavorite = page.annotations.contains {
                AnnotationController.isStamp($0) && $0.contents == AnnotationController.favoriteSymbol
            }
            guard isFavorite else { continue }
            let line = (page.string ?? "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.count > 3 } ?? ""
            out.append(FavoritePage(index: i, title: String(line.prefix(80))))
        }
        return out
    }
}
