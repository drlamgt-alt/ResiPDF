import SwiftUI
import PDFKit

private struct SearchHit: Identifiable {
    let id = UUID()
    let selection: PDFSelection
    let pageIndex: Int
    let context: String
}

/// Buscar texto en el libro o saltar a una página escribiendo su número.
struct SearchView: View {
    let pdf: PDFDocument
    let onSelect: (PDFSelection) -> Void
    let onPage: (PDFPage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searched = false
    @State private var searching = false

    private var pageNumber: Int? {
        guard let n = Int(query.trimmingCharacters(in: .whitespaces)), n >= 1, n <= pdf.pageCount else { return nil }
        return n
    }

    var body: some View {
        NavigationStack {
            List {
                if let n = pageNumber, let page = pdf.page(at: n - 1) {
                    Button {
                        onPage(page)
                        dismiss()
                    } label: {
                        Label("Ir a la página \(n) de \(pdf.pageCount)", systemImage: "arrow.right.doc.on.clipboard")
                    }
                }
                if searching {
                    HStack { ProgressView(); Text("Buscando…") }
                }
                ForEach(hits) { hit in
                    Button {
                        onSelect(hit.selection)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("p. \(hit.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                            Text(hit.context).foregroundStyle(.primary).lineLimit(3)
                        }
                    }
                }
                if searched && hits.isEmpty && !searching && pageNumber == nil {
                    Text("Sin resultados").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Texto o número de página")
            .onSubmit(of: .search) { runSearch() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, pageNumber == nil else { return }
        searching = true
        hits = []
        // Se cede un ciclo para que aparezca el indicador antes de buscar.
        DispatchQueue.main.async {
            let found = pdf.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
            hits = found.prefix(300).compactMap { sel in
                guard let page = sel.pages.first else { return nil }
                let ctx = (sel.copy() as? PDFSelection) ?? sel
                ctx.extendForLineBoundaries()
                let text = (ctx.string ?? q).replacingOccurrences(of: "\n", with: " ")
                return SearchHit(selection: sel, pageIndex: pdf.index(for: page), context: text)
            }
            searching = false
            searched = true
        }
    }
}
