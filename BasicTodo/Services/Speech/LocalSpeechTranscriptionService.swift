import AVFoundation
import Foundation
import OSLog
import Speech

enum SpeechTranscriptionAvailability: Equatable, Sendable {
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

@MainActor
final class LocalSpeechTranscriptionService: NSObject {
    private let logger = Logger(subsystem: "BasicTodo", category: "Speech")
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var activeLocale: Locale?

    func availability(for locale: Locale? = nil) -> SpeechTranscriptionAvailability {
        let resolvedLocale = locale ?? preferredTranscriptionLocale()

        guard resolvedRecognizer(for: resolvedLocale) != nil else {
            return .unavailable(unavailableMessage(for: resolvedLocale))
        }

        return .available
    }

    func startTranscribing(
        locale: Locale? = nil,
        onTextUpdate: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async throws {
        let requestedLocale = locale ?? preferredTranscriptionLocale()
        try await requestPermissions()

        let availability = availability(for: requestedLocale)
        guard case .available = availability else {
            throw LocalSpeechTranscriptionError.unavailable(availability.message ?? Self.defaultUnavailableMessage)
        }

        stopTranscribing()

        guard let recognizer = resolvedRecognizer(for: requestedLocale) else {
            throw LocalSpeechTranscriptionError.unavailable(Self.defaultUnavailableMessage)
        }

        self.recognizer = recognizer
        self.activeLocale = recognizer.locale

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        try configureAudioSession()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Local-only enforcement:
        // - `requiresOnDeviceRecognition = true` prevents remote speech recognition fallback.
        // - If on-device transcription is unsupported, startup fails closed with a user-facing message.
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                Task { @MainActor in
                    onTextUpdate(result.bestTranscription.formattedString)
                }
            }

            if let error {
                Task { @MainActor in
                    let detailedMessage = self?.detailedErrorMessage(for: error) ?? error.localizedDescription
                    self?.stopTranscribing()
                    onError(detailedMessage)
                }
            }
        }
    }

    func stopTranscribing() {
        logger.debug("Stopping transcription. audioEngineRunning=\(self.audioEngine.isRunning, privacy: .public)")
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        activeLocale = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Best effort cleanup for the local microphone session.
            logger.error("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension LocalSpeechTranscriptionService {
    static let defaultUnavailableMessage = "On-device speech transcription is unavailable. No network fallback will be used."

    func preferredTranscriptionLocale() -> Locale {
        if let preferredIdentifier = Locale.preferredLanguages.first {
            return Locale(identifier: preferredIdentifier)
        }

        return .autoupdatingCurrent
    }

    func resolvedRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        for candidate in candidateLocales(for: locale) {
            guard let recognizer = SFSpeechRecognizer(locale: candidate) else { continue }
            guard recognizer.supportsOnDeviceRecognition else { continue }
            return recognizer
        }

        return nil
    }

    func candidateLocales(for locale: Locale) -> [Locale] {
        var locales: [Locale] = [locale]
        let requestedLanguageCode = locale.language.languageCode?.identifier

        if let requestedLanguageCode {
            let matchingSupportedLocales = SFSpeechRecognizer.supportedLocales()
                .filter { supportedLocale in
                    supportedLocale.language.languageCode?.identifier == requestedLanguageCode
                }
                .sorted { lhs, rhs in
                    let lhsRegionMatches = lhs.region == locale.region
                    let rhsRegionMatches = rhs.region == locale.region

                    if lhsRegionMatches != rhsRegionMatches {
                        return lhsRegionMatches && !rhsRegionMatches
                    }

                    return lhs.identifier < rhs.identifier
                }

            locales.append(contentsOf: matchingSupportedLocales)
        }

        var seen = Set<String>()
        return locales.filter { candidate in
            seen.insert(candidate.identifier).inserted
        }
    }

    func unavailableMessage(for locale: Locale) -> String {
        let languageDescription = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier

        return "On-device speech transcription is unavailable for \(languageDescription). No network fallback will be used."
    }

    func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        logger.debug("Speech authorization status raw value: \(speechStatus.rawValue, privacy: .public)")

        guard speechStatus == .authorized else {
            throw LocalSpeechTranscriptionError.permissionDenied(
                "Speech recognition permission was denied. Enable it in Settings to use the microphone."
            )
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        logger.debug("Microphone permission granted: \(microphoneGranted, privacy: .public)")

        guard microphoneGranted else {
            throw LocalSpeechTranscriptionError.permissionDenied(
                "Microphone permission was denied. Enable it in Settings to use voice input."
            )
        }
    }

    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        logger.debug("Audio session active with category record / measurement.")
    }
    func detailedErrorMessage(for error: any Error) -> String {
        let nsError = error as NSError
        let domain = nsError.domain
        let code = nsError.code
        let failureReason = nsError.localizedFailureReason ?? "No failure reason provided."
        let recoverySuggestion = nsError.localizedRecoverySuggestion ?? "No recovery suggestion provided."

        return """
        \(error.localizedDescription)
        Domain: \(domain)
        Code: \(code)
        Reason: \(failureReason)
        Suggestion: \(recoverySuggestion)
        """
    }
}

enum LocalSpeechTranscriptionError: LocalizedError {
    case unavailable(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .permissionDenied(message):
            return message
        }
    }
}
