# Keyboard Extension Audio Recording Problem

## A probléma

- **Keyboard extension** audio felvétel + Apple Speech Recognition
- **Fresh install után**: működik
- **Többszöri felvétel**: működik (engine reuse-zal)
- **Process kill után**: `engine.start()` → "The operation couldn't be completed"
- **Csak reinstall segít**

## Amit kipróbáltunk

- AVAudioRecorder → AVAudioEngine
- Audio session kategóriák: `.playAndRecord`, `.record`
- Audio session módok: `.measurement`, `.default`
- Session reset (deactivate/activate)
- Delay-ek, retry-ok
- Zombie engine cleanup

## A rejtély

```
Fresh install → új process → új engine → engine.start() → ✅ MŰKÖDIK
Process kill  → új process → új engine → engine.start() → ❌ SIKERTELEN
```

Mindkét esetben `4e0s0r0` (nincs engine), mindkét esetben `4N` (új engine) - mégis különböző eredmény.

## Lehetséges okok

1. **coreaudiod (iOS audio daemon)** - Rendszerszintű audio szolgáltatás, ami "emlékszik" az előző session-re. A mi process-ünk újraindul, de a daemon nem.

2. **Stale audio route** - Az iOS azt hiszi, hogy van egy aktív audio útvonal az előző session-ből.

3. **SFSpeechRecognizer daemon** - A speech recognition is külön daemon-ban fut, lehet ott ragadt valami.

## Új megközelítések

### 1. Próbáljuk engine.start()-ot TAP NÉLKÜL

Hátha a tap install a probléma:

```swift
let engine = AVAudioEngine()
engine.prepare()
try engine.start()  // Működik-e tap nélkül?
```

### 2. SFSpeechAudioBufferRecognitionRequest

Közvetlenül stream-elni az audio-t a speech recognizer-be, fájl nélkül. Ez az Apple által javasolt módszer.

### 3. AudioUnit reset

Alacsonyabb szintű audio reset.

## Build history

- B20-B25: AVAudioEngine bevezetése, debug logging
- B26: Audio session deactivate eltávolítása transcription után → **többszöri felvétel működik**
- B27-B31: Process kill utáni hiba debug, különböző session config-ok → **nem segített**
