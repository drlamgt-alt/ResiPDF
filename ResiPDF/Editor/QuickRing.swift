import SwiftUI

/// Rueda de colores que aparece JUNTO AL PENCIL (al apretar el Pencil Pro o con
/// doble toque si así lo configuras). Elegir color sin mover la vista del texto.
struct QuickRing: View {
    let center: CGPoint
    @ObservedObject var editor: EditorState
    @EnvironmentObject private var store: SettingsStore

    private let button: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let presets = store.settings.presets
            let radius: CGFloat = presets.count > 8 ? 88 : 76
            let c = CGPoint(
                x: min(max(center.x, radius + button), geo.size.width - radius - button),
                y: min(max(center.y, radius + button), geo.size.height - radius - button)
            )

            ZStack {
                // Toque fuera = cerrar
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }

                Circle()
                    .fill(.regularMaterial)
                    .frame(width: radius * 2 + button + 8, height: radius * 2 + button + 8)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                    .position(c)

                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    let angle = Double(index) / Double(max(presets.count, 1)) * 2 * .pi - .pi / 2
                    let selected = editor.tool == .preset(preset.id)
                    Button {
                        editor.select(.preset(preset.id), store: store)
                        close()
                    } label: {
                        ZStack {
                            Circle().fill(preset.style == .highlight ? Color(preset.color) : Color(.systemBackground))
                            Circle().strokeBorder(Color(preset.color), lineWidth: preset.style == .highlight ? 0 : 3)
                            Image(systemName: preset.style.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(preset.style == .highlight ? Color.black.opacity(0.7) : Color(preset.color))
                        }
                        .frame(width: button, height: button)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                    .position(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
                }

                // Centro: borrador
                Button {
                    editor.select(.eraser, store: store)
                    close()
                } label: {
                    Image(systemName: "eraser")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: button, height: button)
                        .background(Circle().fill(editor.tool == .eraser ? Color.accentColor : Color(.tertiarySystemFill)))
                        .foregroundStyle(editor.tool == .eraser ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrador")
                .position(c)
            }
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func close() {
        withAnimation(.spring(response: 0.25)) { editor.quickPalettePoint = nil }
    }
}
