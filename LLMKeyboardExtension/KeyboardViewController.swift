import UIKit
import os.log

private let logger = Logger(subsystem: "com.sarimarton.llmkeyboard.keyboard", category: "KeyboardVC")

class KeyboardViewController: UIInputViewController {

    // MARK: - UI Components

    private var mainStackView: UIStackView!
    private var micButton: UIButton!
    private var statusLabel: UILabel!
    private var suggestionBar: UIView!
    private var keyboardView: UIView!
    private var fullAccessOverlay: UIView!

    // MARK: - State

    private var speechManager: SpeechRecognitionManager?
    private var isProcessing = false
    private var debugMode = true // Set to false in production

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupFullAccessOverlay()
        setupObservers()
        updateFullAccessState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateFullAccessState()
        refreshModeDisplay()
    }

    private func refreshModeDisplay() {
        SettingsManager.shared.refresh()
        let mode = SettingsManager.shared.audioEngineMode.modeLabel
        statusLabel.text = "🚀 B32 Mode:\(mode)"
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // Called when text is about to change
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // Called when text has changed
        updateKeyboardAppearance()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let inputView = inputView else { return }

        // Main container
        mainStackView = UIStackView()
        mainStackView.axis = .vertical
        mainStackView.spacing = 8
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(mainStackView)

        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: inputView.topAnchor, constant: 8),
            mainStackView.leadingAnchor.constraint(equalTo: inputView.leadingAnchor, constant: 8),
            mainStackView.trailingAnchor.constraint(equalTo: inputView.trailingAnchor, constant: -8),
            mainStackView.bottomAnchor.constraint(equalTo: inputView.bottomAnchor, constant: -8)
        ])

        // Status bar
        setupStatusBar()

        // Main action area
        setupActionArea()

        // Keyboard controls
        setupKeyboardControls()

        updateKeyboardAppearance()
    }

    private func setupFullAccessOverlay() {
        guard let inputView = inputView else { return }

        fullAccessOverlay = UIView()
        fullAccessOverlay.translatesAutoresizingMaskIntoConstraints = false
        fullAccessOverlay.backgroundColor = .systemBackground
        fullAccessOverlay.isHidden = true
        inputView.addSubview(fullAccessOverlay)

        NSLayoutConstraint.activate([
            fullAccessOverlay.topAnchor.constraint(equalTo: inputView.topAnchor),
            fullAccessOverlay.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            fullAccessOverlay.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            fullAccessOverlay.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)
        ])

        // Main horizontal layout: [Globe] [Content]
        let mainStack = UIStackView()
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        fullAccessOverlay.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: fullAccessOverlay.topAnchor, constant: 8),
            mainStack.leadingAnchor.constraint(equalTo: fullAccessOverlay.leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: fullAccessOverlay.trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: fullAccessOverlay.bottomAnchor, constant: -8)
        ])

        // Globe button (left side)
        let globeButton = UIButton(type: .system)
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = .label
        globeButton.backgroundColor = .secondarySystemBackground
        globeButton.layer.cornerRadius = 8
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .touchUpInside)
        mainStack.addArrangedSubview(globeButton)

        NSLayoutConstraint.activate([
            globeButton.widthAnchor.constraint(equalToConstant: 44),
            globeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Content (center)
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 4
        contentStack.alignment = .center
        mainStack.addArrangedSubview(contentStack)

        // Title row with icon
        let titleStack = UIStackView()
        titleStack.axis = .horizontal
        titleStack.spacing = 6
        titleStack.alignment = .center
        contentStack.addArrangedSubview(titleStack)

        let iconLabel = UILabel()
        iconLabel.text = "🔒"
        iconLabel.font = .systemFont(ofSize: 18)
        titleStack.addArrangedSubview(iconLabel)

        let titleLabel = UILabel()
        titleLabel.text = "Full Access Required"
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = .label
        titleStack.addArrangedSubview(titleLabel)

        // Instructions
        let instructionsLabel = UILabel()
        instructionsLabel.text = "Settings → General → Keyboard → LLM Keyboard → Full Access"
        instructionsLabel.font = .systemFont(ofSize: 11)
        instructionsLabel.textColor = .secondaryLabel
        instructionsLabel.numberOfLines = 2
        instructionsLabel.textAlignment = .center
        contentStack.addArrangedSubview(instructionsLabel)

        // Spacer to push globe button alignment
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(spacer)

        NSLayoutConstraint.activate([
            spacer.widthAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func updateFullAccessState() {
        let hasAccess = hasFullAccess
        fullAccessOverlay.isHidden = hasAccess
        mainStackView.isHidden = !hasAccess
        logDebug("Full Access state: \(hasAccess ? "granted" : "denied")")
    }

    private func setupStatusBar() {
        statusLabel = UILabel()
        let mode = SettingsManager.shared.audioEngineMode.rawValue.prefix(1).uppercased()
        statusLabel.text = "🚀 B32 Mode:\(mode)"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        mainStackView.addArrangedSubview(statusLabel)
    }

    private func setupActionArea() {
        let actionContainer = UIView()
        actionContainer.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.addArrangedSubview(actionContainer)

        NSLayoutConstraint.activate([
            actionContainer.heightAnchor.constraint(equalToConstant: 80)
        ])

        // Microphone button
        micButton = UIButton(type: .system)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = .systemBlue
        micButton.layer.cornerRadius = 30
        micButton.addTarget(self, action: #selector(micButtonTapped), for: .touchUpInside)
        actionContainer.addSubview(micButton)

        NSLayoutConstraint.activate([
            micButton.centerXAnchor.constraint(equalTo: actionContainer.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: actionContainer.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 60),
            micButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func setupKeyboardControls() {
        let controlsStack = UIStackView()
        controlsStack.axis = .horizontal
        controlsStack.distribution = .equalSpacing
        controlsStack.spacing = 8
        mainStackView.addArrangedSubview(controlsStack)

        // Globe button (switch keyboard)
        let globeButton = createControlButton(systemName: "globe", action: #selector(handleInputModeList(from:with:)))

        // Settings button (open host app)
        let settingsButton = createControlButton(systemName: "gearshape", action: #selector(openHostApp))

        // Space button
        let spaceButton = createControlButton(title: "space", action: #selector(spaceButtonTapped))
        spaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        // Backspace button
        let backspaceButton = createControlButton(systemName: "delete.left", action: #selector(backspaceButtonTapped))

        // Return button
        let returnButton = createControlButton(systemName: "return", action: #selector(returnButtonTapped))

        controlsStack.addArrangedSubview(globeButton)
        controlsStack.addArrangedSubview(settingsButton)
        controlsStack.addArrangedSubview(spaceButton)
        controlsStack.addArrangedSubview(backspaceButton)
        controlsStack.addArrangedSubview(returnButton)

        NSLayoutConstraint.activate([
            controlsStack.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func createControlButton(systemName: String? = nil, title: String? = nil, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        if let systemName = systemName {
            button.setImage(UIImage(systemName: systemName), for: .normal)
        }
        if let title = title {
            button.setTitle(title, for: .normal)
        }

        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 8
        button.addTarget(self, action: action, for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        return button
    }

    // MARK: - Appearance

    private func updateKeyboardAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark

        inputView?.backgroundColor = isDark ? UIColor(white: 0.1, alpha: 1) : UIColor(white: 0.95, alpha: 1)
        statusLabel.textColor = isDark ? .lightGray : .darkGray
    }

    // MARK: - Observers

    private func setupObservers() {
        // Observe recording state changes
        // This would be done with Combine in a real implementation
    }

    // MARK: - Actions

    @objc private func micButtonTapped() {
        let isRecording = speechManager?.isRecording ?? false
        NSLog("🎤🎤🎤 MIC TAPPED! isRecording=%d, isProcessing=%d", isRecording ? 1 : 0, isProcessing ? 1 : 0)
        statusLabel.text = "🎤 Mic tapped..."

        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        NSLog("▶️ startRecording called, isProcessing=%d", isProcessing ? 1 : 0)

        guard !isProcessing else {
            NSLog("⛔️ BLOCKED by isProcessing=true!")
            statusLabel.text = "⛔️ Still processing..."
            return
        }

        // REUSE the same manager to keep AVAudioEngine alive between recordings
        // Creating fresh manager each time causes "operation couldn't be completed" error
        if speechManager == nil {
            speechManager = SpeechRecognitionManager()
        }
        speechManager?.startRecording()
        updateMicButtonState(recording: true)

        // Show if recording actually started
        let mode = SettingsManager.shared.audioEngineMode.modeLabel
        if speechManager?.recordingStartFailed == true {
            let lastStep = speechManager?.currentStep ?? "?"
            let failStep = speechManager?.failedAtStep ?? "?"
            statusLabel.text = "❌\(mode) @\(lastStep) fail:\(failStep)"
        } else {
            let step = speechManager?.currentStep ?? "?"
            statusLabel.text = "🎤\(mode) \(step)"
        }
    }

    private func stopRecording() {
        guard let manager = speechManager, manager.isRecording else { return }

        isProcessing = true
        updateMicButtonState(recording: false)
        // Will be updated with file size after recording stops
        statusLabel.text = "⏳ Processing..."

        // Log current settings for debugging
        let settings = SettingsManager.shared
        logDebug("========== CURRENT SETTINGS ==========")
        logDebug("Speech Provider: \(settings.speechProvider.displayName)")
        logDebug("Speech Language: \(settings.speechLanguage)")
        logDebug("LLM Cleanup Enabled: \(settings.enableLLMCleanup)")
        if settings.enableLLMCleanup {
            logDebug("LLM Service: \(settings.llmServiceType.displayName)")
            logDebug("LLM Base URL: \(settings.llmBaseURL)")
            logDebug("LLM Model: \(settings.llmModelName)")
            logDebug("LLM API Key present: \(!settings.llmAPIKey.isEmpty) (length: \(settings.llmAPIKey.count))")
        }
        if settings.speechProvider == .whisperAPI {
            logDebug("Whisper API Key present: \(!settings.whisperAPIKey.isEmpty) (length: \(settings.whisperAPIKey.count))")
        }
        logDebug("=======================================")

        Task {
            do {
                // Transcribe
                let transcription = try await manager.stopRecordingAndTranscribe()

                // Show file size on success
                await MainActor.run {
                    statusLabel.text = "📁 \(manager.lastAudioFileSize) bytes → transcribing..."
                }

                // Cleanup with LLM if enabled
                let settings = SettingsManager.shared
                let finalText: String

                if settings.enableLLMCleanup {
                    await MainActor.run {
                        statusLabel.text = "🤖 Cleaning up with \(settings.llmServiceType.displayName)..."
                    }
                    logDebug("Starting LLM cleanup with \(settings.llmServiceType.displayName)")
                    logDebug("Model: \(settings.llmModelName)")
                    logDebug("Base URL: \(settings.llmBaseURL)")
                    logDebug("API Key present: \(!settings.llmAPIKey.isEmpty)")
                    
                    finalText = try await LLMService.shared.cleanup(text: transcription)
                    logDebug("LLM cleanup completed: \(finalText.prefix(50))...")
                } else {
                    logDebug("LLM cleanup disabled, using raw transcription")
                    finalText = transcription
                }

                // Insert text
                await MainActor.run {
                    textDocumentProxy.insertText(finalText)
                    let duration = manager.lastAudioFileName  // Contains "d:X.Xs"
                    let size = manager.lastAudioFileSize
                    statusLabel.text = "✅ \(duration) \(size)B"
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    // Show error with file info for debugging
                    let fileSize = manager.lastAudioFileSize
                    let duration = manager.lastAudioFileName  // Contains "d:X.Xs"
                    statusLabel.text = "❌ \(duration) \(fileSize)B: \(error.localizedDescription.prefix(30))"
                    isProcessing = false
                }
            }
        }
    }
    
    // MARK: - Error Formatting
    
    private func formatError(_ error: Error) -> String {
        if debugMode {
            // Detailed error for debugging
            if let llmError = error as? LLMError {
                switch llmError {
                case .missingAPIKey:
                    return "❌ Missing API Key! Check Settings"
                case .missingBaseURL:
                    return "❌ Missing Base URL! Check Settings"
                case .invalidResponse:
                    return "❌ Invalid API Response"
                case .apiError(let code, let message):
                    return "❌ API Error (\(code)): \(message.prefix(100))"
                case .noContent:
                    return "❌ No content in API response"
                }
            } else if let speechError = error as? SpeechError {
                switch speechError {
                case .notRecording:
                    return "❌ Not recording"
                case .notAuthorized:
                    return "❌ Speech not authorized - Enable in iOS Settings"
                case .recognizerNotAvailable:
                    return "❌ Recognizer not available for this language"
                case .missingAPIKey:
                    return "❌ Whisper API Key missing!"
                case .invalidResponse:
                    return "❌ Invalid response from Whisper API"
                case .apiError(let message):
                    return "❌ API: \(message.prefix(50))"
                case .notImplemented(let message):
                    return "❌ \(message)"
                }
            } else if let urlError = error as? URLError {
                // Handle network errors specifically
                switch urlError.code {
                case .notConnectedToInternet:
                    return "❌ No internet connection"
                case .timedOut:
                    return "❌ Request timed out"
                case .cannotFindHost:
                    return "❌ Cannot reach server"
                case .networkConnectionLost:
                    return "❌ Connection lost"
                default:
                    return "❌ Network: \(urlError.localizedDescription.prefix(50))"
                }
            } else if let decodingError = error as? DecodingError {
                return "❌ JSON decode error: \(String(describing: decodingError).prefix(80))"
            }
            return "❌ Error: \(error.localizedDescription.prefix(80))"
        } else {
            // Simple error for production
            if let llmError = error as? LLMError {
                return llmError.localizedDescription ?? "Error occurred"
            } else if let speechError = error as? SpeechError {
                return speechError.localizedDescription ?? "Error occurred"
            } else if error is URLError {
                return "Network error. Check connection."
            }
            return "Error: Retry"
        }
    }
    
    // MARK: - Debug Logging

    private func logDebug(_ message: String) {
        if debugMode {
            NSLog("🔍 [KeyboardVC] %@", message)
        }
    }

    private func updateMicButtonState(recording: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.micButton.backgroundColor = recording ? .systemRed : .systemBlue
            self.micButton.setImage(
                UIImage(systemName: recording ? "stop.fill" : "mic.fill"),
                for: .normal
            )
            self.micButton.transform = recording ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity
        }
    }

    // MARK: - Keyboard Actions

    @objc private func spaceButtonTapped() {
        textDocumentProxy.insertText(" ")
    }

    @objc private func backspaceButtonTapped() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func returnButtonTapped() {
        textDocumentProxy.insertText("\n")
    }

    @objc private func openHostApp() {
        guard let url = URL(string: "llmkeyboard://") else { return }

        // Keyboard extensions need to use this method to open URLs
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }

        logDebug("Failed to open host app")
    }

    // MARK: - Helpers

    override var hasFullAccess: Bool {
        // Proper way to check full access:
        // Try to access the pasteboard - this only works with Full Access
        guard let pasteboardItems = UIPasteboard.general.items.first else {
            // No items, try to detect by attempting to set/get
            let testValue = "test_\(UUID().uuidString)"
            UIPasteboard.general.string = testValue
            let hasAccess = UIPasteboard.general.string == testValue
            UIPasteboard.general.string = "" // Clean up
            return hasAccess
        }
        return true
    }
}
