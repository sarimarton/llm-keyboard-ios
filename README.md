# LLM Keyboard for iOS

Voice dictation keyboard with LLM-powered text cleanup for iOS. Designed for Hungarian + English mixed language dictation.

## Motivation

Traditional speech recognition (including Whisper) struggles with code-switching between languages - especially Hungarian mixed with English technical terms. This keyboard solves the problem by:

1. **Recording** speech directly in any app
2. **Transcribing** using multiple speech recognition backends
3. **Cleaning up** the transcription with an LLM (Claude, OpenAI, or custom endpoint)
4. **Inserting** the cleaned text directly into the current input field

## Features

### Speech Recognition Providers

| Provider | Pros | Cons |
|----------|------|------|
| **Apple Speech** | Free, on-device, no API key needed | Mixed language support varies |
| **Whisper API** | Good for mixed language (large-v3) | Requires OpenAI API key, network |
| **Whisper Local** | Best quality, fully offline | Large model download, battery usage |

### LLM Services

Supports OpenAI-compatible API schema with presets for:

- **Claude (Anthropic)** - Excellent for Hungarian, great at understanding context
- **OpenAI (GPT-4o)** - Fast, good quality
- **Custom endpoint** - Any OpenAI-compatible API (local LLMs, proxies, etc.)

Configuration uses OpenAI-compatible fields:
- `Base URL` (known for presets, custom for others)
- `API Key`
- `Model Name`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Main App (Settings)                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  - Configure speech recognition provider                │ │
│  │  - Configure LLM service (Claude/OpenAI/Custom)         │ │
│  │  - Customize cleanup prompt                             │ │
│  │  - Test pipeline before using in keyboard               │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                    App Group (shared container)
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Keyboard Extension                        │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  1. User taps mic button                                │ │
│  │  2. Records audio                                       │ │
│  │  3. Transcribes (Apple/Whisper API/Local)               │ │
│  │  4. Sends to LLM for cleanup (if enabled)               │ │
│  │  5. Inserts result into text field                      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### Why Keyboard Extension (not standalone app)?

- **Direct insertion**: No copy/paste needed, text goes straight into any input field
- **Universal**: Works in any app (Messages, Notes, Email, etc.)
- **Faster workflow**: Single tap to dictate, result appears immediately

Trade-off: Keyboard extensions have sandbox restrictions and require "Full Access" for network requests.

### Why App Group?

Settings configured in the main app need to be accessible from the keyboard extension. iOS uses separate containers for apps and extensions, so we use App Group (`group.com.llmkeyboard.shared`) to share UserDefaults.

### Why OpenAI-compatible API schema?

Most LLM providers (Claude via proxy, Ollama, LM Studio, vLLM, etc.) support OpenAI's chat completions format. Using this as our base format means:
- Easy switching between providers
- Support for local LLMs
- Custom proxy servers (like the user's existing Mac setup)

### Claude API Exception

Claude's API is different from OpenAI's format, so we have special handling:
- Different endpoint (`/messages` vs `/chat/completions`)
- Different auth header (`x-api-key` vs `Authorization: Bearer`)
- Different response format

## Project Structure

```
llm-keyboard-ios/
├── LLMKeyboard/                    # Main iOS app
│   ├── LLMKeyboardApp.swift        # App entry point
│   ├── SettingsView.swift          # Settings UI
│   ├── Info.plist
│   └── LLMKeyboard.entitlements
│
├── LLMKeyboardExtension/           # Keyboard extension
│   ├── KeyboardViewController.swift # Keyboard UI & logic
│   ├── Info.plist
│   └── LLMKeyboardExtension.entitlements
│
├── Shared/                         # Shared code
│   └── Sources/
│       ├── SettingsManager.swift   # UserDefaults wrapper with App Group
│       ├── SpeechRecognitionManager.swift  # Speech recognition abstraction
│       └── LLMService.swift        # LLM API client
│
└── LLMKeyboard.xcodeproj/          # Xcode project
```

## Setup

### Prerequisites

- Xcode 15+
- iOS 16+ device (simulator doesn't support custom keyboards well)
- Apple Developer account (for device testing)

### Build & Run

1. Open `LLMKeyboard.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Update bundle identifiers if needed
4. Build and run on your device

### Enable Keyboard

1. Open Settings → General → Keyboard → Keyboards
2. Tap "Add New Keyboard..."
3. Select "LLM Keyboard"
4. Tap "LLM Keyboard" → Enable "Allow Full Access"

### Configure

1. Open the LLM Keyboard app
2. Set up speech recognition provider
3. Add your API key (Claude or OpenAI)
4. Customize the cleanup prompt if needed
5. Test with the built-in test view

## Cleanup Prompt

The default cleanup prompt is designed for dictation cleanup:

```
You are a dictation cleanup assistant. Your task is to clean up transcribed
speech while preserving the original meaning and intent.

Rules:
- Fix obvious transcription errors
- Add proper punctuation and capitalization
- Keep the original language (Hungarian, English, or mixed)
- Do not add, remove, or change the meaning
- Do not add explanations or commentary
- Return ONLY the cleaned text, nothing else

Transcribed text:
```

You can customize this in settings - useful for:
- Different writing styles
- Specific formatting requirements
- Domain-specific terminology

## Future Improvements

- [ ] **WhisperKit integration** - On-device Whisper models (currently placeholder)
- [ ] **Audio level visualization** - Show recording levels in keyboard UI
- [ ] **Multiple language hints** - Tell Whisper about expected languages
- [ ] **Streaming transcription** - Show partial results as you speak
- [ ] **Keyboard themes** - Light/dark, custom colors
- [ ] **Haptic feedback** - Vibration on start/stop recording

## Troubleshooting

### "Full Access required" message
The keyboard needs network access for API calls. Enable in Settings → Keyboards → LLM Keyboard → Allow Full Access.

### API errors
Check your API key in the main app settings. Test the pipeline using the built-in test view before using in the keyboard.

### No sound / not recording
Make sure you've granted microphone permission. The keyboard should prompt on first use.

## License

MIT
