# WhisKey

> **Work in progress.** Core pipeline works — audio capture, ASR, text injection — but the app is not feature-complete or polished. Expect rough edges, missing UI, and breaking changes.

Local-first macOS voice transcription. Hold a hotkey, speak, release — transcribed text appears in whatever app has focus. No cloud, no subscription, no data leaves the machine.

**Requirements:** macOS 14+, Xcode 16, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Features

### Core
- **Hotkey-driven transcription** — Press a key, speak, release — text appears in the focused window
- **Offline ASR** — Whisper.cpp inference (no cloud API calls)
- **LLM cleanup** — Optional post-processing with phi-3.5-mini or llama-3.2-1b
- **Three injection modes** — AccessibilityAPI, Pasteboard, or keystroke fallback

### Sprint 3
- **Network Activity Monitor** — Live egress audit log with timestamp, URL, and event type; menu bar dot badge (green/orange)
- **Hold-vs-Tap state machine** — Right Option >300ms = Push-to-Talk; double-tap within 300ms = Hands-Free toggle (configurable 250–500ms)
- **Voice Snippets** — Trigger-phrase text expansion with security blocks (password managers, terminals)
- **Multi-hotkey bindings** — Four configurable hotkey actions with live key capture and conflict detection
- **Transcription history** — SQLite database with raw transcript, cleaned text, source app, timestamp

---

## How It Works

### Pipeline

```
Right Option (hold) ──► AudioCaptureService
                               │ AVAudioEngine tap → resample to 16 kHz mono Float32
                               ▼
Right Option (release) ──► WhisperBridge
                               │ whisper.cpp inference (CGGML + CWhisper)
                               ▼
                         LlamaCppProvider  (optional)
                               │ llama.cpp cleanup pass (CGGML + CLlama)
                               ▼
                         TextInjector
                               │ 1. AX direct write (no clipboard clobber)
                               │ 2. Pasteboard + simulated Cmd-V (restores prior clipboard)
                               │ 3. CGEvent keyboard simulation (character-by-character fallback)
                               ▼
                         Focused window receives text
```

### Module Layout

| Module | Language | Role |
|--------|----------|------|
| `CGGML` | C/C++ | Shared ggml runtime — Metal, Accelerate, CPU kernels. Linked once to avoid duplicate symbol errors. |
| `CWhisper` | C/C++ | whisper.cpp ASR — depends on CGGML. |
| `CLlama` | C/C++ | llama.cpp LLM inference — depends on CGGML. |
| `WhisKeyCore` | Swift | Business logic: pipeline, audio capture, ASR bridge, LLM provider, injection, history, settings. |
| `WhisKeyUI` | Swift/SwiftUI | Menu bar, floating HUD, settings, model picker. |
| `WhisKeyApp` | Swift | Entry point — wires pipeline, hotkey, and UI. |

### Key Components

**`AudioCaptureService`** — installs an `AVAudioEngine` tap on the input node, converts native device format to 16 kHz / mono / Float32 using `AVAudioConverter`, accumulates samples in a lock-protected buffer, and publishes normalized RMS for the HUD waveform.

**`WhisperBridge`** — Swift `actor` wrapping the `CWhisper` C bridge. Loads the GGML model lazily from `~/Library/Application Support/WhisKey/Models/`. Runs inference on a `DispatchQueue.global` continuation with a 30-second timeout task racing the inference task.

**`LlamaCppProvider`** — Swift `actor` wrapping the `CLlama` C bridge. Loads a GGUF model lazily from the same Models directory. Builds a cleanup prompt from `CleanupProfile` (filler removal, punctuation, tone style) and calls `llama_bridge_complete`. Silently passes through raw transcript if the model file is absent.

**`TextInjector`** — Tries three injection strategies in order: (1) `AXInjector` sets `kAXValueAttribute` directly on the captured `AXUIElement` — no clipboard involved; (2) `PasteboardInjector` writes to `NSPasteboard`, posts `Cmd-V`, then restores prior contents; (3) `CGEventInjector` synthesizes individual keystrokes for apps that reject both.

**`HotkeyManager`** — `CGEventTap` at `.cgSessionEventTap`. Default hotkey: Right Option (`0x3D`). Supports push-to-talk (hold/release) and toggle (press/press) modes.

**`TranscriptionPipeline`** — Async orchestrator. Snapshots the focused `AXUIElement` immediately on hotkey release (before transcription latency causes focus to shift), runs ASR, optionally runs LLM cleanup, dispatches output, and persists history to SQLite via GRDB.

### Output Modes

