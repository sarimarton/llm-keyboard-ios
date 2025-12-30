import Foundation
import Combine
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: "com.sarimarton.llmkeyboard", category: "Settings")

// MARK: - Enums

enum SpeechProvider: String, CaseIterable, Codable {
    case apple = "apple"
    case whisperAPI = "whisper_api"
    case whisperLocal = "whisper_local"

    var displayName: String {
        switch self {
        case .apple: return "Apple Speech"
        case .whisperAPI: return "Whisper API"
        case .whisperLocal: return "Whisper Local"
        }
    }

    var description: String {
        switch self {
        case .apple:
            return "Uses iOS native speech recognition. Free, on-device, good for Hungarian."
        case .whisperAPI:
            return "Uses OpenAI Whisper API. Better for mixed language (Hungarian + English). Requires API key."
        case .whisperLocal:
            return "Uses on-device Whisper model. Best quality, no network needed, but uses more storage."
        }
    }
}

enum AudioEngineMode: String, CaseIterable, Codable {
    case tapFirst = "tap_first"
    case startFirst = "start_first"
    case streaming = "streaming"
    case noTapDiag = "no_tap_diag"

    var modeLabel: String {
        switch self {
        case .tapFirst: return "A"
        case .startFirst: return "B"
        case .streaming: return "C"
        case .noTapDiag: return "D"
        }
    }

    var displayName: String {
        switch self {
        case .tapFirst: return "A: Tap First (current)"
        case .startFirst: return "B: Start First"
        case .streaming: return "C: Streaming"
        case .noTapDiag: return "D: No Tap (diag)"
        }
    }

    var description: String {
        switch self {
        case .tapFirst: return "Install tap, then start engine"
        case .startFirst: return "Start engine, then install tap"
        case .streaming: return "Stream directly to SFSpeech"
        case .noTapDiag: return "Just start engine, no recording"
        }
    }
}

enum WhisperModelSize: String, CaseIterable, Codable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~75MB)"
        case .base: return "Base (~150MB)"
        case .small: return "Small (~500MB)"
        case .medium: return "Medium (~1.5GB)"
        case .large: return "Large (~3GB)"
        }
    }
}

enum LLMServiceType: String, CaseIterable, Codable {
    case claude = "claude"
    case openai = "openai"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "OpenAI"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o"
        case .custom: return ""
        }
    }
}

