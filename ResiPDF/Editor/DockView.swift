import SwiftUI

private struct DockSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension DockEdge {
    var edgeSet: Edge.Set {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

/// Dock de colores flotante, estilo cápsula:
/// - Se arrastra desde el asa y se pega al borde más cercano (abajo, arriba, izquierda o derecha).
/// - Toque = elegir color. Mantener pulsado = color temporal (al soltar vuelve al anterior).
/// - Etiquetas para la última marca, herramientas secundarias en un menú, borrador y deshacer.
struct DockView: View {
    @ObservedObject var editor: EditorState
    @EnvironmentObject private var store: SettingsStore
    var undoManager: UndoManager?
    var onSize: (CGSize) -> Void = { _ in }

    @State private var drag: CGSize = .zero
    @State private var measured: CGSize = .zero
    @State private var pressedID: UUID?
    @State private var pressStart: Date?
    @State private var springBack: Tool?

    static let margin: CGFloat = 12
    private let spacing: CGFloat = 10

    private var edge: DockEdge { store.settings.dockEdge }

    var body: some View {
        GeometryReader { geo in
            let size = dotSize(for: geo.size)
            let center = position(in: geo.size)
            dock(size: size, geo: geo, center: center)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: DockSizeKey.self, value: g.size)
                    }
                )
                .position(x: center.x + drag.width, y: center.y + drag.height)
        }
        .onPreferenceChange(DockSizeKey.self) { s in
            measured = s
            onSize(s)
        }
    }

    // MARK: - Geometría

    /// Tamaño de los círculos: el preferido, o menor si no caben todos.
    private func dotSize(for area: CGSize) -> CGFloat {
        let preferred = store.settings.buttonSize.points
        let items = CGFloat(store.settings.presets.count + 8)
        let length = (edge.isVertical ? area.height : area.width) - 2 * Self.margin - 40
        let fit = (length - spacing * (items - 1)) / items - 6
        return max(24, min(preferred, fit))
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        hi < lo ? (lo + hi) / 2 : min(max(v, lo), hi)
    }

    private func position(in area: CGSize) -> CGPoint {
        let w = max(measured.width, 44)
        let h = max(measured.height, 44)
        let m = Self.margin
        let f = CGFloat(store.settings.dockOffset)
        switch edge {
        case .bottom:
            return CGPoint(x: clamp(area.width * f, w / 2 + m, area.width - w / 2 - m), y: area.height - h / 2 - m)
        case .top:
            return CGPoint(x: clamp(area.width * f, w / 2 + m, area.width - w / 2 - m), y: h / 2 + m)
        case .left:
            return CGPoint(x: w / 2 + m, y: clamp(area.height * f, h / 2 + m, area.height - h / 2 - m))
        case .right:
            return CGPoint(x: area.width - w / 2 - m, y: clamp(area.height * f, h / 2 + m, area.height - h / 2 - m))
        }
    }

    // MARK: - Dock

    private func dock(size: CGFloat, geo: GeometryProxy, center: CGPoint) -> some View {
        let layout = edge.isVertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout {
            grip(geo: geo, center: center)
            if editor.dockCollapsed {
                collapsedDot(size: size)
            } else {
                ForEach(Array(store.settings.presets.enumerated()), id: \.element.id) { index, preset in
                    presetDot(preset, index: index, size: size)
                }
                divider
                styleToggle(size: size)
                tagMenu(size: size)
                toolsMenu(size: size)
                toolButton(.eraser, symbol: "eraser", label: "Borrador", size: size)
                iconButton("arrow.uturn.backward", label: "Deshacer", size: size) {
                    if undoManager?.canUndo == true { undoManager?.undo() }
                }
                iconButton("arrow.uturn.forward", label: "Rehacer", size: size) {
                    if undoManager?.canRedo == true { undoManager?.redo() }
                }
                iconButton(collapseSymbol, label: "Plegar", size: size) {
                    withAnimation(.spring(response: 0.3)) { editor.dockCollapsed = true }
                }
            }
        }
        .padding(.horizontal, edge.isVertical ? 7 : 12)
        .padding(.vertical, edge.isVertical ? 12 : 7)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .overlay(alignment: edge == .top ? .bottom : .top) {
            if !edge.isVertical, !editor.dockCollapsed, let preset = activePreset {
                activeLabel(preset)
                    .offset(y: edge == .top ? 36 : -36)
                    .allowsHitTesting(false)
            }
        }
    }

    private var activePreset: MarkPreset? {
        if case .preset(let id) = editor.tool { return store.preset(id: id) }
        return nil
    }

    private func activeLabel(_ preset: MarkPreset) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(preset.color)).frame(width: 8, height: 8)
            if editor.styleSwap {
                Image(systemName: editor.effectiveStyle(of: preset).symbol).font(.caption2.weight(.bold))
            }
            Text(preset.name).font(.caption.weight(.semibold))
            Text("· \(preset.action.destination)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .fixedSize()
    }

    private var collapseSymbol: String {
        switch edge {
        case .bottom: return "chevron.down"
        case .top: return "chevron.up"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: edge.isVertical ? 22 : 0.5, height: edge.isVertical ? 0.5 : 22)
    }

    private func grip(geo: GeometryProxy, center: CGPoint) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: edge.isVertical ? 20 : 5, height: edge.isVertical ? 5 : 20)
            .frame(width: edge.isVertical ? 34 : 18, height: edge.isVertical ? 18 : 34)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let x = center.x + value.translation.width
                        let y = center.y + value.translation.height
                        let w = max(geo.size.width, 1)
                        let h = max(geo.size.height, 1)
                        let distances: [(DockEdge, CGFloat)] = [(.left, x), (.right, w - x), (.top, y), (.bottom, h - y)]
                        let newEdge = distances.min { $0.1 < $1.1 }?.0 ?? .bottom
                        var s = store.settings
                        s.dockEdge = newEdge
                        let fraction = newEdge.isVertical ? y / h : x / w
                        s.dockOffset = Double(min(max(fraction, 0.05), 0.95))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.settings = s
                            drag = .zero
                        }
                    }
            )
            .accessibilityLabel("Mover barra de colores")
    }

    private func collapsedDot(size: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { editor.dockCollapsed = false }
        } label: {
            Circle()
                .fill(Color(UIColor(hex: editor.currentHex)))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2).padding(-4))
                .frame(width: size + 8, height: size + 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mostrar colores")
    }

    // MARK: - Colores

    private func presetDot(_ preset: MarkPreset, index: Int, size: CGFloat) -> some View {
        let selected = editor.tool == .preset(preset.id)
        let color = Color(preset.color)
        let diameter = selected ? size + 4 : size - 2
        let style = editor.effectiveStyle(of: preset)
        return ZStack {
            if style == .highlight {
                Circle().fill(color)
            } else {
                Circle().fill(Color(.systemBackground))
                Circle().strokeBorder(color, lineWidth: 4)
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(selected ? 0.85 : 0), lineWidth: 2.5)
                .padding(-4)
        )
        .frame(width: size + 6, height: size + 6)
        .scaleEffect(pressedID == preset.id ? 0.88 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
        .animation(.easeOut(duration: 0.12), value: pressedID)
        .contentShape(Circle())
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
        .accessibilityLabel("\(preset.name), \(preset.style.label)")
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

    // MARK: - Herramientas

    private func roundIcon(_ symbol: String, selected: Bool, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: size + 2, height: size + 2)
            .background(Circle().fill(selected ? Color.accentColor : Color.clear))
            .frame(width: size + 6, height: size + 6)
            .contentShape(Circle())
    }

    private func toolButton(_ tool: Tool, symbol: String, label: String, size: CGFloat) -> some View {
        Button {
            editor.select(editor.tool == tool ? editor.previousTool : tool, store: store)
        } label: {
            roundIcon(symbol, selected: editor.tool == tool, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func iconButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            roundIcon(symbol, selected: false, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Resaltar ↔ Subrayar con los mismos colores (igual que el doble toque del Pencil).
    private func styleToggle(size: CGFloat) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) { editor.toggleStyle(store: store) }
        } label: {
            roundIcon(editor.styleSwap ? "underline" : "highlighter", selected: editor.styleSwap, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(editor.styleSwap ? "Volver a resaltar" : "Subrayar con los mismos colores")
    }

    private func tagMenu(size: CGFloat) -> some View {
        Menu {
            if let target = editor.lastTagTarget {
                Section("Etiquetar la última marca") {
                    ForEach(store.settings.tags, id: \.self) { tag in
                        Button {
                            var tags = target.tags
                            if let i = tags.firstIndex(of: tag) { tags.remove(at: i) } else { tags.append(tag) }
                            target.apply(tags)
                        } label: {
                            Label(tag, systemImage: target.tags.contains(tag) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            } else {
                Text("Marca un texto y luego elige sus etiquetas")
            }
        } label: {
            roundIcon("tag", selected: false, size: size)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Etiquetas")
    }

    private var secondaryToolSymbol: String? {
        switch editor.tool {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .circle: return "circle"
        case .note: return "text.bubble"
        case .stamp: return "seal"
        case .mask: return "rectangle.fill.on.rectangle.fill"
        case .navigate: return "hand.point.up.left"
        case .crop: return "crop"
        default: return nil
        }
    }

    private func toolsMenu(size: CGFloat) -> some View {
        Menu {
            Section("Herramientas") {
                toolItem(.pen, "Lápiz libre", "pencil.tip")
                toolItem(.arrow, "Flecha", "arrow.up.right")
                toolItem(.circle, "Círculo", "circle")
                toolItem(.note, "Comentario", "text.bubble")
                toolItem(.mask, "Tapa de autoevaluación", "rectangle.fill.on.rectangle.fill")
                toolItem(.crop, "Recortar figura al cuaderno", "crop")
                toolItem(.navigate, "Navegar (el Pencil no anota)", "hand.point.up.left")
            }
            Section("Sellos") {
                ForEach(store.settings.stamps, id: \.self) { stamp in
                    Button {
                        store.settings.currentStamp = stamp
                        editor.select(.stamp, store: store)
                    } label: {
                        Label("Sello \(stamp)", systemImage: "seal")
                    }
                }
            }
        } label: {
            roundIcon(secondaryToolSymbol ?? "ellipsis", selected: secondaryToolSymbol != nil, size: size)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Más herramientas")
    }

    private func toolItem(_ tool: Tool, _ title: String, _ symbol: String) -> some View {
        Button {
            editor.select(tool, store: store)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}
