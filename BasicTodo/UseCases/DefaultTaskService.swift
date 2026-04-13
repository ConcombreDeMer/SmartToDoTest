import Foundation

struct DefaultTaskService: TaskManaging {
    private let repository: TaskRepository

    init(repository: TaskRepository) {
        self.repository = repository
    }

    func loadTasks() async throws -> [TaskItem] {
        let tasks = try await repository.fetchTasks()
        return sortTasks(tasks)
    }

    func addTask(title: String) async throws -> [TaskItem] {
        var tasks = try await repository.fetchTasks()
        tasks.append(TaskItem(title: normalize(title)))
        return try await persist(tasks)
    }

    func updateTask(id: UUID, title: String) async throws -> [TaskItem] {
        var tasks = try await repository.fetchTasks()

        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return sortTasks(tasks)
        }

        tasks[index] = tasks[index].updatingTitle(normalize(title))
        return try await persist(tasks)
    }

    func toggleTask(id: UUID) async throws -> [TaskItem] {
        var tasks = try await repository.fetchTasks()

        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return sortTasks(tasks)
        }

        tasks[index] = tasks[index].toggledCompletion()
        return try await persist(tasks)
    }

    func deleteTask(id: UUID) async throws -> [TaskItem] {
        let tasks = try await repository.fetchTasks().filter { $0.id != id }
        return try await persist(tasks)
    }
}

private extension DefaultTaskService {
    func persist(_ tasks: [TaskItem]) async throws -> [TaskItem] {
        let sortedTasks = sortTasks(tasks)
        try await repository.saveTasks(sortedTasks)
        return sortedTasks
    }

    func sortTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    func normalize(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
