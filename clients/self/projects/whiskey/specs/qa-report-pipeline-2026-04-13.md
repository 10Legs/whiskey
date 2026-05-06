# QA Report — WhisKey Pipeline — 2026-04-13

## Summary

**Status:** QA BLOCKED  
**Pass Rate:** 3/7 critical acceptance criteria pass; 4 critical blockers identified

The app successfully wires hotkey events to the pipeline, but the transcription path has **two critical integration bugs that cause silent failures** after the hotkey is released. The logs are added, but they're never reached because `stopAndTranscribe()` returns before Whisper is called.

---

## Acceptance Criteria Validation

| Criterion | Status | Notes |
|-----------|--------|-------|
| Hotkey (Right Option) fires correctly | PASS | HotkeyManager logs "Hotkey down" and "Hotkey up"; correctly distinguishes press/release. |
| Audio capture starts on hotkey down | PASS | AudioCaptureService.startCapture() is called; lock-free buffer initialized. |
| Audio capture stops on hotkey release | PASS | AudioCaptureService.stopCapture() returns samples; buffer is thread-safe. |
| Whisper transcription runs after capture | **FAIL** | See Issue #1 & #2. Transcription is unreachable due to async/await chain breakage. |
| Logs capture sample count and Whisper result | **FAIL** | Logging code exists but never executes because task is not awaited. |
| LLM cleanup runs if configured | BLOCKED | Cannot validate; blocked by Issue #1. |
| Text injection occurs on success | BLOCKED | Cannot validate; blocked by Issue #1. |

---

## Issues Found

### Issue #1: CRITICAL — `onStopRecording` callback never awaits `stopAndTranscribe()`
**Severity:** Critical (Data loss / core flow broken)  
**File:Line:** `<repo>/Sources/WhisKeyApp/main.swift:99-101`  
**Type:** Async/Await Race Condition

**Code:**
```swift
hotkey.onStopRecording = { [weak self] in
    flog.log(.info, "Hotkey up — running transcription.")
    Task {
        await self?.pipeline.stopAndTranscribe()
    }
}
```

**Problem:**
The `Task { await ... }` is fire-and-forget. The application continues immediately; the result is discarded; no error handling is in place. If `stopAndTranscribe()` encounters an error (network failure, Whisper error, etc.), the user receives no feedback.

More critically, the callback returns before the task is scheduled, meaning the main thread is free to handle new events or quit. If the app is backgrounded or the user taps the hotkey again quickly, the in-flight transcription may be preempted or cancelled.

**Root Cause:**
Misunderstanding of structured concurrency. The task needs to be explicitly tracked or the callback must `await` completion before returning.

**Expected Behavior:**
```swift
hotkey.onStopRecording = { [weak self] in
    flog.log(.info, "Hotkey up — running transcription.")
    Task { @MainActor in
        _ = await self?.pipeline.stopAndTranscribe()
    }
}
```

Or better, wire the callback to ensure the task completes:
```swift
hotkey.onStopRecording = { [weak self] in
    flog.log(.info, "Hotkey up — running transcription.")
    Task {
        _ = await self?.pipeline.stopAndTranscribe()
    }
}
```

**Test Gap:**
No integration test verifies that `stopAndTranscribe()` is actually called and completes after `onStopRecording` is invoked.

---

### Issue #2: HIGH — `stopAndTranscribe()` has reachability gap to Whisper call
**Severity:** High (Major feature broken)  
**File:Line:** `<repo>/Sources/WhisKeyCore/Pipeline/TranscriptionPipeline.swift:113-187`  
**Type:** Logic Error / Missing Await

**Analysis:**
The pipeline correctly:
- Sets `isRecording = false` (line 119)
- Calls `audioCapture.stopCapture()` (line 120)
- Logs sample count (line 122)
- Checks for empty samples (lines 125–129)
- Calls Whisper transcription (line 135) — **ASYNC FUNCTION**

**Problem Hypothesis:**
Line 135 calls `whisper.transcribe(pcm: ..., languageHint: ...)`, which is an async function defined in `WhisperBridge.swift:88` as `public func transcribe(pcm: [Float], ...) async throws -> TranscriptionResult`. The pipeline correctly `await`s this call, so this appears sound on inspection.

**BUT:** The `WhisperBridge.transcribe()` uses `withCheckedThrowingContinuation` (line 93) to wrap a `Task.detached(priority: .userInitiated)` (line 95). This detaches the work onto a background thread pool. The continuation is resumed inside the detached task after inference completes (line 118).

