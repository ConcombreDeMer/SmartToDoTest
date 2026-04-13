import Foundation

protocol TaskManaging: Sendable {
    func loadTasks() async throws -> [TaskItem]
    func addTask(title: String) async throws -> [TaskItem]
    func updateTask(id: UUID, title: String) async throws -> [TaskItem]
    func toggleTask(id: UUID) async throws -> [TaskItem]
    func deleteTask(id: UUID) async throws -> [TaskItem]
}
