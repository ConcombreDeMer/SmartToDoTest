import Foundation
import FoundationModels

enum TaskAssistantAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var message: String? {
        switch self {
        case .available:
            return nil
        case let .unavailable(message):
            return message
        }
    }
}

struct TaskAssistantResponse: Sendable {
    let message: String
    let tasks: [TaskItem]
}

struct TaskAssistantService {
    private let actionHandler: TaskAssistantActionHandler
    private let runtimeResponse: ((String) async throws -> String)?

    init(taskService: TaskManaging) {
        let actionHandler = TaskAssistantActionHandler(taskService: taskService)
        self.actionHandler = actionHandler

        if #available(iOS 26.0, *) {
            let runtime = Runtime(actionHandler: actionHandler)
            self.runtimeResponse = { prompt in
                try await runtime.respond(to: prompt)
            }
        } else {
            self.runtimeResponse = nil
        }
    }

    func availability() -> TaskAssistantAvailability {
        if #available(iOS 26.0, *) {
            return Self.availability(for: SystemLanguageModel.default.availability)
        } else {
            return .unavailable(
                "This device is running an older OS version, so Apple’s on-device Foundation Model is unavailable. AI stays disabled and no remote fallback will be used."
            )
        }
    }

    func currentTasks() async throws -> [TaskItem] {
        try await actionHandler.currentTasks()
    }

    func respond(to input: String) async -> TaskAssistantResponse {
        let fallbackTasks = (try? await actionHandler.currentTasks()) ?? []

        guard let runtimeResponse else {
            return TaskAssistantResponse(
                message: availability().message ?? Self.unavailableMessage,
                tasks: fallbackTasks
            )
        }

        guard availability() == .available else {
            return TaskAssistantResponse(
                message: availability().message ?? Self.unavailableMessage,
                tasks: fallbackTasks
            )
        }

        do {
            let tasksBeforeResponse = try await actionHandler.currentTasks()
            let prompt = Self.makePrompt(
                userInput: input,
                tasks: tasksBeforeResponse
            )

            let message = try await runtimeResponse(prompt)
            let updatedTasks = try await actionHandler.currentTasks()

            return TaskAssistantResponse(
                message: message,
                tasks: updatedTasks
            )
        } catch {
            return TaskAssistantResponse(
                message: "I couldn’t complete that request with the on-device Apple model right now. AI remains local-only and no remote fallback was attempted.",
                tasks: fallbackTasks
            )
        }
    }
}

private extension TaskAssistantService {
    static let unavailableMessage = "The on-device Apple model is unavailable. AI stays disabled and this app will not use any remote fallback."

