import SwiftUI

/// Guía de estudio: tus marcas del libro ordenadas por tema (capítulo / sección del índice),
/// con las preguntas primero y una casilla para ir marcando lo que ya repasaste.
struct StudyGuideView: View {
    @ObservedObject var store: NotebookStore
    var standalone: Bool
    var onGo: (Int) -> Void

    enum Filter: String, CaseIterable, Identifiable {
        case all, questions, pending
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Todo"
            case .questions: return "Solo preguntas"
            case .pending: return "Por repasar"
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var collapsed: Set<String> = []

    private var marks: [StudyMark] {
        let reviewed = store.reviewed
        return store.studyMarks.filter { m in
            switch filter {
            case .all: return true
            case .questions: return m.action == .question
            case .pending: return !reviewed.contains(m.id)
            }
        }
    }

    var body: some View {
        let sections = StudyGuide.sections(marks)
        let total = store.studyMarks.count
        let done = store.studyMarks.filter { store.reviewed.contains($0.id) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GUÍA DE ESTUDIO")
                        .font(.caption.weight(.bold))
                        .kerning(1)
                        .foregroundStyle(.secondary)
                    Text(store.bookName)
                        .font(.title2.weight(.bold))
                    Text("Se arma sola con lo que marcas en el libro, ordenada por temas del índice. Primero las preguntas de examen. Marca ✓ lo que ya repasaste.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if total > 0 {
                    progress(done: done, total: total)
                    Picker("Mostrar", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if sections.isEmpty {
                    emptyState(total: total)
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { n, section in
                        topicCard(section, number: n + 1)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func progress(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Repasado: \(done) de \(total)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(Double(done) / Double(max(total, 1)) * 100)) %")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(.green)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func emptyState(total: Int) -> some View {
        if total == 0 {
            ContentUnavailableView {
                Label("Aún no hay temas", systemImage: "list.star")
            } description: {
                Text(standalone
                     ? "Abre el libro y marca con tus colores: las preguntas, lo que hay que memorizar y las ideas aparecerán aquí ordenadas por tema."
                     : "Marca el libro con tus colores (por ejemplo, morado = pregunta de examen) y aparecerán aquí ordenadas por tema.")
            }
        } else {
            Text("¡Nada pendiente con este filtro! 🎉")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        }
    }

    private func topicCard(_ section: StudyGuide.Section, number: Int) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(number)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.topic)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 10) {
                            Text(section.firstPage == section.lastPage
                                 ? "p. \(section.firstPage + 1)"
                                 : "pp. \(section.firstPage + 1)–\(section.lastPage + 1)")
                            ForEach(StudyGuide.actionOrder, id: \.self) { action in
                                let c = section.count(action)
                                if c > 0 {
                                    Label("\(c)", systemImage: StudyGuide.symbol(for: action))
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Divider()
                ForEach(section.marks) { mark in
                    row(mark)
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ mark: StudyMark) -> some View {
        let done = store.reviewed.contains(mark.id)
        return HStack(alignment: .top, spacing: 12) {
            Button { store.toggleReviewed(mark.id) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Marcar como pendiente" : "Marcar como repasada")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label(StudyGuide.label(for: mark.action), systemImage: StudyGuide.symbol(for: mark.action))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color(mark.color.darker()))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(mark.color).opacity(0.22)))
                    ForEach(mark.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                    Spacer(minLength: 0)
                    Button("p. \(mark.pageIndex + 1)") { onGo(mark.pageIndex) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                Text(mark.displayText)
                    .font(mark.action == .question ? .body.weight(.medium) : .body)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .strikethrough(done, color: .secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

extension UIColor {
    /// Versión más oscura (para texto sobre un fondo del mismo color).
    func darker(_ amount: CGFloat = 0.45) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: min(1, s + 0.15), brightness: b * (1 - amount), alpha: 1)
    }
}
