import SwiftUI

/// Rueda de colores que aparece donde está tu mano:
/// - JUNTO AL PENCIL al apretar el Pencil Pro o con doble toque (si así lo configuras).
/// - BAJO EL DEDO al mantenerlo quieto sobre la página: deslízalo hasta un color y suelta.
///   Así eliges color con una sola mano o con la mano izquierda sin ir al dock.
struct QuickRing: View {
    let center: CGPoint
    @ObservedObject var editor: EditorState
    @EnvironmentObject private var store: SettingsStore

    static let button: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            ringContent(in: geo.size)
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    // MARK: - Geometría (compartida con el gesto del dedo)

    static func radius(count: Int) -> CGFloat {
        count > 8 ? 94 : 82
    }

    /// Centro de la rueda, ajustado para que no se salga de la pantalla.
    static func clampedCenter(_ center: CGPoint, in size: CGSize, count: Int) -> CGPoint {
        let margin: CGFloat = radius(count: count) + button
        let x: CGFloat = min(max(center.x, margin), max(size.width - margin, margin))
        let y: CGFloat = min(max(center.y, margin), max(size.height - margin, margin))
        return CGPoint(x: x, y: y)
    }

    static func position(index: Int, count: Int, around c: CGPoint) -> CGPoint {
        let fraction: Double = Double(index) / Double(max(count, 1))
        let angle: Double = fraction * 2 * Double.pi - Double.pi / 2
        let r = radius(count: count)
        return CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
    }

    /// Qué hay bajo el dedo: índice del color, -1 = borrador (centro), nil = nada.
    static func hit(_ p: CGPoint, center: CGPoint, in size: CGSize, count: Int) -> Int? {
        let c = clampedCenter(center, in: size, count: count)
        let fromCenter = hypot(p.x - c.x, p.y - c.y)
        if fromCenter < 28 { return nil }                     // aún sin moverse: no elige nada
        // Gana el color más cercano en ángulo, si el dedo salió del centro.
        var best: (Int, CGFloat)?
        for i in 0..<count {
            let q = position(index: i, count: count, around: c)
            let d = hypot(p.x - q.x, p.y - q.y)
            if best == nil || d < best!.1 { best = (i, d) }
        }
        guard let best, best.1 < radius(count: count) else { return nil }
        return best.0
    }

    // MARK: - Vista

    private func ringContent(in size: CGSize) -> some View {
        let presets = store.settings.presets
        let c = Self.clampedCenter(center, in: size, count: presets.count)
        let radius = Self.radius(count: presets.count)
        let diameter: CGFloat = radius * 2 + Self.button + 12
        let hovered = editor.ringPointer.flatMap { Self.hit($0, center: center, in: size, count: presets.count) }

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
                    hovered: hovered == item.offset,
                    size: Self.button
                ) {
                    editor.select(.preset(item.element.id), store: store)
                    close()
                }
                .position(Self.position(index: item.offset, count: presets.count, around: c))
            }

            centerLabel(hovered: hovered.map { presets[$0] })
                .position(c)
        }
        .animation(.spring(response: 0.2), value: hovered)
    }

    /// En el centro: el nombre del color bajo el dedo, o el borrador.
    @ViewBuilder
    private func centerLabel(hovered: MarkPreset?) -> some View {
        if let hovered {
            VStack(spacing: 2) {
                Image(systemName: hovered.action.symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(hovered.name)
                    .font(.caption2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color(hovered.color.darker(0.3)))
            .frame(width: 74, height: 74)
        } else {
            let selected = editor.tool == .eraser
            Button {
                editor.select(.eraser, store: store)
                close()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: Self.button, height: Self.button)
                    .background(Circle().fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Borrador")
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.25)) {
            editor.quickPalettePoint = nil
            editor.ringPointer = nil
        }
    }
}

private struct RingPresetButton: View {
    let preset: MarkPreset
    let selected: Bool
    let hovered: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        let isHighlight = preset.style == .highlight
        let color = Color(preset.color)
        return Button(action: action) {
            ZStack {
                Circle().fill(isHighlight ? color : Color(.systemBackground))
                Circle().strokeBorder(color, lineWidth: isHighlight ? 0 : 3.5)
                Image(systemName: preset.style.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isHighlight ? Color.black.opacity(0.7) : color)
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-4))
            .scaleEffect(hovered ? 1.25 : 1)
            .shadow(color: .black.opacity(hovered ? 0.25 : 0), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }
}