    @available(iOS 26.0, *)
    static func availability(for availability: SystemLanguageModel.Availability) -> TaskAssistantAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(
                "This device does not support Apple’s on-device Foundation Model. AI stays disabled and no remote fallback will be used."
            )
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(
                "Apple Intelligence is turned off in system settings, so the on-device model is unavailable. AI stays disabled and no remote fallback will be used."
            )
        case .unavailable(.modelNotReady):
            return .unavailable(
                "Apple’s on-device model is not ready yet. Finish Apple Intelligence setup and try again. No remote fallback will be used."
            )
        @unknown default:
            return .unavailable(
                "Apple’s on-device model is unavailable on this device right now. AI stays disabled and no remote fallback will be used."
            )
        }
    }

    static func makePrompt(userInput: String, tasks: [TaskItem]) -> String {
        """
        Current tasks:
        \(formattedTaskContext(tasks))

        User request:
        \(userInput)
        """
    }

    static func formattedTaskContext(_ tasks: [TaskItem]) -> String {
        guard !tasks.isEmpty else {
            return "No tasks exist yet."
        }

        return tasks
            .enumerated()
            .map { index, task in
                let state = task.isCompleted ? "done" : "pending"
                return "\(index + 1). \(task.title) [\(state)]"
            }
            .joined(separator: "\n")
    }

    @available(iOS 26.0, *)
    final class Runtime {
        private let session: LanguageModelSession

        init(actionHandler: TaskAssistantActionHandler) {
            // Local-only enforcement:
            // - This code uses only Apple's on-device SystemLanguageModel.default.
            // - If the model is unavailable, the caller fails closed and never falls back to a remote service.
            let model = SystemLanguageModel.default

            self.session = LanguageModelSession(
                model: model,
                tools: [
                    CreateTaskTool(actionHandler: actionHandler),
                    CreateMultipleTasksTool(actionHandler: actionHandler),
                    DeleteTaskTool(actionHandler: actionHandler),
                    DeleteMultipleTasksTool(actionHandler: actionHandler),
                    RenameTaskTool(actionHandler: actionHandler),
                    RenameMultipleTasksTool(actionHandler: actionHandler),
                    SetTaskCompletionTool(actionHandler: actionHandler),
                    ListTasksTool(actionHandler: actionHandler)
                ],
                instructions: Self.instructions
            )
        }

        func respond(to prompt: String) async throws -> String {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0,
                    maximumResponseTokens: 220
                )
            )

            let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "I’m not sure yet. Please try rephrasing your task request." : trimmed
        }

        private static let instructions = """
        You are a local-only task assistant for a to-do app.
        Stay focused on task management only.
        Use the provided tools for any task creation, deletion, rename, completion, or listing request.
        If the user asks to create multiple tasks in one request, prefer the batch creation tool.
        If the user asks to delete or rename multiple tasks in one request, prefer the matching batch tool.
        Never claim you changed a task unless a tool confirmed it.
        If a request is ambiguous, ask a concise follow-up question instead of guessing.
        Keep replies short and practical.
        Never suggest cloud processing, remote AI, or external services.
        """
    }
}

