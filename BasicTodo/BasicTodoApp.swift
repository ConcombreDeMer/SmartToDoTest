import SwiftUI

@main
struct BasicTodoApp: App {
    private let container = AppContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            TaskListView(
                viewModel: TaskListViewModel(taskService: container.taskService)
            )
        }
    }
}
