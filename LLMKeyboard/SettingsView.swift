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
            Section {
                Text("1. Open Settings app")
                Text("2. Go to General → Keyboard → Keyboards")
                Text("3. Tap 'Add New Keyboard...'")
                Text("4. Select 'LLM Keyboard'")
                Text("5. Tap 'LLM Keyboard' and enable 'Allow Full Access'")
            } header: {
                Text("Setup Instructions")
            } footer: {
                Text("Full Access is required for network requests to speech recognition and LLM services.")
            }

            Section {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle("Keyboard Setup")
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
