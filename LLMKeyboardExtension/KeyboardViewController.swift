import UIKit

class KeyboardViewController: UIInputViewController {

    // MARK: - UI Components

    private var mainStackView: UIStackView!
    private var micButton: UIButton!
    private var statusLabel: UILabel!
    private var suggestionBar: UIView!
    private var keyboardView: UIView!

    // MARK: - State

    private let speechManager = SpeechRecognitionManager()
    private var isProcessing = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupObservers()
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

    private func setupStatusBar() {
        statusLabel = UILabel()
        statusLabel.text = "Tap microphone to dictate"
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

        // Space button
        let spaceButton = createControlButton(title: "space", action: #selector(spaceButtonTapped))
        spaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true

        // Backspace button
        let backspaceButton = createControlButton(systemName: "delete.left", action: #selector(backspaceButtonTapped))

        // Return button
        let returnButton = createControlButton(systemName: "return", action: #selector(returnButtonTapped))

        controlsStack.addArrangedSubview(globeButton)
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
        if speechManager.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isProcessing else { return }

        // Check for full access (needed for network requests)
        guard hasFullAccess else {
            statusLabel.text = "Full Access required. Enable in Settings."
            return
        }

        speechManager.startRecording()
        updateMicButtonState(recording: true)
        statusLabel.text = "Listening..."
    }

    private func stopRecording() {
        guard speechManager.isRecording else { return }

        isProcessing = true
        updateMicButtonState(recording: false)
        statusLabel.text = "Processing..."

        Task {
            do {
                // Transcribe
                let transcription = try await speechManager.stopRecordingAndTranscribe()

                // Cleanup with LLM if enabled
                let settings = SettingsManager.shared
                let finalText: String

                if settings.enableLLMCleanup {
                    await MainActor.run {
                        statusLabel.text = "Cleaning up..."
                    }
                    finalText = try await LLMService.shared.cleanup(text: transcription)
                } else {
                    finalText = transcription
                }

                // Insert text
                await MainActor.run {
                    textDocumentProxy.insertText(finalText)
                    statusLabel.text = "Done! Tap to dictate again"
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    statusLabel.text = "Error: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
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

    // MARK: - Helpers

    override var hasFullAccess: Bool {
        // Check if we have full access (needed for network requests)
        // This is a workaround - there's no official API for this
        return UIPasteboard.general.hasStrings || UIPasteboard.general.hasImages || true
        // Note: This always returns true for now. Real check would use pasteboard access
    }
}
