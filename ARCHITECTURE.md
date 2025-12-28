# Architecture & Design Decisions

This document explains the key architectural decisions and trade-offs made in LLM Keyboard.

## Overview

LLM Keyboard is a dictation-focused iOS keyboard that pipes speech through an LLM for cleanup. The primary use case is Hungarian + English mixed-language dictation, where traditional speech recognition often fails.

## Core Problem

Speech recognition struggles with **code-switching** - when speakers mix languages mid-sentence:

```
"A useEffectet úgy kell használni, hogy a dependency array-be berakom a változókat"
```

Traditional ASR will often:
- Fail to recognize the English technical terms
- Produce nonsense phonetic matches
- Lose context between language switches

## Solution Architecture

### Pipeline

```
[Microphone] → [Audio Recording] → [Speech Recognition] → [LLM Cleanup] → [Text Insertion]
     1              2                     3                    4               5
```

1. **Audio Recording**: Standard iOS AVAudioRecorder, M4A format at 16kHz
2. **Speech Recognition**: Pluggable backend (Apple Speech / Whisper API / Local Whisper)
3. **LLM Cleanup**: Full-context review of transcription by Claude/GPT/custom
4. **Text Insertion**: Via UIInputViewController's textDocumentProxy

### Why Each Component?

#### Audio Recording (not streaming)
We record first, then process - not streaming. Reasons:
- Whisper API doesn't support streaming
- Apple Speech streaming is inconsistent for mixed languages
- LLM cleanup needs full context anyway
- Simpler implementation, fewer edge cases

#### Speech Recognition Abstraction
Three backends serve different needs:

| Backend | Use Case |
|---------|----------|
| Apple Speech | Quick notes, single-language, offline fallback |
| Whisper API | Best quality for mixed-language, cloud processing |
| Local Whisper | Maximum privacy, no latency for API calls |

The `SpeechRecognitionManager` abstracts these behind a common interface.

#### LLM Cleanup
This is the **key differentiator**. Raw transcription is never good enough for mixed-language. The LLM:
- Fixes obvious transcription errors ("react hook" → "React Hook")
- Adds punctuation and capitalization
- Preserves code-switching intent
- Handles domain-specific terminology

We use a simple prompt rather than fine-tuning because:
- Works across all LLM providers
- Easy to customize per user
- No training data needed
- Prompt can be updated without app update

## iOS-Specific Decisions

### Keyboard Extension vs Standalone App

We chose keyboard extension because:

| Factor | Keyboard Extension | Standalone App |
|--------|-------------------|----------------|
| Text insertion | Direct | Copy/paste |
| Works in any app | Yes | No |
| Network access | Requires Full Access | Always available |
| Sandbox | Restricted | Normal |
| Development | Complex | Simple |

The UX benefit of direct insertion outweighs the development complexity.

### App Group for Shared Settings

iOS apps and extensions run in separate containers. To share settings:

```
Main App                    Keyboard Extension
    │                              │
    └──── App Group Container ─────┘
          (UserDefaults)
```

We use `group.com.llmkeyboard.shared` to share:
- Selected speech provider
- API keys (securely stored)
- LLM service configuration
- Custom cleanup prompt

### Full Access Requirement

Keyboard extensions need "Full Access" (previously "Allow Full Access") to:
- Make network requests (for Whisper API and LLM calls)
- Access shared container (for settings)

This is a necessary trade-off. We:
- Clearly explain why it's needed
- Never collect or transmit user keystrokes
- Only send audio/text when user explicitly triggers dictation

## API Design

### OpenAI-Compatible Schema

We standardize on OpenAI's chat completions format:

```swift
struct LLMRequest {
    let model: String
    let messages: [Message]
    let maxTokens: Int
}
```

Benefits:
- Works with OpenAI, Ollama, LM Studio, vLLM, Anthropic proxies
- Users can point to local LLMs
- Familiar format for developers

### Claude Special Handling

Claude's API differs from OpenAI:
- Endpoint: `/messages` vs `/chat/completions`
- Auth: `x-api-key` header vs `Authorization: Bearer`
- Response: `content[0].text` vs `choices[0].message.content`

We detect Claude from the service type and use appropriate formatting.

## Settings Architecture

### SettingsManager Singleton

```swift
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var speechProvider: SpeechProvider
    @Published var llmServiceType: LLMServiceType
    // ... more settings
}
```

Why singleton:
- Settings need to be accessible from keyboard extension
- Single source of truth
- `@Published` enables SwiftUI reactivity in main app

### UserDefaults Keys

All settings use explicit string keys for clarity:

```swift
private enum Key: String {
    case speechProvider
    case whisperAPIKey
    case llmBaseURL
    // ...
}
```

## Security Considerations

### API Key Storage

Currently: API keys stored in UserDefaults (App Group shared)

Improvement path:
1. Move to Keychain for sensitive data
2. Keychain can be shared via Keychain Access Groups
3. More secure but more complex to implement

### Network Requests

All API calls use HTTPS. The cleanup prompt is designed to not include:
- Personal information
- App-specific context
- Anything beyond the transcribed text

### Audio Data

- Audio is recorded to temp directory
- Immediately deleted after transcription
- Never stored permanently
- Never sent to analytics

## Performance Considerations

### Memory

Keyboard extensions have strict memory limits (~30MB). We:
- Don't load large models into memory (local Whisper would be streamed)
- Release audio data immediately after use
- Avoid caching API responses

### Latency

Typical flow timing:
- Recording: User-controlled (3-30 seconds typical)
- Whisper API: 1-3 seconds
- LLM cleanup: 0.5-2 seconds
- Total processing: 2-5 seconds

Apple Speech is faster but lower quality for mixed language.

### Battery

Recording and network requests drain battery. Mitigations:
- Efficient audio format (M4A, 16kHz mono)
- No background processing
- No polling or persistent connections

## Future Architecture

### WhisperKit Integration

[WhisperKit](https://github.com/argmaxinc/WhisperKit) enables on-device Whisper:

```
Current: [Audio] → [Network] → [OpenAI Whisper API] → [Transcription]
Future:  [Audio] → [WhisperKit (on-device)] → [Transcription]
```

Benefits:
- No network latency for transcription
- Privacy (audio never leaves device)
- No API costs

Challenges:
- Model size (base: 150MB, large: 3GB)
- Initial download time
- Battery usage during inference

### Streaming Transcription

Future possibility:
```
[Audio Stream] → [Partial Transcription] → [Display] → [Final] → [LLM Cleanup]
```

Would provide real-time feedback but adds complexity.

### Multi-Model Support

Could support multiple LLMs simultaneously:
- Fast model for quick cleanup
- Powerful model for complex text
- User chooses based on context

## Testing Strategy

### Main App Testing
The TestView provides in-app testing of the full pipeline:
1. Records audio
2. Shows transcription
3. Shows cleaned text
4. Helps debug without switching keyboards

### Keyboard Extension Testing
Keyboard extensions are hard to debug. Strategies:
- Log to shared container, read from main app
- Use Xcode console attach to extension process
- Test core logic in main app first

## Conclusion

The architecture prioritizes:
1. **User experience**: Direct text insertion, minimal steps
2. **Flexibility**: Multiple ASR and LLM backends
3. **Privacy**: On-device options, minimal data transmission
4. **Simplicity**: Clear pipeline, maintainable code

Trade-offs accepted:
- Keyboard extension complexity for better UX
- Full Access requirement for network features
- Some latency for LLM cleanup quality
