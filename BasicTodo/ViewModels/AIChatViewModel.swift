import Foundation

@MainActor
final class AIChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published var draftMessage = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var isRecording = false
    @Published private(set) var availability: TaskAssistantAvailability
    @Published private(set) var speechAvailability: SpeechTranscriptionAvailability
    @Published var speechMessage: String?
    @Published var recordingHint = "Press and hold the microphone to record."

    private let service: TaskAssistantService
    private let speechService: LocalSpeechTranscriptionService
    private let onTasksUpdated: @MainActor ([TaskItem]) -> Void

    init(
        taskService: TaskManaging,
        onTasksUpdated: @escaping @MainActor ([TaskItem]) -> Void
    ) {
        self.service = TaskAssistantService(taskService: taskService)
        self.speechService = LocalSpeechTranscriptionService()
        self.onTasksUpdated = onTasksUpdated
        self.availability = service.availability()
        self.speechAvailability = speechService.availability()
        self.messages = [Self.makeWelcomeMessage(for: availability)]
    }

    var isUnavailable: Bool {
        if case .unavailable = availability {
            return true
        }

        return false
    }

    var isSendDisabled: Bool {
        isGenerating || draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUnavailable
    }

    var isMicrophoneDisabled: Bool {
        isGenerating || isUnavailable || isSpeechUnavailable
    }

    var isSpeechUnavailable: Bool {
        if case .unavailable = speechAvailability {
            return true
        }

        return false
    }

    func sendMessage() async {
        let trimmedMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }

        stopRecording()

        availability = service.availability()

        guard !isUnavailable else {
            let message = availability.message ?? "The on-device Apple model is unavailable."
            appendAssistantMessage(message)
            draftMessage = ""
            return
        }

        draftMessage = ""
        messages.append(ChatMessage(role: .user, content: trimmedMessage))
        isGenerating = true

        let response = await service.respond(to: trimmedMessage)

        isGenerating = false
        messages.append(ChatMessage(role: .assistant, content: response.message))
        onTasksUpdated(response.tasks)
    }

    func refreshAvailability() {
        availability = service.availability()
        speechAvailability = speechService.availability()
        if isSpeechUnavailable {
            speechMessage = speechAvailability.message
        } else if speechMessage == speechAvailability.message {
            speechMessage = nil
        }
    }

    func syncTasks() async {
        guard let tasks = try? await service.currentTasks() else { return }
        onTasksUpdated(tasks)
    }

    func startRecording() async {
        guard !isRecording else { return }
        speechAvailability = speechService.availability()

        guard !isSpeechUnavailable else {
            speechMessage = speechAvailability.message
            return
        }

        do {
            try await speechService.startTranscribing(
                onTextUpdate: { [weak self] text in
                    self?.draftMessage = text
                },
                onError: { [weak self] message in
                    self?.isRecording = false
                    self?.speechMessage = message
                }
            )
            speechMessage = nil
            isRecording = true
        } catch {
            speechMessage = error.localizedDescription
            isRecording = false
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        speechService.stopTranscribing()
        isRecording = false
    }
}

private extension AIChatViewModel {
    static func makeWelcomeMessage(for availability: TaskAssistantAvailability) -> ChatMessage {
        let content: String

        switch availability {
        case .available:
            content = "I’m your local task assistant. Ask me to add, rename, delete, complete, or list tasks. Everything stays on-device."
        case let .unavailable(message):
            content = message
        }

        return ChatMessage(role: .assistant, content: content)
    }

    func appendAssistantMessage(_ content: String) {
        guard messages.last?.content != content else { return }
        messages.append(ChatMessage(role: .assistant, content: content))
    }
}
