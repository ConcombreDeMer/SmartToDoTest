import SwiftUI

struct TaskListView: View {
    @StateObject private var viewModel: TaskListViewModel
    @State private var isPresentingAI = false

    init(viewModel: TaskListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tasks.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Tasks Yet",
                        systemImage: "checklist",
                        description: Text("Add a task to get started.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(viewModel.tasks) { task in
                                TaskRowView(
                                    task: task,
                                    onToggle: {
                                        Task { await viewModel.toggleTask(task) }
                                    },
                                    onEdit: {
                                        viewModel.startEditing(task)
                                    }
                                )
                            }
                            .onDelete { offsets in
                                Task { await viewModel.deleteTasks(at: offsets) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingAI = true
                    } label: {
                        Text("AI")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black, in: Capsule())
                    }
                    .accessibilityLabel("Open task assistant")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                TaskComposerView(
                    title: $viewModel.draftTitle,
                    isDisabled: viewModel.isAddDisabled,
                    onSubmit: {
                        Task { await viewModel.addTask() }
                    }
                )
            }
        }
        .task {
            await viewModel.loadTasks()
        }
        .sheet(item: $viewModel.editingTask) { task in
            TaskEditorSheet(
                initialTitle: task.title,
                onSave: { newTitle in
                    await viewModel.saveEdition(title: newTitle)
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isPresentingAI) {
            AIChatView(viewModel: viewModel.makeAIChatViewModel())
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )
    }
}
