import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var newTag = ""
    @State private var showNewTag = false
    @ObservedObject private var sync = SyncFolder.shared
    @State private var pickFolder = false
    @State private var confirmDisconnect = false
    @State private var showLegend = false

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
                syncSection
                appearanceSection
                patternSection
                presetsSection
                tagsSection
                dockSection
                pencilSection
                speedSection
                readingSection
                stampsSection
            }
            .navigationTitle("Preferencias")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .confirmationDialog("¿Eliminar el patrón «\(store.settings.activeProfile.name)»?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    store.settings.profiles.remove(at: store.settings.activeIndex)
                    store.settings.activeProfileID = store.settings.profiles.first?.id
                }
            }
            .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { sync.connect(url) }
            }
            .confirmationDialog("¿Dejar de sincronizar?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Dejar de sincronizar", role: .destructive) { sync.disconnect() }
            } message: {
                Text("Se guarda una copia de los cuadernos en este iPad y los cambios dejan de compartirse. La carpeta de iCloud Drive no se borra.")
            }
            .sheet(isPresented: $showLegend) {
                ColorLegendView().environmentObject(store)
            }
            .alert("Nueva etiqueta", isPresented: $showNewTag) {
                TextField("Ej. Pediatría", text: $newTag)
                Button("Añadir") {
                    let tag = SettingsStore.sanitizeTag(newTag)
                    if !tag.isEmpty, !store.settings.tags.contains(tag) { store.settings.tags.append(tag) }
                    newTag = ""
                }
                Button("Cancelar", role: .cancel) { newTag = "" }
            }
        }
    }

    // MARK: - Sincronización

    private var syncSection: some View {
        Section {
            SyncStatusBanner()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            Button {
                pickFolder = true
            } label: {
                Label(sync.isConnected ? "Cambiar carpeta…" : "Elegir carpeta en iCloud Drive…",
                      systemImage: "folder.badge.plus")
            }
            if sync.isConnected {
                Button {
                    sync.checkNow()
                } label: {
                    HStack {
                        Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if let last = sync.lastCheck {
                            Text(last, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button(role: .destructive) { confirmDisconnect = true } label: {
                    Label("Dejar de sincronizar", systemImage: "icloud.slash")
                }
            }
            if let error = sync.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            NavigationLink {
                NotebookLibraryView()
            } label: {
                Label("Mis cuadernos", systemImage: "books.vertical")
            }
        } header: {
            Text("Sincronización")
        } footer: {
            Text("Crea en Archivos una carpeta «iCloud Drive › ResiPDF» y elígela aquí en cada iPad. Se comparten los cuadernos, los colores, los patrones y las etiquetas. Guarda los PDF en esa misma carpeta: las marcas van dentro del PDF y también se sincronizan.")
        }
    }

    // MARK: - Apariencia

    private var appearanceSection: some View {
        Section {
            Picker("App", selection: $store.settings.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Página del PDF", selection: $store.settings.pageTone) {
                ForEach(PageTone.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
        } header: {
            Text("Apariencia")
        } footer: {
            Text("Noche: fondo oscuro y letras claras, tus colores mantienen su tono. Sepia: papel cálido para sesiones largas. Automático: noche cuando el iPad está en modo oscuro. En el cuaderno, elige «Noche» como color del papel.")
        }
    }

    // MARK: - Patrón de colores

    private var patternSection: some View {
        Section {
            Picker("Patrón activo", selection: Binding(
                get: { store.settings.activeProfile.id },
                set: { store.settings.activeProfileID = $0 }
            )) {
                ForEach(store.settings.profiles) { Text($0.name).tag($0.id) }
            }
            TextField("Nombre del patrón", text: $store.settings.activeProfileName)
            Button { showLegend = true } label: {
                Label("Qué significa cada color", systemImage: "info.circle")
            }

            Menu {
                Section("Plantillas") {
                    ForEach(PresetProfile.builtIn, id: \.name) { template in
                        Button(template.name) { addProfile(template) }
                    }
                }
                Button("Copia del patrón actual") {
                    var copy = store.settings.activeProfile
                    copy.name += " (copia)"
                    copy.presets = copy.presets.map { var p = $0; p.id = UUID(); return p }
                    addProfile(copy)
                }
                Button("Patrón vacío") {
                    addProfile(PresetProfile(name: "Mi patrón", presets: [
                        MarkPreset(name: "Idea principal", hex: "#FFC94D", style: .highlight, action: .summary),
                    ]))
                }
            } label: {
                Label("Crear patrón", systemImage: "plus.square.on.square")
            }

            if store.settings.profiles.count > 1 {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Eliminar este patrón", systemImage: "trash")
                }
            }
        } header: {
            Text("Patrón de colores")
        } footer: {
            Text("Un patrón es tu sistema de colores. El recomendado, «Residente de cirugía», usa 7 colores, cada uno ligado a lo que harás al repasar; el tema clínico va en etiquetas. Cámbialo rápido con 🎨 en la barra superior.")
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
                store.settings.presets.append(MarkPreset(name: "Nuevo color", hex: hex, style: .highlight))
            } label: {
                Label("Añadir color", systemImage: "plus.circle")
            }
        } header: {
            Text("Colores de «\(store.settings.activeProfile.name)»")
        } footer: {
            Text("El orden es su lugar en el dock y su tecla 1–9. Pulsa «Editar» para reordenar y pon primero los que más usas. Menos colores = decisiones más rápidas.")
        }
    }

    // MARK: - Etiquetas

    private var tagsSection: some View {
        Section {
            ForEach(store.settings.tags, id: \.self) { tag in
                Label(tag, systemImage: "tag")
            }
            .onDelete { store.settings.tags.remove(atOffsets: $0) }
            .onMove { store.settings.tags.move(fromOffsets: $0, toOffset: $1) }

            Button {
                showNewTag = true
            } label: {
                Label("Añadir etiqueta", systemImage: "plus.circle")
            }
            Toggle("Mostrar etiquetas al terminar de marcar", isOn: $store.settings.autoTagBar)
        } header: {
            Text("Etiquetas clínicas")
        } footer: {
            Text("Al levantar el Pencil aparece una barra con tus etiquetas: toca «Cx» o «Tx» y sigue leyendo. Luego filtra en Marcas, por ejemplo: todas las preguntas sobre complicaciones.")
        }
    }

    // MARK: - Dock y Pencil

    private var dockSection: some View {
        Section {
            Picker("Posición", selection: $store.settings.dockEdge) {
                ForEach(DockEdge.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Tamaño", selection: $store.settings.buttonSize) {
                ForEach(ButtonSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Dock de colores")
        } footer: {
            Text("También puedes arrastrarlo desde su asa: se pega al borde más cercano. Para usarlo con la mano izquierda, ponlo a la izquierda.")
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
            Toggle("Ver el color bajo la punta (hover)", isOn: $store.settings.pencilHover)
            Toggle("Anotar también con el dedo", isOn: $store.settings.fingerDrawing)
        } header: {
            Text("Apple Pencil")
        } footer: {
            Text("Solo el Pencil anota y el dedo navega (la palma se ignora). El hover funciona en iPad con chip M2 o posterior y en iPad mini con Pencil Pro.")
        }
    }

    private var speedSection: some View {
        Section {
            Toggle("Dedo quieto sobre la página = rueda de colores", isOn: $store.settings.fingerRing)
            Toggle("Tras marcar, cambiar el color con un toque", isOn: $store.settings.quickRecolor)
            Toggle("Mantener pulsado = color temporal", isOn: $store.settings.springLoaded)
            Toggle("Volver al color tras flecha, sello o comentario", isOn: $store.settings.autoReturn)
            Toggle("Dos dedos = deshacer (tres = rehacer)", isOn: $store.settings.twoFingerUndo)
        } header: {
            Text("Velocidad")
        } footer: {
            Text("Con una mano: deja el dedo quieto en la página, desliza hasta el color y suelta. Con dos manos: el Pencil en la derecha y el pulgar izquierdo en el dock (ponlo a la izquierda y tamaño «Pulgar»). Si te equivocas de color, toca el correcto en la barra que aparece junto a la marca.")
        }
    }

    private var readingSection: some View {
        Section {
            Picker("Modo", selection: $store.settings.readingMode) {
                ForEach(ReadingMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                Text("Intensidad del resaltador: \(Int(store.settings.highlightOpacity * 100)) %")
                Slider(value: $store.settings.highlightOpacity, in: 0.2...0.8)
            }
            VStack(alignment: .leading) {
                Text("Grosor de lápiz y flechas: \(store.settings.penWidth, specifier: "%.1f") pt")
                Slider(value: $store.settings.penWidth, in: 0.5...6, step: 0.5)
            }
        } header: {
            Text("Lectura y trazos")
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
            Text("Q = pregunta propia · ❗ = importante · ⭐ = página favorita · ❓ = duda para el adjunto · ✔︎ = repasada.")
        }
    }

    private func addProfile(_ profile: PresetProfile) {
        var p = profile
        p.id = UUID()
        store.settings.profiles.append(p)
        store.settings.activeProfileID = p.id
    }
}

// MARK: - Filas y editor de un color

struct PresetSwatch: View {
    let preset: MarkPreset
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            if preset.style == .highlight {
                Circle().fill(Color(preset.color))
            } else {
                Circle().fill(Color(.systemBackground))
                Circle().strokeBorder(Color(preset.color), lineWidth: 3.5)
                Image(systemName: preset.style.symbol)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(Color(preset.color))
            }
        }
        .frame(width: size, height: size)
    }
}

struct PresetRow: View {
    let preset: MarkPreset

    var body: some View {
        HStack(spacing: 12) {
            PresetSwatch(preset: preset)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                HStack(spacing: 4) {
                    Image(systemName: preset.action.symbol)
                    Text("\(preset.style.label) · \(preset.action.destination)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Section {
                preview
            }
            Section {
                TextField("Ej. Pregunta de examen", text: $preset.name)
                TextField("Qué va con este color (ej. cifras, dosis, criterios)", text: $preset.detail, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Significado")
            }
            Section {
                Picker("Acción", selection: $preset.action) {
                    ForEach(ReviewAction.allCases) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(action.label, systemImage: action.symbol)
                            Text(action.destination).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(action)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Qué harás con ello al repasar")
            } footer: {
                Text("Esto decide a qué lista o anexo va cada marca.")
            }
            Section("Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(MarkPreset.swatches, id: \.self) { hex in
                        Circle()
                            .fill(Color(UIColor(hex: hex)))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Color.primary, lineWidth: preset.hex == hex ? 3 : 0).padding(-3))
                            .onTapGesture { preset.hex = hex }
                    }
                }
                .padding(.vertical, 6)
                ColorPicker("Otro color", selection: colorBinding, supportsOpacity: false)
            }
            Section("Estilo") {
                Picker("Estilo", selection: $preset.style) {
                    ForEach(MarkStyle.allCases) { style in
                        Label(style.label, systemImage: style.symbol).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(preset.name)
    }

    /// Vista previa de cómo queda en el texto.
    private var preview: some View {
        let color = Color(preset.color)
        return HStack(spacing: 0) {
            Text("La apendicitis es ")
            Text("la urgencia quirúrgica más frecuente")
                .padding(.horizontal, 2)
                .background(preset.style == .highlight ? color.opacity(0.45) : Color.clear)
                .overlay(alignment: preset.style == .strikeOut ? .center : .bottom) {
                    if preset.style == .underline || preset.style == .strikeOut {
                        Rectangle().fill(color).frame(height: 2)
                    }
                }
                .overlay {
                    if preset.style == .box {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1.5)
                    }
                }
        }
        .font(.system(.body, design: .serif))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.vertical, 6)
    }
}
