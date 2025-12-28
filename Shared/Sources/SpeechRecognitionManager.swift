import Foundation
import AVFoundation
import Speech

// MARK: - Speech Recognition Protocol

protocol SpeechRecognizer {
    func startRecording() throws
    func stopRecording() async throws -> String
    var isRecording: Bool { get }
}

// MARK: - Speech Recognition Manager

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var audioFileURL: URL?
    private var levelTimer: Timer?

    private let settings = SettingsManager.shared

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }

        // Create temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        audioFileURL = tempDir.appendingPathComponent(UUID().uuidString + ".m4a")

        guard let url = audioFileURL else { return }

        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: recordSettings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true

            // Start level monitoring
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateAudioLevel()
                }
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecordingAndTranscribe() async throws -> String {
        guard isRecording, let recorder = audioRecorder, let url = audioFileURL else {
            throw SpeechError.notRecording
        }

        levelTimer?.invalidate()
        levelTimer = nil
        recorder.stop()
        isRecording = false
        audioLevel = 0

        defer {
            // Cleanup temp file
            try? FileManager.default.removeItem(at: url)
        }

        // Transcribe based on selected provider
        switch settings.speechProvider {
        case .apple:
            return try await transcribeWithAppleSpeech(url: url)
        case .whisperAPI:
            return try await transcribeWithWhisperAPI(url: url)
        case .whisperLocal:
            return try await transcribeWithLocalWhisper(url: url)
        }
    }

    private func updateAudioLevel() {
        guard let recorder = audioRecorder, isRecording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // Convert dB to 0-1 range
        audioLevel = max(0, min(1, (level + 50) / 50))
    }

    // MARK: - Apple Speech Recognition

    private func transcribeWithAppleSpeech(url: URL) async throws -> String {
        // Check and request authorization if needed
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            guard status == .authorized else {
                throw SpeechError.notAuthorized
            }
        }

        let locale = Locale(identifier: settings.speechLanguage == "auto" ? "hu-HU" : settings.speechLanguage)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechError.recognizerNotAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - Whisper API

    private func transcribeWithWhisperAPI(url: URL) async throws -> String {
        let apiKey = settings.whisperAPIKey
        guard !apiKey.isEmpty else {
            throw SpeechError.missingAPIKey
        }

        let audioData = try Data(contentsOf: url)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add language hint if not auto
        if settings.speechLanguage != "auto" {
            let langCode = String(settings.speechLanguage.prefix(2)) // "hu-HU" -> "hu"
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(langCode)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SpeechError.apiError(errorText)
        }

        struct WhisperResponse: Codable {
            let text: String
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }

    // MARK: - Local Whisper

    private func transcribeWithLocalWhisper(url: URL) async throws -> String {
        // This will use WhisperKit - implementation to be added
        // For now, throw not implemented
        throw SpeechError.notImplemented("Local Whisper support coming soon. Please use Apple Speech or Whisper API for now.")
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case notRecording
    case notAuthorized
    case recognizerNotAvailable
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notRecording:
            return "Not currently recording"
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in Settings."
        case .recognizerNotAvailable:
            return "Speech recognizer not available for this language"
        case .missingAPIKey:
            return "API key is missing. Please add it in Settings."
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API error: \(message)"
        case .notImplemented(let message):
            return message
        }
    }
}
