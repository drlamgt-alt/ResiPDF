import SwiftUI

/// Barra rápida que aparece junto a la marca recién hecha, sin soltar el Pencil:
/// - Colores: ¿te equivocaste de color? Un toque y la marca cambia (no hay que borrar y repetir).
/// - Etiquetas: Dx, Tx, Cx…
/// - Papelera: borra esa marca.
/// Se cierra sola a los pocos segundos o al seguir marcando.
struct TagBar: View {
    let request: TagRequest
    let tags: [String]
    var onClose: () -> Void

    @EnvironmentObject private var store: SettingsStore
    @State private var selected: [String]
    @State private var presetID: UUID?

    init(request: TagRequest, tags: [String], onClose: @escaping () -> Void) {
        self.request = request
        self.tags = tags
        self.onClose = onClose
        _selected = State(initialValue: request.tags)
        _presetID = State(initialValue: request.presetID)
    }

    private var showColors: Bool { store.settings.quickRecolor && request.recolor != nil }
    private var showTags: Bool { store.settings.autoTagBar && !tags.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showColors {
                HStack(spacing: 8) {
                    ForEach(store.settings.presets) { preset in
                        colorButton(preset)
                    }
                    Divider().frame(height: 26)
                    if let delete = request.delete {
                        Button {
                            delete()
                            onClose()
                        } label: {
                            Image(systemName: "trash")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.red.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Borrar esta marca")
                    }
                    closeButton
                }
            }
            if showTags {
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
                    if !showColors { closeButton }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .fixedSize()
    }

    private func colorButton(_ preset: MarkPreset) -> some View {
        let isCurrent = preset.id == presetID
        let color = Color(preset.color)
        return Button {
            guard !isCurrent else { return }
            request.recolor?(preset)
            presetID = preset.id
        } label: {
            ZStack {
                if preset.style == .highlight {
                    Circle().fill(color)
                } else {
                    Circle().fill(Color(.systemBackground))
                    Circle().strokeBorder(color, lineWidth: 3)
                    Image(systemName: preset.style.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(Color.primary.opacity(isCurrent ? 0.85 : 0), lineWidth: 2).padding(-3))
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cambiar a \(preset.name)")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cerrar")
    }
}
