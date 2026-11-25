import SwiftUI

/// Barra que aparece junto a la marca recién hecha para etiquetarla
/// (Dx, Tx, Cx…) sin soltar el Pencil. Se cierra sola a los pocos segundos.
struct TagBar: View {
    let request: TagRequest
    let tags: [String]
    var onClose: () -> Void

    @State private var selected: [String]

    init(request: TagRequest, tags: [String], onClose: @escaping () -> Void) {
        self.request = request
        self.tags = tags
        self.onClose = onClose
        _selected = State(initialValue: request.tags)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(tags, id: \.self) { tag in
                let on = selected.contains(tag)
                Button {
                    if let i = selected.firstIndex(of: tag) { selected.remove(at: i) } else { selected.append(tag) }
                    request.apply(selected)
                } label: {
                    Text(tag)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar etiquetas")
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .fixedSize()
    }
}
