import SwiftUI

/// Identidad visual de la app: un índigo sobrio como acento, coherente en día y noche.
enum Theme {
    static let accent = Color(red: 0.30, green: 0.36, blue: 0.86)
    static let sepia = Color(red: 0.98, green: 0.92, blue: 0.80)
}

/// Tono de la página del PDF:
/// - Noche: fondo oscuro y letras claras; los colores de tus marcas conservan su tono
///   (se invierte la luminosidad y se gira el color 180° para que el amarillo siga siendo amarillo).
/// - Sepia: papel cálido que cansa menos la vista en sesiones largas.
struct PageToneModifier: ViewModifier {
    let tone: PageTone

    func body(content: Content) -> some View {
        switch tone {
        case .night:
            content
                .colorInvert()
                .hueRotation(.degrees(180))
                .brightness(0.04)
        case .sepia:
            content
                .overlay(Theme.sepia.blendMode(.multiply).allowsHitTesting(false))
        case .day, .auto:
            content
        }
    }
}

/// Leyenda: qué significa cada color del patrón activo y qué hace la app con él.
struct ColorLegendView: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(store.settings.presets.enumerated()), id: \.element.id) { index, preset in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack(alignment: .topTrailing) {
                                PresetSwatch(preset: preset, size: 38)
                                if index < 9 {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .offset(x: 10, y: -6)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).font(.headline)
                                if !preset.detail.isEmpty {
                                    Text(preset.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 6) {
                                    Label(preset.style.label, systemImage: preset.style.symbol)
                                    Text("·")
                                    Label(preset.action.destination, systemImage: preset.action.symbol)
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(preset.color.darker(0.35)))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(store.settings.activeProfile.name)
                } footer: {
                    Text("Cada color es una acción de repaso, no un tema: así subrayar te obliga a recordar después. Los temas (Dx, Tx, Cx…) van en etiquetas. Doble toque del Pencil = el mismo color pasa a subrayar. Teclas 1–9 = elegir color.")
                }
            }
            .navigationTitle("Qué significa cada color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }
}
