import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showingAPIKeyAlert = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Keyboard Status
                Section {
                    NavigationLink {
                        KeyboardSetupGuideView()
                    } label: {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.blue)
                            Text("Keyboard Setup")
                            Spacer()
                            if settings.isKeyboardEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Text("Not Enabled")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Status")
                }

                // MARK: - Speech Recognition
                Section {
                    Picker("Provider", selection: $settings.speechProvider) {
                        ForEach(SpeechProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    if settings.speechProvider == .whisperAPI {
                        SecureField("OpenAI API Key", text: $settings.whisperAPIKey)
                            .textContentType(.password)
                    }

                    if settings.speechProvider == .whisperLocal {
                        Picker("Model Size", selection: $settings.whisperModelSize) {
                            ForEach(WhisperModelSize.allCases, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }

                        if settings.whisperModelDownloadProgress > 0 && settings.whisperModelDownloadProgress < 1 {
                            ProgressView(value: settings.whisperModelDownloadProgress) {
                                Text("Downloading model...")
                            }
                        }
                    }

                    Picker("Language", selection: $settings.speechLanguage) {
                        Text("Hungarian").tag("hu-HU")
                        Text("English").tag("en-US")
                        Text("Auto-detect").tag("auto")
                    }
                } header: {
                    Text("Speech Recognition")
                } footer: {
                    Text(settings.speechProvider.description)
                }

                // MARK: - Audio Engine Mode (Debug)
                Section {
                    Picker("Mode", selection: $settings.audioEngineMode) {
                        ForEach(AudioEngineMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text("Audio Engine Mode (Debug)")
                } footer: {
                    Text(settings.audioEngineMode.description)
                }

                // MARK: - LLM Service
                Section {
                    Picker("Service", selection: $settings.llmServiceType) {
                        ForEach(LLMServiceType.allCases, id: \.self) { service in
                            Text(service.displayName).tag(service)
                        }
                    }

                    if settings.llmServiceType == .custom {
                        TextField("Base URL", text: $settings.llmBaseURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }

                    SecureField("API Key", text: $settings.llmAPIKey)
                        .textContentType(.password)

                    TextField("Model Name", text: $settings.llmModelName)
                        .autocapitalization(.none)

                    Toggle("Enable Cleanup", isOn: $settings.enableLLMCleanup)
                } header: {
                    Text("LLM Text Cleanup")
                } footer: {
                    if settings.llmServiceType == .custom {
                        Text("Use OpenAI-compatible API endpoint")
                    } else {
                        Text("Uses \(settings.llmServiceType.displayName) API for text cleanup")
                    }
                }

                // MARK: - Cleanup Prompt
                if settings.enableLLMCleanup {
                    Section {
                        TextEditor(text: $settings.cleanupPrompt)
                            .frame(minHeight: 100)
                    } header: {
                        Text("Cleanup Prompt")
                    } footer: {
                        Text("The transcribed text will be appended to this prompt")
                    }
                }

                // MARK: - Test
                Section {
                    NavigationLink {
                        TestView()
                    } label: {
                        Label("Test Pipeline", systemImage: "mic.badge.plus")
                    }
                } header: {
                    Text("Testing")
                }
            }
            .navigationTitle("LLM Keyboard")
        }
    }
}

struct KeyboardSetupGuideView: View {
    var body: some View {
        List {
            // Quick action
            Section {
                Button {
                    openKeyboardSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.blue)
                            .cornerRadius(8)

                        VStack(alignment: .leading) {
                            Text("Open Keyboard Settings")
                                .font(.headline)
                            Text("Enable LLM Keyboard & Full Access")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                SetupStepView(number: 1, text: "Tap 'Open Keyboard Settings' above")
                SetupStepView(number: 2, text: "Tap 'Keyboards'")
                SetupStepView(number: 3, text: "Tap 'Add New Keyboard...'")
                SetupStepView(number: 4, text: "Select 'LLM Keyboard'")
                SetupStepView(number: 5, text: "Tap 'LLM Keyboard' in the list")
                SetupStepView(number: 6, text: "Enable 'Allow Full Access'", isImportant: true)
            } header: {
                Text("Setup Steps")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Why Full Access?", systemImage: "info.circle")
                        .font(.headline)

                    Text("Full Access is required for:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    BulletPoint("Sending audio to Whisper API")
                    BulletPoint("Sending text to Claude/OpenAI for cleanup")
                    BulletPoint("Sharing settings between app and keyboard")
                }
                .padding(.vertical, 4)
            } header: {
                Text("About Full Access")
            } footer: {
                Text("Your voice data is only sent to the APIs you configure. We don't collect any data.")
            }
        }
        .navigationTitle("Keyboard Setup")
    }

    private func openKeyboardSettings() {
        // Try to open keyboard settings directly (works on most iOS versions)
        if let url = URL(string: "App-Prefs:root=General&path=Keyboard") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        // Fallback to general settings
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct SetupStepView: View {
    let number: Int
    let text: String
    var isImportant: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(isImportant ? Color.orange : Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundColor(isImportant ? .orange : .primary)

            Spacer()
        }
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.blue)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct TestView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var speechManager = SpeechRecognitionManager()
    @State private var transcribedText = ""
    @State private var cleanedText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            // Recording button
            Button {
                if speechManager.isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(speechManager.isRecording ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)

                    Image(systemName: speechManager.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .disabled(isProcessing)

            if isProcessing {
                ProgressView("Processing...")
            }

            // Transcribed text
            GroupBox("Transcribed") {
                ScrollView {
                    Text(transcribedText.isEmpty ? "Tap the microphone to start recording" : transcribedText)
                        .foregroundColor(transcribedText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 100)
            }

            // Cleaned text
            if settings.enableLLMCleanup {
                GroupBox("Cleaned") {
                    ScrollView {
                        Text(cleanedText.isEmpty ? "Will appear after cleanup" : cleanedText)
                            .foregroundColor(cleanedText.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Test")
    }

    private func startRecording() {
        transcribedText = ""
        cleanedText = ""
        errorMessage = nil
        speechManager.startRecording()
    }

    private func stopRecording() {
        isProcessing = true

        Task {
            do {
                let transcription = try await speechManager.stopRecordingAndTranscribe()
                await MainActor.run {
                    transcribedText = transcription
                }

                if settings.enableLLMCleanup {
                    let cleaned = try await LLMService.shared.cleanup(text: transcription)
                    await MainActor.run {
                        cleanedText = cleaned
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isProcessing = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