actor TaskAssistantActionHandler {
    private let taskService: TaskManaging

    init(taskService: TaskManaging) {
        self.taskService = taskService
    }

    func currentTasks() async throws -> [TaskItem] {
        try await taskService.loadTasks()
    }

    func createTask(title: String) async -> String {
        let trimmedTitle = normalize(title)
        guard !trimmedTitle.isEmpty else {
            return "I need a task title before I can create anything."
        }

        do {
            _ = try await taskService.addTask(title: trimmedTitle)
            return "Created \"\(trimmedTitle)\"."
        } catch {
            return "I couldn’t create that task because the local task store returned an error."
        }
    }

    func createTasks(titles: [String]) async -> String {
        let normalizedTitles = titles
            .map(normalize)
            .filter { !$0.isEmpty }

        guard !normalizedTitles.isEmpty else {
            return "I need at least one task title before I can create anything."
        }

        guard normalizedTitles.count <= 10 else {
            return "I can create up to 10 tasks per request. Please shorten the list and try again."
        }

        do {
            var createdTitles: [String] = []

            for title in normalizedTitles {
                _ = try await taskService.addTask(title: title)
                createdTitles.append(title)
            }

            if createdTitles.count == 1 {
                return "Created \"\(createdTitles[0])\"."
            }

            let lines = createdTitles.enumerated().map { index, title in
                "\(index + 1). \(title)"
            }

            return """
            Created \(createdTitles.count) tasks:
            \(lines.joined(separator: "\n"))
            """
        } catch {
            return "I couldn’t create all of those tasks because the local task store returned an error."
        }
    }

    func deleteTask(matching query: String) async -> String {
        do {
            let tasks = try await taskService.loadTasks()
            guard let task = resolveSingleTask(for: query, in: tasks) else {
                let matches = resolveMatches(for: query, in: tasks)
                return matchMessage(for: matches, query: query)
            }

            _ = try await taskService.deleteTask(id: task.id)
            return "Deleted \"\(task.title)\"."
        } catch {
            return "I couldn’t delete that task because the local task store returned an error."
        }
    }

    func deleteTasks(matching queries: [String]) async -> String {
        let normalizedQueries = normalizedBatchValues(
            from: queries,
            emptyMessage: "I need at least one task title before I can delete anything.",
            limitMessage: "I can delete up to 10 tasks per request. Please shorten the list and try again."
        )

        switch normalizedQueries {
        case let .failure(message):
            return message
        case let .success(queries):
            do {
                let tasks = try await taskService.loadTasks()
                let resolved = try resolveBatchTasks(for: queries, in: tasks)

                for task in resolved {
                    _ = try await taskService.deleteTask(id: task.id)
                }

                if resolved.count == 1 {
                    return "Deleted \"\(resolved[0].title)\"."
                }

                let lines = resolved.enumerated().map { index, task in
                    "\(index + 1). \(task.title)"
                }

                return """
                Deleted \(resolved.count) tasks:
                \(lines.joined(separator: "\n"))
                """
            } catch let error as BatchResolutionError {
                return error.message
            } catch {
                return "I couldn’t delete all of those tasks because the local task store returned an error."
            }
        }
    }

    func renameTask(matching query: String, to newTitle: String) async -> String {
        let trimmedTitle = normalize(newTitle)
        guard !trimmedTitle.isEmpty else {
            return "I need a non-empty new title before I can rename a task."
        }

        do {
            let tasks = try await taskService.loadTasks()
            guard let task = resolveSingleTask(for: query, in: tasks) else {
                let matches = resolveMatches(for: query, in: tasks)
                return matchMessage(for: matches, query: query)
            }

            _ = try await taskService.updateTask(id: task.id, title: trimmedTitle)
            return "Renamed \"\(task.title)\" to \"\(trimmedTitle)\"."
        } catch {
            return "I couldn’t rename that task because the local task store returned an error."
        }
    }

    fileprivate func renameTasks(_ requests: [BatchRenameRequest]) async -> String {
        let normalizedRequests = normalizedRenameRequests(requests)

        switch normalizedRequests {
        case let .failure(message):
            return message
        case let .success(requests):
            do {
                let tasks = try await taskService.loadTasks()
                let resolved = try resolveBatchRenameRequests(requests, in: tasks)

                for item in resolved {
                    _ = try await taskService.updateTask(id: item.task.id, title: item.newTitle)
                }

                if resolved.count == 1, let item = resolved.first {
                    return "Renamed \"\(item.task.title)\" to \"\(item.newTitle)\"."
                }

                let lines = resolved.enumerated().map { index, item in
                    "\(index + 1). \(item.task.title) -> \(item.newTitle)"
                }

                return """
                Renamed \(resolved.count) tasks:
                \(lines.joined(separator: "\n"))
                """
            } catch let error as BatchResolutionError {
                return error.message
            } catch {
                return "I couldn’t rename all of those tasks because the local task store returned an error."
            }
        }
    }

    func setTaskCompletion(matching query: String, isCompleted: Bool) async -> String {
        do {
            let tasks = try await taskService.loadTasks()
            let matches = resolveMatches(for: query, in: tasks)

            guard let task = requireSingleMatch(matches, query: query) else {
                return matchMessage(for: matches, query: query)
            }

            guard task.isCompleted != isCompleted else {
                let state = isCompleted ? "already completed" : "already marked as pending"
                return "\"\(task.title)\" is \(state)."
            }

            _ = try await taskService.toggleTask(id: task.id)
            return isCompleted
                ? "Marked \"\(task.title)\" as completed."
                : "Marked \"\(task.title)\" as pending."
        } catch {
            return "I couldn’t update that task because the local task store returned an error."
        }
    }

    func listTasks() async -> String {
        do {
            let tasks = try await taskService.loadTasks()

            guard !tasks.isEmpty else {
                return "You don’t have any tasks yet."
            }

            let lines = tasks.enumerated().map { index, task in
                let state = task.isCompleted ? "done" : "pending"
                return "\(index + 1). \(task.title) (\(state))"
            }

            return lines.joined(separator: "\n")
        } catch {
            return "I couldn’t read the local task list right now."
        }
    }
}

private extension TaskAssistantActionHandler {
    enum BatchResolutionError: Error {
        case message(String)

