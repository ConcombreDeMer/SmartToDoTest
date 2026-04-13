import Foundation

protocol TaskRepository: Sendable {
    func fetchTasks() async throws -> [TaskItem]
    func saveTasks(_ tasks: [TaskItem]) async throws
}