// MARK: - Settings Manager

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults: UserDefaults
    private let appGroupID = "group.com.sarimarton.llmkeyboard.share"

    // MARK: - Published Properties

    // Speech Recognition
    @Published var speechProvider: SpeechProvider {
        didSet { save(speechProvider.rawValue, forKey: .speechProvider) }
    }

    @Published var whisperAPIKey: String {
        didSet { save(whisperAPIKey, forKey: .whisperAPIKey) }
    }

    @Published var whisperModelSize: WhisperModelSize {
        didSet { save(whisperModelSize.rawValue, forKey: .whisperModelSize) }
    }

    @Published var whisperModelDownloadProgress: Double = 0

    @Published var speechLanguage: String {
        didSet { save(speechLanguage, forKey: .speechLanguage) }
    }

    @Published var audioEngineMode: AudioEngineMode {
        didSet { save(audioEngineMode.rawValue, forKey: .audioEngineMode) }
    }

    // LLM Service
    @Published var llmServiceType: LLMServiceType {
        didSet {
            save(llmServiceType.rawValue, forKey: .llmServiceType)
            // Update base URL and model when switching presets
            if llmServiceType != .custom {
                llmBaseURL = llmServiceType.defaultBaseURL
                if llmModelName.isEmpty || oldValue != .custom {
                    llmModelName = llmServiceType.defaultModel
                }
            }
        }
    }

    @Published var llmBaseURL: String {
        didSet { save(llmBaseURL, forKey: .llmBaseURL) }
    }

    @Published var llmAPIKey: String {
        didSet { save(llmAPIKey, forKey: .llmAPIKey) }
    }

    @Published var llmModelName: String {
        didSet { save(llmModelName, forKey: .llmModelName) }
    }

    @Published var enableLLMCleanup: Bool {
        didSet { save(enableLLMCleanup, forKey: .enableLLMCleanup) }
    }

    @Published var cleanupPrompt: String {
        didSet { save(cleanupPrompt, forKey: .cleanupPrompt) }
    }

    // Keyboard Status
    @Published var isKeyboardEnabled: Bool = false

    // MARK: - Keys

    private enum Key: String {
        case speechProvider
        case whisperAPIKey
        case whisperModelSize
        case speechLanguage
        case audioEngineMode
        case llmServiceType
        case llmBaseURL
        case llmAPIKey
        case llmModelName
        case enableLLMCleanup
        case cleanupPrompt
    }

    // MARK: - Init

    private init() {
        // Try to use App Group defaults, fallback to standard
        if let groupDefaults = UserDefaults(suiteName: appGroupID) {
            defaults = groupDefaults
            NSLog("✅ [Settings] Using App Group: %@", appGroupID)
        } else {
            defaults = .standard
            NSLog("⚠️ [Settings] App Group failed, using standard UserDefaults")
        }

        // Force synchronize to ensure container is initialized
        defaults.synchronize()

        // Load all settings
        speechProvider = SpeechProvider(rawValue: defaults.string(forKey: Key.speechProvider.rawValue) ?? "") ?? .apple
        whisperAPIKey = defaults.string(forKey: Key.whisperAPIKey.rawValue) ?? ""
        whisperModelSize = WhisperModelSize(rawValue: defaults.string(forKey: Key.whisperModelSize.rawValue) ?? "") ?? .base
        speechLanguage = defaults.string(forKey: Key.speechLanguage.rawValue) ?? "hu-HU"
        audioEngineMode = AudioEngineMode(rawValue: defaults.string(forKey: Key.audioEngineMode.rawValue) ?? "") ?? .tapFirst

        // TEST DEFAULTS - remove in production
        let testDefaults = true
        if testDefaults {
            llmServiceType = .custom
            llmBaseURL = "https://mba2020.taild008f3.ts.net/claude/v1"
            llmAPIKey = "dummy"
            llmModelName = "claude-sonnet-4-20250514"
        } else {
            llmServiceType = LLMServiceType(rawValue: defaults.string(forKey: Key.llmServiceType.rawValue) ?? "") ?? .claude
            llmBaseURL = defaults.string(forKey: Key.llmBaseURL.rawValue) ?? LLMServiceType.claude.defaultBaseURL
            llmAPIKey = defaults.string(forKey: Key.llmAPIKey.rawValue) ?? ""
            llmModelName = defaults.string(forKey: Key.llmModelName.rawValue) ?? LLMServiceType.claude.defaultModel
        }
        // Always load from user settings
        enableLLMCleanup = defaults.bool(forKey: Key.enableLLMCleanup.rawValue)
        cleanupPrompt = defaults.string(forKey: Key.cleanupPrompt.rawValue) ?? Self.defaultCleanupPrompt

        // Check if cleanup prompt is empty and set default
        if cleanupPrompt.isEmpty {
            cleanupPrompt = Self.defaultCleanupPrompt
        }

        // Check keyboard status
        checkKeyboardEnabled()
    }

    // MARK: - Default Cleanup Prompt

    static let defaultCleanupPrompt = """
    You are a dictation cleanup assistant. Your task is to clean up transcribed speech while preserving the original meaning and intent.

    Rules:
    - Fix obvious transcription errors
    - Add proper punctuation and capitalization
    - Keep the original language (Hungarian, English, or mixed)
    - Do not add, remove, or change the meaning
    - Do not add explanations or commentary
    - Return ONLY the cleaned text, nothing else

    Transcribed text:
    """

    // MARK: - Helpers

    private func save(_ value: Any?, forKey key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    func checkKeyboardEnabled() {
        #if canImport(UIKit)
        // Check if our keyboard extension is enabled
        // This is done by checking the enabled input modes
        let enabledModes = UITextInputMode.activeInputModes
        isKeyboardEnabled = enabledModes.contains { mode in
            mode.primaryLanguage?.contains("LLMKeyboard") ?? false
        }
        #else
        isKeyboardEnabled = false
        #endif
    }

    /// Re-read settings from UserDefaults (useful for keyboard extension to pick up changes from main app)
    func refresh() {
        defaults.synchronize()
        audioEngineMode = AudioEngineMode(rawValue: defaults.string(forKey: Key.audioEngineMode.rawValue) ?? "") ?? .tapFirst
    }
}