        var message: String {
            switch self {
            case let .message(message):
                return message
            }
        }
    }

    enum ValidationResult<Value> {
        case success(Value)
        case failure(String)
    }

    struct ResolvedRenameRequest {
        let task: TaskItem
        let newTitle: String
    }

    func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func normalizedBatchValues(
        from values: [String],
        emptyMessage: String,
        limitMessage: String
    ) -> ValidationResult<[String]> {
        let normalizedValues = values
            .map(normalize)
            .filter { !$0.isEmpty }

        guard !normalizedValues.isEmpty else {
            return .failure(emptyMessage)
        }

        guard normalizedValues.count <= 10 else {
            return .failure(limitMessage)
        }

        return .success(normalizedValues)
    }

    func normalizedRenameRequests(_ requests: [BatchRenameRequest]) -> ValidationResult<[BatchRenameRequest]> {
        let normalizedRequests = requests.compactMap { request -> BatchRenameRequest? in
            let currentTitle = normalize(request.currentTitle)
            let newTitle = normalize(request.newTitle)

            guard !currentTitle.isEmpty, !newTitle.isEmpty else {
                return nil
            }

            return BatchRenameRequest(
                currentTitle: currentTitle,
                newTitle: newTitle
            )
        }

        guard !normalizedRequests.isEmpty else {
            return .failure("I need at least one current title and one new title before I can rename anything.")
        }

        guard normalizedRequests.count <= 10 else {
            return .failure("I can rename up to 10 tasks per request. Please shorten the list and try again.")
        }

        return .success(normalizedRequests)
    }

    func resolveMatches(for query: String, in tasks: [TaskItem]) -> [TaskItem] {
        let normalizedQuery = normalize(query).localizedLowercase
        guard !normalizedQuery.isEmpty else { return [] }

        let exactMatches = tasks.filter {
            normalize($0.title).localizedLowercase == normalizedQuery
        }

        if !exactMatches.isEmpty {
            return exactMatches
        }

        return tasks.filter {
            let normalizedTitle = normalize($0.title).localizedLowercase
            return normalizedTitle.contains(normalizedQuery) || normalizedQuery.contains(normalizedTitle)
        }
    }

    func resolveSingleTask(for query: String, in tasks: [TaskItem]) -> TaskItem? {
        let matches = resolveMatches(for: query, in: tasks)
        return requireSingleMatch(matches, query: query)
    }

    func resolveBatchTasks(for queries: [String], in tasks: [TaskItem]) throws -> [TaskItem] {
        var resolvedTasks: [TaskItem] = []
        var seenTaskIDs = Set<UUID>()

        for query in queries {
            let matches = resolveMatches(for: query, in: tasks)

            guard let task = requireSingleMatch(matches, query: query) else {
                throw BatchResolutionError.message(matchMessage(for: matches, query: query))
            }

            guard seenTaskIDs.insert(task.id).inserted else {
                throw BatchResolutionError.message("I can’t target the same task more than once in a single delete request.")
            }

            resolvedTasks.append(task)
        }

        return resolvedTasks
    }

    func resolveBatchRenameRequests(_ requests: [BatchRenameRequest], in tasks: [TaskItem]) throws -> [ResolvedRenameRequest] {
        var resolvedRequests: [ResolvedRenameRequest] = []
        var seenTaskIDs = Set<UUID>()

        for request in requests {
            let matches = resolveMatches(for: request.currentTitle, in: tasks)

            guard let task = requireSingleMatch(matches, query: request.currentTitle) else {
                throw BatchResolutionError.message(matchMessage(for: matches, query: request.currentTitle))
            }

            guard seenTaskIDs.insert(task.id).inserted else {
                throw BatchResolutionError.message("I can’t target the same task more than once in a single rename request.")
            }

            resolvedRequests.append(
                ResolvedRenameRequest(
                    task: task,
                    newTitle: request.newTitle
                )
            )
        }

        return resolvedRequests
    }

