import Foundation

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var draftTitle = ""
    @Published var editingTask: TaskItem?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let taskService: TaskManaging

    init(taskService: TaskManaging) {
        self.taskService = taskService
    }

    var isAddDisabled: Bool {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try await taskService.loadTasks()
            errorMessage = nil
        } catch {
            errorMessage = "Unable to load tasks."
        }
    }

    func addTask() async {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        do {
            tasks = try await taskService.addTask(title: title)
            draftTitle = ""
            errorMessage = nil
        } catch {
            errorMessage = "Unable to add the task."
        }
    }

    func toggleTask(_ task: TaskItem) async {
        do {
            tasks = try await taskService.toggleTask(id: task.id)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to update the task."
        }
    }

    func deleteTasks(at offsets: IndexSet) async {
        let ids = offsets.map { tasks[$0].id }

        do {
            var currentTasks = tasks

            for id in ids {
                currentTasks = try await taskService.deleteTask(id: id)
            }

            tasks = currentTasks
            errorMessage = nil
        } catch {
            errorMessage = "Unable to delete the task."
        }
    }

    func startEditing(_ task: TaskItem) {
        editingTask = task
    }

    func saveEdition(title: String) async -> Bool {
        guard let editingTask else { return false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        do {
            tasks = try await taskService.updateTask(id: editingTask.id, title: trimmedTitle)
            self.editingTask = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Unable to save the task."
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func makeAIChatViewModel() -> AIChatViewModel {
        AIChatViewModel(
            taskService: taskService,
            onTasksUpdated: { [weak self] tasks in
                self?.tasks = tasks
            }
        )
    }
}
