import SwiftUI

private struct PaletteHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Paleta flotante pensada para la MANO IZQUIERDA (o derecha):
/// - Se arrastra desde el asa ≡ y se pega al borde más cercano.
/// - Toque corto en un color = lo selecciona.
/// - MANTENER pulsado un color = se usa solo mientras lo mantienes (modo resorte)
///   y al soltar vuelve al anterior. Ideal: pulgar izquierdo sostiene, Pencil marca.
struct FloatingPalette: View {
    @ObservedObject var editor: EditorState
    @EnvironmentObject private var store: SettingsStore
    var undoManager: UndoManager?

    @State private var drag: CGSize = .zero
    @State private var collapsed = false
    @State private var paletteHeight: CGFloat = 0

    // Modo resorte
    @State private var pressedID: UUID?
    @State private var pressStart: Date?
    @State private var springBack: Tool?

    private var cell: CGFloat { store.settings.buttonSize.points }
    private let gap: CGFloat = 8

    private var columns: [GridItem] {
        [GridItem(.fixed(cell), spacing: gap), GridItem(.fixed(cell), spacing: gap)]
    }

    var body: some View {
        GeometryReader { geo in
            let width = collapsed ? cell + 16 : cell * 2 + gap + 16
            let onLeft = store.settings.paletteOnLeft
            let baseX = onLeft ? 12 + width / 2 : geo.size.width - 12 - width / 2
            let half = max(paletteHeight / 2, 40)
            let rawY = geo.size.height * CGFloat(store.settings.paletteY)
            let baseY = min(max(rawY, half + 8), max(half + 8, geo.size.height - half - 8))

            panel(geo: geo, baseX: baseX, baseY: baseY)
                .frame(width: width)
                .frame(maxHeight: max(geo.size.height - 16, 100))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: PaletteHeightKey.self, value: g.size.height)
                    }
                )
                .position(x: baseX + drag.width, y: baseY + drag.height)
        }
        .onPreferenceChange(PaletteHeightKey.self) { paletteHeight = $0 }
    }

    private func panel(geo: GeometryProxy, baseX: CGFloat, baseY: CGFloat) -> some View {
        VStack(spacing: gap) {
            HStack(spacing: 0) {
                // Asa para arrastrar la paleta
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { drag = $0.translation }
                            .onEnded { value in
                                var s = store.settings
                                let fx = baseX + value.translation.width
                                let fy = baseY + value.translation.height
                                s.paletteOnLeft = fx < geo.size.width / 2
                                s.paletteY = Double(min(max(fy / max(geo.size.height, 1), 0.05), 0.95))
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    store.settings = s
                                    drag = .zero
                                }
                            }
                    )
                    .accessibilityLabel("Mover paleta")

                if !collapsed {
                    Button {
                        withAnimation(.spring(response: 0.3)) { collapsed = true }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Plegar paleta")
                }
            }

            if collapsed {
                collapsedBody
            } else {
                ViewThatFits(in: .vertical) {
                    VStack(spacing: gap) { expandedBody }
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: gap) { expandedBody }
                    }
                }
            }
        }
        .padding(8)
    }

    // MARK: - Contenido

    private var collapsedBody: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { collapsed = false }
        } label: {
            Circle()
                .fill(Color(UIColor(hex: editor.currentHex)))
                .frame(width: cell - 6, height: cell - 6)
                .overlay(Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mostrar paleta")
    }

    @ViewBuilder
    private var expandedBody: some View {
        LazyVGrid(columns: columns, spacing: gap) {
            ForEach(Array(store.settings.presets.enumerated()), id: \.element.id) { index, preset in
                presetButton(preset, index: index)
            }
        }

        Divider()

        LazyVGrid(columns: columns, spacing: gap) {
            toolButton(.pen, symbol: "pencil.tip", label: "Lápiz", usesColor: true)
            toolButton(.arrow, symbol: "arrow.up.right", label: "Flecha", usesColor: true)
            toolButton(.circle, symbol: "circle", label: "Círculo", usesColor: true)
            toolButton(.note, symbol: "text.bubble", label: "Comentario", usesColor: true)
            stampButton
            toolButton(.mask, symbol: "rectangle.fill.on.rectangle.fill", label: "Tapa de autoevaluación", usesColor: false)
            toolButton(.eraser, symbol: "eraser", label: "Borrador", usesColor: false)
            toolButton(.navigate, symbol: "hand.point.up.left", label: "Navegar", usesColor: false)
        }

        Divider()

        HStack(spacing: gap) {
            iconButton("arrow.uturn.backward", label: "Deshacer") {
                if undoManager?.canUndo == true { undoManager?.undo() }
            }
            iconButton("arrow.uturn.forward", label: "Rehacer") {
                if undoManager?.canRedo == true { undoManager?.redo() }
            }
        }
    }

    private func presetButton(_ preset: MarkPreset, index: Int) -> some View {
        let selected = editor.tool == .preset(preset.id)
        let color = Color(preset.color)
        let isHighlight = preset.style == .highlight
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlight ? color : Color(.systemBackground))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color, lineWidth: isHighlight ? 0 : 3)
            Image(systemName: preset.style.symbol)
                .font(.system(size: cell * 0.38, weight: .semibold))
                .foregroundStyle(isHighlight ? Color.black.opacity(0.7) : color)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isHighlight ? Color.black.opacity(0.45) : color.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(4)
            }
        }
        .frame(width: cell, height: cell)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                .padding(-4)
        )
        .scaleEffect(pressedID == preset.id ? 0.92 : (selected ? 1.05 : 1))
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.12), value: pressedID)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard pressedID != preset.id else { return }
                    pressedID = preset.id
                    pressStart = Date()
                    springBack = editor.tool
                    editor.select(.preset(preset.id), store: store)
                }
                .onEnded { _ in
                    // Mantener pulsado > 0,4 s = uso temporal; al soltar vuelve al anterior.
                    if store.settings.springLoaded,
                       let start = pressStart, Date().timeIntervalSince(start) > 0.4,
                       let back = springBack, back != .preset(preset.id) {
                        editor.select(back, store: store, announce: false)
                    }
                    pressedID = nil
                    pressStart = nil
                    springBack = nil
                }
        )
        .background(shortcutButton(index: index) { editor.select(.preset(preset.id), store: store) })
        .accessibilityElement()
        .accessibilityLabel("\(preset.style.label): \(preset.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editor.select(.preset(preset.id), store: store) }
    }

    /// Botón invisible que solo aporta el atajo de teclado 1–9.
    @ViewBuilder
    private func shortcutButton(index: Int, action: @escaping () -> Void) -> some View {
        if index < 9 {
            Button("", action: action)
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var stampButton: some View {
        let selected = editor.tool == .stamp
        return Menu {
            Section("Sello (mantén pulsado para cambiar)") {
                ForEach(store.settings.stamps, id: \.self) { stamp in
                    Button(stamp) {
                        store.settings.currentStamp = stamp
                        editor.select(.stamp, store: store)
                    }
                }
            }
        } label: {
            Text(store.settings.currentStamp)
                .font(.system(size: cell * 0.34, weight: .heavy))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: cell, height: cell)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                )
        } primaryAction: {
            editor.select(.stamp, store: store)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Sello \(store.settings.currentStamp)")
    }

    private func toolButton(_ tool: Tool, symbol: String, label: String, usesColor: Bool) -> some View {
        let selected = editor.tool == tool
        return Button {
            editor.select(tool, store: store)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: cell * 0.4, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: cell, height: cell)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                )
                .overlay(alignment: .bottomTrailing) {
                    if usesColor {
                        Circle()
                            .fill(Color(UIColor(hex: editor.currentHex)))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: cell * 0.38, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: cell, height: cell)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
