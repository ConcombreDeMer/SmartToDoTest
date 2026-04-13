import SwiftUI

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isSaving = false

    let onSave: (String) async -> Bool

    init(initialTitle: String, onSave: @escaping (String) async -> Bool) {
        _title = State(initialValue: initialTitle)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task title", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let didSave = await onSave(title)
                            isSaving = false

                            if didSave {
                                dismiss()
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}
