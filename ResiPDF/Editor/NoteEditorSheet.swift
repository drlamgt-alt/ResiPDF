import SwiftUI

/// Hoja para escribir un comentario (se puede escribir a mano con Scribble).
struct NoteEditorSheet: View {
    let request: NoteRequest
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(request: NoteRequest) {
        self.request = request
        _text = State(initialValue: request.initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding()
                .navigationTitle(request.isEditing ? "Editar comentario" : "Nuevo comentario")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") {
                            request.onSave(text)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        if request.isEditing {
                            Button("Eliminar comentario", role: .destructive) {
                                request.onDelete()
                                dismiss()
                            }
                        }
                    }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
