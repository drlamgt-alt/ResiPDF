import UIKit
import PDFKit

/// Organiza las marcas del libro en una guía de estudio por temas.
/// El tema sale del índice del PDF (capítulos y secciones). Si el PDF no tiene índice,
/// se agrupa por bloques de 10 páginas.
enum StudyGuide {
    struct Section: Identifiable {
        let topic: String
        let marks: [StudyMark]
        var id: String { topic }
        var firstPage: Int { marks.map(\.pageIndex).min() ?? 0 }
        var lastPage: Int { marks.map(\.pageIndex).max() ?? 0 }
        func count(_ action: ReviewAction) -> Int { marks.filter { $0.action == action }.count }
    }

    /// Orden de cada tipo de marca dentro de un tema: primero lo que se pregunta.
    static let actionOrder: [ReviewAction] = [.question, .memorize, .summary, .connect, .doubt]

    static func build(items: [AnnotationItem], pdf: PDFDocument) -> [StudyMark] {
        let outline = topics(of: pdf)
        var seen: [String: Int] = [:]
        return items.map { item in
            // Id estable (para recordar qué repasaste) y único aunque repitas el mismo texto.
            let base = "\(item.pageIndex)|\(item.group)|\(item.text.prefix(80))"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return StudyMark(
                id: n == 0 ? base : "\(base)#\(n)",
                pageIndex: item.pageIndex,
                action: item.action,
                group: item.group,
                kind: item.kind,
                text: item.text,
                hex: item.color.withAlphaComponent(1).hexString,
                tags: item.tags,
                topic: topic(for: item.pageIndex, in: outline)
            )
        }
    }

    /// Entradas del índice (dos niveles) ordenadas por página.
    static func topics(of pdf: PDFDocument) -> [(page: Int, title: String)] {
        var result: [(Int, String)] = []
        func walk(_ item: PDFOutline, depth: Int, parent: String?) {
            for i in 0..<item.numberOfChildren {
                guard let child = item.child(at: i) else { continue }
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty, let page = child.destination?.page {
                    let full = depth == 0 || parent == nil ? title : "\(parent!) › \(title)"
                    result.append((pdf.index(for: page), full))
                }
                if depth < 1 { walk(child, depth: depth + 1, parent: title.isEmpty ? parent : title) }
            }
        }
        if let root = pdf.outlineRoot { walk(root, depth: 0, parent: nil) }
        return result.sorted { $0.0 < $1.0 }
    }

    static func topic(for page: Int, in outline: [(page: Int, title: String)]) -> String {
        if let entry = outline.last(where: { $0.page <= page }) { return entry.title }
        if let first = outline.first, page < first.page { return "Introducción" }
        let start = (page / 10) * 10
        return "Páginas \(start + 1)–\(start + 10)"
    }

    /// Agrupa por tema, en el orden del libro; dentro de cada tema, preguntas primero.
    static func sections(_ marks: [StudyMark]) -> [Section] {
        var order: [String] = []
        var byTopic: [String: [StudyMark]] = [:]
        for m in marks.sorted(by: { $0.pageIndex < $1.pageIndex }) {
            if byTopic[m.topic] == nil { order.append(m.topic) }
            byTopic[m.topic, default: []].append(m)
        }
        return order.map { topic in
            let list = byTopic[topic] ?? []
            let sorted = list.sorted { a, b in
                let ia = a.action.flatMap { actionOrder.firstIndex(of: $0) } ?? 99
                let ib = b.action.flatMap { actionOrder.firstIndex(of: $0) } ?? 99
                return ia == ib ? a.pageIndex < b.pageIndex : ia < ib
            }
            return Section(topic: topic, marks: sorted)
        }
    }

    static func label(for action: ReviewAction?) -> String {
        switch action {
        case .question?: return "Pregunta"
        case .memorize?: return "Memorizar"
        case .summary?: return "Idea"
        case .connect?: return "Conectar"
        case .doubt?: return "Duda"
        default: return "Marca"
        }
    }

    static func symbol(for action: ReviewAction?) -> String {
        switch action {
        case .question?: return "questionmark.circle.fill"
        case .memorize?: return "brain.head.profile"
        case .summary?: return "lightbulb.fill"
        case .connect?: return "link"
        case .doubt?: return "exclamationmark.bubble.fill"
        default: return "highlighter"
        }
    }
}
