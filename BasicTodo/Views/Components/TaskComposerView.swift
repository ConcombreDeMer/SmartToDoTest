import SwiftUI

struct TaskComposerView: View {
    @Binding var title: String
    let isDisabled: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Add a new task", text: $title)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
