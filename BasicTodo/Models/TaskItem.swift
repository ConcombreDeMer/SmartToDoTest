import Foundation

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension TaskItem {
    func toggledCompletion() -> TaskItem {
        var copy = self
        copy.isCompleted.toggle()
        copy.updatedAt = .now
        return copy
    }

    func updatingTitle(_ newTitle: String) -> TaskItem {
        var copy = self
        copy.title = newTitle
        copy.updatedAt = .now
        return copy
    }
}
