import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var stampsText: Binding<String> {
        Binding(
            get: { store.settings.stamps.joined(separator: " ") },
            set: { newValue in
                let list = newValue.split(separator: " ").map(String.init).filter { !$0.isEmpty }
                store.settings.stamps = list.isEmpty ? AppSettings().stamps : list
                if !store.settings.stamps.contains(store.settings.currentStamp) {
                    store.settings.currentStamp = store.settings.stamps[0]
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                presetsSection
                speedSection
                pencilSection
                paletteSection
                stampsSection
            }
            .navigationTitle("Preferencias")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .confirmationDialog("¿Eliminar el perfil «\(store.settings.activeProfile.name)»?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    let idx = store.settings.activeIndex
                    store.settings.profiles.remove(at: idx)
                    store.settings.activeProfileID = store.settings.profiles.first?.id
                }
            }
        }
    }

    // MARK: - Secciones

    private var profileSection: some View {
        Section {
            Picker("Perfil activo", selection: Binding(
                get: { store.settings.activeProfile.id },
                set: { store.settings.activeProfileID = $0 }
            )) {
                ForEach(store.settings.profiles) { Text($0.name).tag($0.id) }
            }
            TextField("Nombre del perfil", text: $store.settings.activeProfileName)

            Menu {
                ForEach(PresetProfile.builtIn, id: \.name) { template in
                    Button(template.name) { addProfile(template) }
                }
                Divider()
                Button("Copia del perfil actual") {
                    var copy = store.settings.activeProfile
                    copy.id = UUID()
                    copy.name += " (copia)"
                    copy.presets = copy.presets.map { var p = $0; p.id = UUID(); return p }
                    addProfile(copy)
                }
            } label: {
                Label("Añadir perfil", systemImage: "plus.square.on.square")
            }

            if store.settings.profiles.count > 1 {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Eliminar este perfil", systemImage: "trash")
                }
            }
        } header: {
            Text("Perfiles de color")
        } footer: {
            Text("Un perfil por tipo de libro: «Cirugía» para Schwartz/Sabiston, «Anatomía quirúrgica» para atlas, «Clínico» para el resto. Se cambia rápido con el botón 🎨 de la barra superior.")
        }
    }

    private var presetsSection: some View {
        Section {
            ForEach($store.settings.presets) { $preset in
                NavigationLink {
                    PresetEditor(preset: $preset)
                } label: {
                    PresetRow(preset: preset)
                }
            }
            .onMove { store.settings.presets.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { offsets in
                if store.settings.presets.count - offsets.count >= 1 {
                    store.settings.presets.remove(atOffsets: offsets)
                }
            }

            Button {
                let hex = MarkPreset.swatches[store.settings.presets.count % MarkPreset.swatches.count]
                store.settings.presets.append(MarkPreset(name: "Nuevo marcador", hex: hex, style: .highlight))
            } label: {
                Label("Añadir marcador", systemImage: "plus.circle")
            }
        } header: {
            Text("Marcadores de «\(store.settings.activeProfile.name)»")
        } footer: {
            Text("Color + estilo + significado. El orden es su lugar en la paleta y su tecla 1–9. Pulsa «Editar» para reordenar: pon arriba los que más usas.")
        }
    }

    private var speedSection: some View {
        Section {
            Toggle("Mantener pulsado = color temporal", isOn: $store.settings.springLoaded)
            Toggle("Volver al marcador tras flecha, círculo, sello o comentario", isOn: $store.settings.autoReturn)
            Toggle("Toque con 2 dedos = deshacer (3 = rehacer)", isOn: $store.settings.twoFingerUndo)
        } header: {
            Text("Velocidad")
        } footer: {
            Text("Mantén pulsado un color con el pulgar izquierdo mientras marcas con el Pencil: al soltarlo vuelves al color anterior, sin tocar nada más.")
        }
    }

    private var pencilSection: some View {
        Section {
            Picker("Doble toque", selection: $store.settings.doubleTap) {
                ForEach(PencilAction.allCases) { Text($0.label).tag($0) }
            }
            Picker("Apretar (Pencil Pro)", selection: $store.settings.squeeze) {
                ForEach(PencilAction.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Anotar también con el dedo", isOn: $store.settings.fingerDrawing)
        } header: {
            Text("Apple Pencil")
        } footer: {
            Text("Por defecto solo el Pencil anota y el dedo navega (la palma se ignora). Si activas «anotar con el dedo», desplázate con dos dedos.")
        }
    }

    private var paletteSection: some View {
        Section {
            Picker("Lado de la paleta", selection: $store.settings.paletteOnLeft) {
                Text("Izquierda").tag(true)
                Text("Derecha").tag(false)
            }
            .pickerStyle(.segmented)

            Picker("Tamaño de botones", selection: $store.settings.buttonSize) {
                ForEach(ButtonSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
                Text("Opacidad del resaltador: \(Int(store.settings.highlightOpacity * 100)) %")
                Slider(value: $store.settings.highlightOpacity, in: 0.2...0.8)
            }
            VStack(alignment: .leading) {
                Text("Grosor de lápiz, flechas y círculos: \(store.settings.penWidth, specifier: "%.1f") pt")
                Slider(value: $store.settings.penWidth, in: 0.5...6, step: 0.5)
            }
        } header: {
            Text("Paleta y trazos")
        } footer: {
            Text("«Compacto» cabe mejor en el iPad mini en horizontal; «Grande» es más cómodo para el pulgar.")
        }
    }

    private var stampsSection: some View {
        Section {
            TextField("Sellos separados por espacios", text: stampsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Sellos")
        } footer: {
            Text("Q = pregunta para Anki · Dx · Tx · Cx = complicación · Qx = quirúrgico · ⭐ = página clave · ❓ = duda. Mantén pulsado el botón de sello en la paleta para elegir otro.")
        }
    }

    private func addProfile(_ profile: PresetProfile) {
        var p = profile
        p.id = UUID()
        store.settings.profiles.append(p)
        store.settings.activeProfileID = p.id
    }
}

struct PresetRow: View {
    let preset: MarkPreset

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(preset.color))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: preset.style.symbol).font(.caption.bold()).foregroundStyle(.black.opacity(0.7)))
            VStack(alignment: .leading) {
                Text(preset.name)
                Text(preset.style.label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PresetEditor: View {
    @Binding var preset: MarkPreset

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(preset.color) },
            set: { preset.hex = UIColor($0).hexString }
        )
    }

    var body: some View {
        Form {
            Section("Significado") {
                TextField("Ej. Pregunta de examen", text: $preset.name)
            }
            Section("Color") {
                ColorPicker("Color personalizado", selection: colorBinding, supportsOpacity: false)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(MarkPreset.swatches, id: \.self) { hex in
                        Circle()
                            .fill(Color(UIColor(hex: hex)))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: preset.hex == hex ? 3 : 0))
                            .onTapGesture { preset.hex = hex }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Estilo") {
                Picker("Estilo", selection: $preset.style) {
                    ForEach(MarkStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle(preset.name)
    }
}