| Mode | Behavior |
|------|----------|
| `activeWindow` | Inject into focused app |
| `clipboard` | Write to clipboard only |
| `both` | Inject + write to clipboard |

### LLM Cleanup

When `llmEnabled` is on, the pipeline applies a `CleanupProfile` post-pass:

- **Remove fillers** — strips "um", "uh", "like", "you know", etc.
- **Add punctuation** — capitalizes sentences, adds periods/commas
- **Tone style** — `casual`, `formal`, `literal` (passthrough), or context-inferred from the active app bundle ID
- **Raw mode** — bypass LLM entirely regardless of other settings

Default model: `phi-3.5-mini-q4_k_m.gguf`. Falls back to passthrough if the GGUF file is absent.

---

## Building

### 1. Install tools

```bash
brew install xcodegen
```

### 2. Clone and generate the Xcode project

```bash
git clone <repo-url>
cd whiskey
xcodegen generate
```

### 3. Download models

```bash
# Whisper ASR (required)
bash Scripts/download-models.sh tiny      # ~75 MB — default
bash Scripts/download-models.sh base      # ~142 MB
bash Scripts/download-models.sh small     # ~466 MB
bash Scripts/download-models.sh medium    # ~1.5 GB

# LLM cleanup (optional — app works without it)
bash Scripts/download-models.sh phi-3.5-mini   # ~2.4 GB — recommended
bash Scripts/download-models.sh llama-3.2-1b   # ~0.8 GB — fastest
```

Models are saved to `~/Library/Application Support/WhisKey/Models/`.

### 4. Build and run

Open `WhisKey.xcodeproj` in Xcode, select the **WhisKey** scheme, and press `Cmd-R`.

The post-build script auto-installs the app to `~/Applications/WhisKey.app`.

#### SPM CLI build (no Xcode)

```bash
swift build -c release
```

Note: the Metal shader (`default.metallib`) is compiled by Xcode's pre-build script. Running via SPM CLI requires manually compiling and placing `default.metallib` in the same directory as the binary, or disabling Metal GPU offload.

---

## Permissions

On first launch, grant these when prompted:

| Permission | Why |
|------------|-----|
| **Microphone** | Audio capture |
| **Input Monitoring** | Global hotkey via `CGEventTap` |
| **Accessibility** | AX-based text injection into other apps |

To reset permissions:

```bash
bash Scripts/reset-permissions.sh
```

---

## Usage

1. Launch WhisKey — appears as a menu bar icon.
2. **Push-to-Talk:** Hold **Right Option** >300ms and speak — transcribed text types into the focused window.
3. **Hands-Free Toggle:** Double-tap **Right Option** within 300ms to toggle hands-free transcription mode (if enabled in Settings → Hotkey).
4. Accidental taps <80ms are silently discarded.

### Hotkey Interaction

The Right Option key disambiguates hold duration:
- **Hold >300ms** — Push-to-Talk transcription
- **Double-tap within 300ms** — Hands-Free toggle (when enabled)
- **Disambiguation window** — Configurable 250–500ms (default 300ms) in Settings → Hotkey

### Settings (menu bar → Settings)

| Setting | Tab | Options |
|---------|-----|---------|
| Whisper model | Transcription | tiny, base, small, medium, large |
| Language hint | Transcription | BCP-47 code, or blank for auto-detect |
| LLM cleanup | Transcription | On / Off |
| LLM model | Transcription | phi-3.5-mini, llama-3.2-1b |
| Tone style | Transcription | casual, formal, literal |
| Remove fillers | Transcription | On / Off |
| Add punctuation | Transcription | On / Off |
| Raw mode | Transcription | Bypass LLM regardless of other settings |
| Output mode | Transcription | Active window / Clipboard / Both |
| Notifications | Transcription | On / Off |
| Primary hotkey | Hotkeys | Key capture with conflict detection |
| Hands-Free toggle | Hotkeys | On / Off — enables Right Option double-tap |
| Disambiguation window | Hotkeys | 250–500ms slider (default 300ms) |
| Voice snippets | Snippets | Trigger phrase → expansion text mapping |
| Egress audit | Privacy | Live log of all outbound network calls |

### Transcription History

Every transcription is stored in SQLite (`~/Library/Application Support/WhisKey/history.db`) with the raw transcript, cleaned text, source app bundle ID, and timestamp. Viewable from the menu bar.

---

## Running Tests

```bash
swift test
# or in Xcode: Cmd-U
```

Tests target `WhisKeyCoreTests` and run against the host app binary (`WhisKey.app`).