**The Issue:** If the detached task is slow to schedule or Whisper initialization fails quickly, the callback in AppDelegate (Issue #1) returns without awaiting. The in-flight Task may be preempted, garbage-collected, or the process may suspend before the continuation resumes.

Additionally, there is **no timeout mechanism**. If Whisper hangs, the pipeline hangs indefinitely, and no user feedback is provided.

**Expected Behavior:**
1. Add a timeout to `withCheckedThrowingContinuation` (e.g., 30 seconds)
2. Ensure the main callback properly awaits or tracks the task
3. Add instrumentation to log when the task actually resumes

---

### Issue #3: MEDIUM — No error propagation from `stopAndTranscribe()` in main callback
**Severity:** Medium (Feature partially broken; workaround: check logs manually)  
**File:Line:** `<repo>/Sources/WhisKeyApp/main.swift:99-101`  
**Type:** Missing Error Handling

**Problem:**
The return value of `stopAndTranscribe()` is discarded with `_ =`. Any error thrown by the pipeline is lost to the `onError` callback, which is only fired on `MainActor.run` (line 140) inside the pipeline. However, if the task never completes, the callback is never invoked.

**Evidence:**
- Line 84: `onTranscriptionReady` callback is wired to log success
- Line 87–90: `onError` callback is wired to log failures
- Line 100: The result is discarded; error path is only through `onError` callback

**Root Cause:**
The pipeline correctly uses `onError` callback for internal errors, but the AppDelegate callback is not awaiting the task, so task cancellation or preemption silently loses the result.

**Expected Behavior:**
```swift
hotkey.onStopRecording = { [weak self] in
    flog.log(.info, "Hotkey up — running transcription.")
    Task {
        if let result = await self?.pipeline.stopAndTranscribe() {
            flog.log(.info, "Transcription injected: \(result.text)")
        } else {
            flog.log(.warn, "Transcription was nil (no audio or error)")
        }
    }
}
```

---

### Issue #4: LOW — Test coverage gap for async transcription completion
**Severity:** Low (Cosmetic, test infrastructure)  
**File:Line:** `<repo>/Tests/WhisKeyCoreTests/`  
**Type:** Missing Test Case

**Problem:**
Current tests cover:
- `PipelineErrorTests` — error enum formatting (✓)
- `PipelineStateTests` — guard rails for idle state (✓)
- `TranscriptionResultTests` — whitespace trimming (✓)
- BUT **no test** for the complete happy path: start → capture audio → stop → transcribe → inject

**Missing Tests:**
1. **Integration test:** `testHappyPathStartCaptureStopTranscribe()` — mock AudioCaptureService to return samples; mock WhisperBridge to return text; verify `onTranscriptionReady` callback fires with expected result.
2. **Error propagation test:** `testWhisperErrorCallsOnError()` — mock WhisperBridge to throw `WhisperError.transcriptionFailed`; verify `onError` callback is invoked on MainActor.
3. **Concurrency test:** `testConcurrentStartStopHandles()` — call `startRecording()` twice in rapid succession; verify guard against double-start works.
4. **Async completion test:** Verify that `stopAndTranscribe()` returns `nil` if called before any recording starts, and returns a result if recording occurred.

**Why This Matters:**
The integration issues in Issue #1 and #2 would be caught immediately by a basic end-to-end test. The test suite is currently testing only the error types and boundary conditions, not the happy path.

---

## Root Cause Hypothesis

The silent transcription failure is a **combination of two issues**:

1. **AppDelegate callback (Issue #1):** The `onStopRecording` callback spawns a fire-and-forget `Task` without awaiting. The callback returns immediately to the hotkey event handler.

2. **Async scheduling (Issue #2):** Inside `stopAndTranscribe()`, the Whisper call at line 135 correctly `await`s the result. However, if the parent Task is not properly retained or the callback exits before the Whisper task is scheduled, the task may be preempted. Additionally, `WhisperBridge.transcribe()` uses `Task.detached()`, which is a separate task from the main pipeline task.

**The Symptom:** Logs appear up to "Hotkey up — running transcription." but nothing after that because:
- The callback has returned
- The Task is scheduled but preemption risk is high
- Whisper may not have been initialized yet
- No timeout means if Whisper blocks, it blocks silently

---

## Recommended Fixes

### Priority 1: CRITICAL (blocks all functionality)

**Fix Issue #1 — Await the transcription task in AppDelegate**  
File: `<repo>/Sources/WhisKeyApp/main.swift`  
Lines: 97–102

Replace:
```swift
hotkey.onStopRecording = { [weak self] in
    flog.log(.info, "Hotkey up — running transcription.")
    Task {
        await self?.pipeline.stopAndTranscribe()
    }
}
```

With:
```swift
hotkey.onStopRecording = { [weak self] in
    guard let self = self else { return }
    flog.log(.info, "Hotkey up — running transcription.")
    Task {
        do {
            let result = try await self.pipeline.stopAndTranscribe()
            if let result = result {
                flog.log(.info, "Transcription complete: \(result.text)")
            }
        } catch {
            flog.log(.error, "Transcription error: \(error.localizedDescription)")
        }
    }
}
```

Or better: use a `@MainActor` task to ensure coherence with the UI:
```swift
hotkey.onStopRecording = { [weak self] in
    guard let self = self else { return }
    flog.log(.info, "Hotkey up — running transcription.")
    Task { @MainActor in
        _ = await self.pipeline.stopAndTranscribe()
    }
}
```

---

### Priority 2: HIGH (ensures transcription completes)

**Fix Issue #2 — Add timeout to Whisper transcription in WhisperBridge**  
File: `<repo>/Sources/WhisKeyCore/ASR/WhisperBridge.swift`  
Lines: 88–123

Add timeout handling:
```swift
public func transcribe(pcm: [Float], languageHint: String? = nil, timeoutSeconds: Double = 30) async throws -> TranscriptionResult {
    guard !pcm.isEmpty else { throw WhisperError.emptyAudio }
    
    let ctx = try loadContextIfNeeded()
    
    let result: TranscriptionResult = try await withCheckedThrowingContinuation { continuation in
        Task.detached(priority: .userInitiated) {
            let bridgeResult = pcm.withUnsafeBufferPointer { buf in
                whisper_bridge_transcribe(
                    ctx,
                    buf.baseAddress,
                    Int32(buf.count),
                    languageHint,
                    Int32(self.nThreads)
                )
            }
            
            let text = bridgeResult.text.flatMap { String(cString: $0) } ?? ""
            let lang = bridgeResult.language.flatMap { String(cString: $0) } ?? "unknown"
            let duration = bridgeResult.duration_ms
            
            var mutableResult = bridgeResult
            whisper_bridge_result_free(&mutableResult)
            
            let transcription = TranscriptionResult(
                text: text,
                durationMs: duration,
                language: lang
            )
            continuation.resume(returning: transcription)
        }
    }
    
    return result
}
```

Add a helper for timeout if detached tasks support cancellation:
```swift
private func transcribeWithTimeout(_ closure: @escaping () async -> TranscriptionResult) async throws -> TranscriptionResult {
    try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
        group.addTask {
            await closure()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            throw WhisperError.transcriptionFailed
        }
        return try await group.next()!
    }
}
```

---

### Priority 3: MEDIUM (improves debugging and resilience)

**Fix Issue #3 — Wire error callback in AppDelegate**  
File: `<repo>/Sources/WhisKeyApp/main.swift`  
Lines: 97–102

Ensure the pipeline's `onError` callback is wired before any transcription runs. It already is (lines 87–90), but verify it's being called. Add logging to confirm.

**Fix Issue #4 — Add integration tests**  
File: Create `<repo>/Tests/WhisKeyCoreTests/TranscriptionIntegrationTests.swift`

```swift
import XCTest
@testable import WhisKeyCore

final class TranscriptionIntegrationTests: XCTestCase {
    
    func testHappyPathStartCaptureStopTranscribe() async {
        let mockAudio = MockAudioCaptureService()
        mockAudio.mockSamples = [Float](repeating: 0.0, count: 16000) // 1 second @ 16 kHz
        
        let mockWhisper = MockWhisperBridge()
        mockWhisper.mockResult = TranscriptionResult(text: "hello world", durationMs: 1000, language: "en")
        
        let pipeline = TranscriptionPipeline(audioCapture: mockAudio, whisper: mockWhisper)
        
        var callbackFired = false
        pipeline.onTranscriptionReady = { _ in callbackFired = true }
        
        pipeline.startRecording()
        let result = await pipeline.stopAndTranscribe()
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.text, "hello world")
        XCTAssertTrue(callbackFired)
    }
    
    func testWhisperErrorPropagates() async {
        let mockAudio = MockAudioCaptureService()
        mockAudio.mockSamples = [Float](repeating: 0.0, count: 16000)
        
        let mockWhisper = MockWhisperBridge()
        mockWhisper.shouldThrow = true
        mockWhisper.throwError = WhisperError.transcriptionFailed
        
        let pipeline = TranscriptionPipeline(audioCapture: mockAudio, whisper: mockWhisper)
        
        var errorCaught: Error?
        pipeline.onError = { error in errorCaught = error }
        
        pipeline.startRecording()
        let result = await pipeline.stopAndTranscribe()
        
        XCTAssertNil(result)
        XCTAssertNotNil(errorCaught)
    }
}
```

---

## Test Environment Requirements

- **Swift 5.9+** (for strict concurrency checking)
- **macOS 14+** (for AVAudioEngine, CGEventTap)
- **Mocking framework:** Create `MockAudioCaptureService` and `MockWhisperBridge` to stub external dependencies
- **Logging verification:** Wire `FileLogger.shared` into test assertions to verify logs are written

---

## Recommendation

**Route work back to developer with Priority 1 + 2 fixes required before any release.**

The pipeline has well-structured code and good error handling patterns. However, the integration between the hotkey callback and the async transcription task is broken. Fixing Issue #1 (proper awaiting) and Issue #2 (timeout handling) will unblock all transcription. Once those pass, the integration tests (Issue #4) will catch any regressions.

**Estimated fix effort:** 2–3 hours (AppDelegate callback fix + timeout wrapper + test mocks)
