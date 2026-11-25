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
            ringContent(in: geo.size)
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var radius: CGFloat {
        store.settings.presets.count > 8 ? 88 : 76
    }

    /// Centro de la rueda, ajustado para que no se salga de la pantalla.
    private func clampedCenter(in size: CGSize) -> CGPoint {
        let margin: CGFloat = radius + button
        let x: CGFloat = min(max(center.x, margin), size.width - margin)
        let y: CGFloat = min(max(center.y, margin), size.height - margin)
        return CGPoint(x: x, y: y)
    }

    private func position(index: Int, count: Int, around c: CGPoint) -> CGPoint {
        let fraction: Double = Double(index) / Double(max(count, 1))
        let angle: Double = fraction * 2 * Double.pi - Double.pi / 2
        let dx: CGFloat = radius * CGFloat(cos(angle))
        let dy: CGFloat = radius * CGFloat(sin(angle))
        return CGPoint(x: c.x + dx, y: c.y + dy)
    }

    private func ringContent(in size: CGSize) -> some View {
        let c = clampedCenter(in: size)
        let presets = store.settings.presets
        let diameter: CGFloat = radius * 2 + button + 8

        return ZStack {
            // Toque fuera = cerrar
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { close() }

            Circle()
                .fill(.regularMaterial)
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .position(c)

            ForEach(Array(presets.enumerated()), id: \.element.id) { item in
                RingPresetButton(
                    preset: item.element,
                    selected: editor.tool == .preset(item.element.id),
                    size: button
                ) {
                    editor.select(.preset(item.element.id), store: store)
                    close()
                }
                .position(position(index: item.offset, count: presets.count, around: c))
            }

            eraserButton.position(c)
        }
    }

    private var eraserButton: some View {
        let selected = editor.tool == .eraser
        return Button {
            editor.select(.eraser, store: store)
            close()
        } label: {
            Image(systemName: "eraser")
                .font(.system(size: 18, weight: .medium))
                .frame(width: button, height: button)
                .background(Circle().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Borrador")
    }

    private func close() {
        withAnimation(.spring(response: 0.25)) { editor.quickPalettePoint = nil }
    }
}

private struct RingPresetButton: View {
    let preset: MarkPreset
    let selected: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        let isHighlight = preset.style == .highlight
        let color = Color(preset.color)
        return Button(action: action) {
            ZStack {
                Circle().fill(isHighlight ? color : Color(.systemBackground))
                Circle().strokeBorder(color, lineWidth: isHighlight ? 0 : 3)
                Image(systemName: preset.style.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isHighlight ? Color.black.opacity(0.7) : color)
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }
}
