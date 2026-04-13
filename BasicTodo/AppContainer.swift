import Foundation

struct AppContainer {
    let taskService: TaskManaging

    static func makeDefault() -> AppContainer {
        let repository = JSONTaskRepository()
        let taskService = DefaultTaskService(repository: repository)

        return AppContainer(taskService: taskService)
    }
}