    func requireSingleMatch(_ matches: [TaskItem], query: String) -> TaskItem? {
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    func matchMessage(for matches: [TaskItem], query: String) -> String {
        switch matches.count {
        case 0:
            return "I couldn’t find a task matching \"\(normalize(query))\"."
        case 1:
            return "I found a single matching task."
        default:
            let options = matches.prefix(4).map(\.title).joined(separator: ", ")
            return "I found multiple matches for \"\(normalize(query))\": \(options). Which one should I use?"
        }
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for creating a new task.")
private struct CreateTaskArguments {
    let title: String
}

@available(iOS 26.0, *)
private struct CreateTaskTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Create a new to-do task using the provided title."

    func call(arguments: CreateTaskArguments) async throws -> String {
        await actionHandler.createTask(title: arguments.title)
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for creating multiple tasks in a single request.")
private struct CreateMultipleTasksArguments {
    let titles: [String]
}

@available(iOS 26.0, *)
private struct CreateMultipleTasksTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Create between 1 and 10 new to-do tasks from a list of titles."

    func call(arguments: CreateMultipleTasksArguments) async throws -> String {
        await actionHandler.createTasks(titles: arguments.titles)
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for deleting a task by title or close match.")
private struct DeleteTaskArguments {
    let taskTitle: String
}

@available(iOS 26.0, *)
private struct DeleteTaskTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Delete a task that matches the provided title."

    func call(arguments: DeleteTaskArguments) async throws -> String {
        await actionHandler.deleteTask(matching: arguments.taskTitle)
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for deleting multiple tasks in a single request.")
private struct DeleteMultipleTasksArguments {
    let taskTitles: [String]
}

@available(iOS 26.0, *)
private struct DeleteMultipleTasksTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Delete between 1 and 10 tasks that match the provided titles."

    func call(arguments: DeleteMultipleTasksArguments) async throws -> String {
        await actionHandler.deleteTasks(matching: arguments.taskTitles)
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for renaming a task.")
private struct RenameTaskArguments {
    let currentTitle: String
    let newTitle: String
}

fileprivate struct BatchRenameRequest {
    let currentTitle: String
    let newTitle: String
}

@available(iOS 26.0, *)
private struct RenameTaskTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Rename an existing task from its current title to a new one."

    func call(arguments: RenameTaskArguments) async throws -> String {
        await actionHandler.renameTask(
            matching: arguments.currentTitle,
            to: arguments.newTitle
        )
    }
}

@available(iOS 26.0, *)
@Generable(description: "A single task rename request.")
private struct RenameTaskItemArguments {
    let currentTitle: String
    let newTitle: String
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for renaming multiple tasks in a single request.")
private struct RenameMultipleTasksArguments {
    let renames: [RenameTaskItemArguments]
}

@available(iOS 26.0, *)
private struct RenameMultipleTasksTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Rename between 1 and 10 tasks by mapping each current title to a new title."

    func call(arguments: RenameMultipleTasksArguments) async throws -> String {
        let requests = arguments.renames.map { item in
            BatchRenameRequest(
                currentTitle: item.currentTitle,
                newTitle: item.newTitle
            )
        }

        return await actionHandler.renameTasks(requests)
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for marking a task completed or pending.")
private struct SetTaskCompletionArguments {
    let taskTitle: String
    let isCompleted: Bool
}

@available(iOS 26.0, *)
private struct SetTaskCompletionTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "Mark a matching task as completed or pending."

    func call(arguments: SetTaskCompletionArguments) async throws -> String {
        await actionHandler.setTaskCompletion(
            matching: arguments.taskTitle,
            isCompleted: arguments.isCompleted
        )
    }
}

@available(iOS 26.0, *)
@Generable(description: "Arguments for listing tasks.")
private struct ListTasksArguments {}

@available(iOS 26.0, *)
private struct ListTasksTool: Tool {
    let actionHandler: TaskAssistantActionHandler
    let description = "List the current tasks and their completion state."

    func call(arguments: ListTasksArguments) async throws -> String {
        await actionHandler.listTasks()
    }
}
