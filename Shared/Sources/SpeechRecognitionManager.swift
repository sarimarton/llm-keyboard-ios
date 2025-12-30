import Foundation
import AVFoundation
import Speech
import os.log

private let logger = Logger(subsystem: "com.sarimarton.llmkeyboard", category: "SpeechManager")

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
    @Published var lastAudioFileSize: Int64 = 0  // For debugging
    @Published var lastAudioFileName: String = ""  // For debugging
    @Published var recordingStartFailed = false  // For debugging

    // AVAudioEngine based recording (instead of AVAudioRecorder which fails in extensions)
    // Keep engine alive between recordings to avoid "operation couldn't be completed" error
    private var audioEngine: AVAudioEngine?
    private var isEngineSetup = false
    private var audioFileURL: URL?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?

    // Speech recognition
    private var currentRecognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    private let settings = SettingsManager.shared

    // MARK: - Recording with AVAudioEngine

    // Track which step failed for debugging
    var failedAtStep: String = ""

    // On-screen step tracking (since Console doesn't work)
    @Published var currentStep: String = ""

    // Track the path taken for debugging
    private var stepPath: String = ""

    // Persistent engine that stays running
    private var engineStartedOnce = false
    private var tapInstalled = false

    func startRecording() {
        guard !isRecording else { return }

        failedAtStep = ""
        recordingStartFailed = false
        stepPath = ""

        // Dispatch to the appropriate mode
        let mode = settings.audioEngineMode
        step("M\(mode.modeLabel)")

        switch mode {
        case .tapFirst:
            startRecordingTapFirst()
        case .startFirst:
            startRecordingStartFirst()
        case .streaming:
            startRecordingStreaming()
        case .noTapDiag:
            startRecordingNoTapDiag()
        }
    }

    private func step(_ s: String) {
        currentStep = s
        stepPath += stepPath.isEmpty ? s : ">\(s)"
    }

    // MARK: - Mode A: Tap First (current approach)
    private func startRecordingTapFirst() {
        step("1")
        cleanupOldAudioFiles()

        step("2")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            failedAtStep = "\(stepPath)>ses:\(error.localizedDescription.prefix(10))"
            recordingStartFailed = true
            return
        }

        step("3")
        let uniqueFilename = "rec_\(UUID().uuidString).wav"
        audioFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename)

        guard let url = audioFileURL else {
            failedAtStep = "\(stepPath)>url"
            recordingStartFailed = true
            return
        }

        do {
            // Check engine state
            let e = audioEngine != nil ? 1 : 0
            let s = engineStartedOnce ? 1 : 0
            let r = audioEngine?.isRunning == true ? 1 : 0
            step("4e\(e)s\(s)r\(r)")

            // Reuse running engine or create new
            if let existingEngine = audioEngine, engineStartedOnce, existingEngine.isRunning {
                step("4K")
                if tapInstalled {
                    existingEngine.inputNode.removeTap(onBus: 0)
                    tapInstalled = false
                }
            } else {
                step("4N")
                cleanupEngine()
                Thread.sleep(forTimeInterval: 0.1)
                audioEngine = AVAudioEngine()
            }

            guard let engine = audioEngine else {
                failedAtStep = "\(stepPath)>nil"
                recordingStartFailed = true
                return
            }

            step("5")
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                failedAtStep = "\(stepPath)>fmt"
                recordingStartFailed = true
                return
            }

            step("6")
            let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: inputFormat.sampleRate,
                                          channels: 1,
                                          interleaved: false)!
            audioFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)

            step("7tap")
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                Task { @MainActor in self?.processAudioBuffer(buffer) }
            }
            tapInstalled = true

            if !engine.isRunning {
                step("8p")
                engine.prepare()
                step("8s")
                try engine.start()
                engineStartedOnce = true
            } else {
                step("8run")
            }

            finishStart()
        } catch {
            failedAtStep = "\(stepPath)>!\(error.localizedDescription.prefix(10))"
            recordingStartFailed = true
        }
    }

    // MARK: - Mode B: Start First (start engine before installing tap)
    private func startRecordingStartFirst() {
        step("1")
        cleanupOldAudioFiles()

        step("2")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            failedAtStep = "\(stepPath)>ses"
            recordingStartFailed = true
            return
        }

        step("3")
        let uniqueFilename = "rec_\(UUID().uuidString).wav"
        audioFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueFilename)

        guard let url = audioFileURL else {
            failedAtStep = "\(stepPath)>url"
            recordingStartFailed = true
            return
        }

        do {
            let e = audioEngine != nil ? 1 : 0
            let s = engineStartedOnce ? 1 : 0
            let r = audioEngine?.isRunning == true ? 1 : 0
            step("4e\(e)s\(s)r\(r)")

            // Reuse or create engine
            if let existingEngine = audioEngine, engineStartedOnce, existingEngine.isRunning {
                step("4K")
                if tapInstalled {
                    existingEngine.inputNode.removeTap(onBus: 0)
                    tapInstalled = false
                }
            } else {
                step("4N")
                cleanupEngine()
                Thread.sleep(forTimeInterval: 0.1)
                audioEngine = AVAudioEngine()
            }

            guard let engine = audioEngine else {
                failedAtStep = "\(stepPath)>nil"
                recordingStartFailed = true
                return
            }

            // START FIRST (before tap)
            if !engine.isRunning {
                step("5p")
                engine.prepare()
                step("5s")
                try engine.start()
                engineStartedOnce = true
            } else {
                step("5run")
            }

            step("6")
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                failedAtStep = "\(stepPath)>fmt"
                recordingStartFailed = true
                return
            }

            step("7")
            let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: inputFormat.sampleRate,
                                          channels: 1,
                                          interleaved: false)!
            audioFile = try AVAudioFile(forWriting: url, settings: fileFormat.settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)

            step("8tap")
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                Task { @MainActor in self?.processAudioBuffer(buffer) }
            }
            tapInstalled = true

            finishStart()
        } catch {
            failedAtStep = "\(stepPath)>!\(error.localizedDescription.prefix(10))"
            recordingStartFailed = true
        }
    }

    // MARK: - Mode C: Streaming (direct to SFSpeech, no file)
    private var streamingRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    private func startRecordingStreaming() {
        step("1")
        cleanupOldAudioFiles()

        step("2")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            failedAtStep = "\(stepPath)>ses"
            recordingStartFailed = true
            return
        }

        do {
            let e = audioEngine != nil ? 1 : 0
            let s = engineStartedOnce ? 1 : 0
            let r = audioEngine?.isRunning == true ? 1 : 0
            step("3e\(e)s\(s)r\(r)")

            if let existingEngine = audioEngine, engineStartedOnce, existingEngine.isRunning {
                step("3K")
                if tapInstalled {
                    existingEngine.inputNode.removeTap(onBus: 0)
                    tapInstalled = false
                }
            } else {
                step("3N")
                cleanupEngine()
                Thread.sleep(forTimeInterval: 0.1)
                audioEngine = AVAudioEngine()
            }

            guard let engine = audioEngine else {
                failedAtStep = "\(stepPath)>nil"
                recordingStartFailed = true
                return
            }

            step("4")
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                failedAtStep = "\(stepPath)>fmt"
                recordingStartFailed = true
                return
            }

            // Create streaming request
            step("5req")
            streamingRecognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            streamingRecognitionRequest?.shouldReportPartialResults = false

            step("6tap")
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                self?.streamingRecognitionRequest?.append(buffer)
            }
            tapInstalled = true

            if !engine.isRunning {
                step("7p")
                engine.prepare()
                step("7s")
                try engine.start()
                engineStartedOnce = true
            } else {
                step("7run")
            }

            finishStart()
        } catch {
            failedAtStep = "\(stepPath)>!\(error.localizedDescription.prefix(10))"
            recordingStartFailed = true
        }
    }

    // MARK: - Mode D: No Tap Diagnostic (just start engine, no recording)
    private func startRecordingNoTapDiag() {
        step("1")

        step("2")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            failedAtStep = "\(stepPath)>ses"
            recordingStartFailed = true
            return
        }

        do {
            let e = audioEngine != nil ? 1 : 0
            let s = engineStartedOnce ? 1 : 0
            let r = audioEngine?.isRunning == true ? 1 : 0
            step("3e\(e)s\(s)r\(r)")

            // Always create fresh engine for diagnostic
            step("3N")
            cleanupEngine()
            Thread.sleep(forTimeInterval: 0.1)
            audioEngine = AVAudioEngine()

            guard let engine = audioEngine else {
                failedAtStep = "\(stepPath)>nil"
                recordingStartFailed = true
                return
            }

            // NO TAP - just start the engine
            step("4p")
            engine.prepare()
            step("4s")
            try engine.start()
            engineStartedOnce = true

            // Engine started successfully!
            finishStart()
        } catch {
            failedAtStep = "\(stepPath)>!\(error.localizedDescription.prefix(10))"
            recordingStartFailed = true
        }
    }

    // MARK: - Helpers

    private func cleanupEngine() {
        if let engine = audioEngine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            engine.stop()
            engine.reset()
        }
        audioEngine = nil
        engineStartedOnce = false
    }

    private func finishStart() {
        recordingStartTime = Date()
        isRecording = true
        recordingStartFailed = false
        currentStep = stepPath + ">OK"
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }

        // Update audio level for UI feedback
        if let channelData = buffer.floatChannelData?[0] {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += abs(channelData[i])
            }
            let average = sum / Float(frameLength)
            // Scale to 0-1 range
            audioLevel = min(1.0, average * 5)
        }

        // Write to file
        do {
            try audioFile?.write(from: buffer)
        } catch {
            logDebug("❌ Error writing audio buffer: \(error)")
        }
    }

    private func stopAudioEngine() {
        // Don't stop the engine - just remove tap and close file
        // Keeping the engine alive avoids "operation couldn't be completed" on restart
        if let engine = audioEngine, tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            // DON'T stop: engine.stop()
            logDebug("Tap removed (engine kept alive)")
        }
        // DON'T nil out: audioEngine = nil
        audioFile = nil
    }

    func stopRecordingAndTranscribe() async throws -> String {
        guard isRecording else {
            logDebug("❌ Not currently recording")
            throw SpeechError.notRecording
        }

        // Cancel any previous recognition task
        if let task = currentRecognitionTask {
            logDebug("Cancelling previous recognition task...")
            task.cancel()
            currentRecognitionTask = nil
        }

        // Calculate recording duration
        let recordingDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        logDebug("Stopping recording after \(String(format: "%.1f", recordingDuration))s...")

        // Stop the engine and close the file
        stopAudioEngine()
        isRecording = false
        audioLevel = 0

        lastAudioFileName = "d:\(String(format: "%.1f", recordingDuration))s"

        // Handle streaming mode (Mode C) separately
        if settings.audioEngineMode == .streaming {
            return try await transcribeStreaming()
        }

        // Handle diagnostic mode (Mode D) - no actual recording
        if settings.audioEngineMode == .noTapDiag {
            lastAudioFileSize = 0
            return "[DIAG MODE - No audio recorded. Engine start was successful!]"
        }

        // Normal modes (A, B) - use file
        guard let url = audioFileURL else {
            throw SpeechError.notRecording
        }

        // Get audio file info for debugging
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            lastAudioFileSize = size
            logDebug("Audio file size: \(size) bytes")
        } else {
            lastAudioFileSize = -1
        }

        logDebug("Starting transcription with provider: \(settings.speechProvider.displayName)")

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

    // MARK: - Streaming Transcription (Mode C)
    private func transcribeStreaming() async throws -> String {
        logDebug("Using streaming transcription")

        guard let request = streamingRecognitionRequest else {
            throw SpeechError.notRecording
        }

        // End the audio stream
        request.endAudio()

        let locale = Locale(identifier: settings.speechLanguage == "auto" ? "hu-HU" : settings.speechLanguage)
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerNotAvailable
        }

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            var didResume = false

            currentRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] taskResult, error in
                guard !didResume else { return }

                if let error = error {
                    didResume = true
                    self?.logDebug("❌ Streaming recognition error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                if let taskResult = taskResult, taskResult.isFinal {
                    didResume = true
                    self?.logDebug("✅ Streaming transcription: \(taskResult.bestTranscription.formattedString.prefix(50))...")
                    continuation.resume(returning: taskResult.bestTranscription.formattedString)
                }
            }
        }

        currentRecognitionTask = nil
        speechRecognizer = nil
        streamingRecognitionRequest = nil

        return result
    }

    private func logDebug(_ message: String) {
        NSLog("🔍 [SpeechManager] %@", message)
    }

    private func cleanupOldAudioFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("rec_") && (file.pathExtension == "m4a" || file.pathExtension == "wav") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Apple Speech Recognition

    private func transcribeWithAppleSpeech(url: URL) async throws -> String {
        logDebug("Using Apple Speech Recognition")

        // Check and request authorization if needed
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            logDebug("Speech authorization not granted, requesting...")
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            guard status == .authorized else {
                logDebug("❌ Speech authorization denied: \(status)")
                throw SpeechError.notAuthorized
            }
            logDebug("✅ Speech authorization granted")
        }

        let locale = Locale(identifier: settings.speechLanguage == "auto" ? "hu-HU" : settings.speechLanguage)
        logDebug("Using locale: \(locale.identifier)")

        // Create fresh recognizer each time (reset state)
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            logDebug("❌ Recognizer not available for locale: \(locale.identifier)")
            throw SpeechError.recognizerNotAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        logDebug("Starting recognition task...")

        let result: String
        do {
            result = try await withCheckedThrowingContinuation { continuation in
                var didResume = false

                self.currentRecognitionTask = recognizer.recognitionTask(with: request) { [weak self] taskResult, error in
                    guard !didResume else { return }

                    if let error = error {
                        didResume = true
                        self?.logDebug("❌ Recognition error: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                        return
                    }

                    if let taskResult = taskResult, taskResult.isFinal {
                        didResume = true
                        self?.logDebug("✅ Transcription completed: \(taskResult.bestTranscription.formattedString.prefix(50))...")
                        continuation.resume(returning: taskResult.bestTranscription.formattedString)
                    }
                }
            }
        } catch {
            // DON'T deactivate audio session - it kills AVAudioEngine!
            // try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            currentRecognitionTask = nil
            speechRecognizer = nil
            throw error
        }

        currentRecognitionTask = nil
        speechRecognizer = nil
        // DON'T deactivate audio session - it kills AVAudioEngine!
        // try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return result
    }

    // MARK: - Whisper API

    private func transcribeWithWhisperAPI(url: URL) async throws -> String {
        logDebug("Using Whisper API")

        let apiKey = settings.whisperAPIKey
        guard !apiKey.isEmpty else {
            logDebug("❌ Whisper API key is missing")
            throw SpeechError.missingAPIKey
        }

        logDebug("Reading audio file...")
        let audioData = try Data(contentsOf: url)
        logDebug("Audio file size: \(audioData.count) bytes")

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file - use correct extension based on actual format
        let fileExtension = url.pathExtension
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(fileExtension)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/\(fileExtension)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add language hint if not auto
        if settings.speechLanguage != "auto" {
            let langCode = String(settings.speechLanguage.prefix(2))
            logDebug("Using language hint: \(langCode)")
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(langCode)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        logDebug("Sending request to Whisper API...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logDebug("❌ Invalid response type")
            throw SpeechError.invalidResponse
        }

        logDebug("Response status code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            logDebug("❌ API Error (\(httpResponse.statusCode)): \(errorText)")
            throw SpeechError.apiError(errorText)
        }

        struct WhisperResponse: Codable {
            let text: String
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        logDebug("✅ Transcription completed: \(result.text.prefix(50))...")
        return result.text
    }

    // MARK: - Local Whisper

    private func transcribeWithLocalWhisper(url: URL) async throws -> String {
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
