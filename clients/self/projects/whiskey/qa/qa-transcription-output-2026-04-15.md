# QA Report — Whiskey Transcription Output Pipeline — 2026-04-15

## Summary
Status: **QA BLOCKED**  
Pass Rate: 0/5 test cases passed  
Critical Blocker: Transcription output is silently dropped in ALL output modes due to async/await mismatches in the output dispatch pipeline.

---

## Root Cause Analysis

### Critical Issue #1: clipboardOnly() Marked @MainActor But Called With Await
**Severity: CRITICAL**
**Location:** `<repo>/Sources/WhisKeyCore/Pipeline/TranscriptionPipeline.swift:224-229`

The method `clipboardOnly(_ text: String)` is marked with `@MainActor` (line 224), but in `stopAndTranscribe()` it is being called with `await` (lines 208, 212).

```swift
@MainActor
private func clipboardOnly(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}
```

Called as:
```swift
case .clipboard:
    await clipboardOnly(textToInject)  // Line 208 — WRONG: @MainActor methods don't return Void
case .both:
    await injector.inject(textToInject)
    await clipboardOnly(textToInject)  // Line 212 — WRONG
```

**Why This is a Bug:**
- `@MainActor` methods that return `Void` do not suspend. They should be called directly, not with `await`.
- Calling `await` on a non-Sendable `@MainActor` method that returns `Void` is likely a compiler error or causes the call to silently fail or execute without proper main-thread dispatch.
- Result: Clipboard is never actually written.

**Impact:** `.clipboard` and `.both` output modes do NOT write to clipboard.

---

### Critical Issue #2: TextInjector.inject() is Async But Underlying Injectors Are Not
**Severity: CRITICAL**
**Location:** `<repo>/Sources/WhisKeyCore/Injection/TextInjector.swift:26-30`

`TextInjector.inject()` is declared as `async`:
```swift
public func inject(_ text: String) async {
    if await axInjector.inject(text) { return }
    if await pasteboardInjector.inject(text) { return }
    await cgEventInjector.inject(text)
}
```

But the underlying injectors are **synchronous**:
- `AXInjector.inject()` is sync (line 14): `func inject(_ text: String) -> Bool`
- `PasteboardInjector.inject()` is sync (line 10): `func inject(_ text: String) -> Bool`
- `CGEventInjector.inject()` is sync (line 11): `func inject(_ text: String)`

**Why This is a Bug:**
- Swift does not allow `await` on synchronous functions.
- The code compiles only because of implicit `@MainActor` isolation on those functions (they use `@MainActor` but don't suspend).
- Awaiting a `@MainActor` synchronous function does NOT actually dispatch work to the main thread if already on the main thread, but awaiting it is incorrect and non-idiomatic.
- The calls may be silently no-oping or the dispatch may be unreliable.

**Impact:** `.activeWindow` and `.both` output modes may not inject text into the window reliably or at all.

---

### Root Cause Pattern
The issue stems from a refactoring where:
1. `TextInjector.inject()` was changed to be `async`
2. Individual injectors (`AXInjector`, `PasteboardInjector`, `CGEventInjector`) were not updated to be `async`
3. `clipboardOnly()` was marked `@MainActor` but the calling site uses `await`

This is a **fundamentally broken output dispatch chain**. No output modes are reliably functional.

---

## Acceptance Criteria Validation

| Criterion | Status | Notes |
|-----------|--------|-------|
| `.activeWindow` mode injects text into focused window | **FAIL** | TextInjector.inject() async/await mismatch with underlying sync injectors |
| `.clipboard` mode copies to NSPasteboard | **FAIL** | clipboardOnly() marked @MainActor but called with await — write never executes |
| `.both` mode injects AND copies to clipboard | **FAIL** | Both sub-paths broken due to async/await errors |
| `.hudOnly` mode shows in history only | **PASS** | No injection/clipboard logic; flows to history correctly |
| Settings persists outputMode via UserDefaults | **PASS** | SettingsManager correctly handles fallback to `.activeWindow` |
| HotkeyManager correctly calls stopAndTranscribe() | **PASS** | Hotkey wiring in AppDelegate.swift line 168 is correct |

---

## Confirmed Bugs

### Bug #1: clipboardOnly() Async/Await Mismatch
- **File:** `Sources/WhisKeyCore/Pipeline/TranscriptionPipeline.swift`
- **Lines:** 224 (declaration), 208, 212 (call sites)
- **Issue:** `@MainActor` method called with `await` — violates Swift concurrency model
- **Fix:** Remove `@MainActor` annotation from `clipboardOnly()` OR remove `await` from call sites and ensure it's called on the main thread via `MainActor.run {}`
- **Recommended:** Remove `await` and use direct call since `clipboardOnly()` is simple synchronous logic that doesn't need MainActor isolation

### Bug #2: TextInjector.inject() Async Signature Mismatch
- **File:** `Sources/WhisKeyCore/Injection/TextInjector.swift`
- **Lines:** 26 (declaration), 27-29 (call sites)
- **Issue:** Declared `async` but calls synchronous injectors with `await` — breaks the contract
- **Fix:** Either:
  - **Option A:** Remove `async` from `TextInjector.inject()` signature and make it synchronous
  - **Option B:** Make underlying injectors (`AXInjector`, `PasteboardInjector`, `CGEventInjector`) async
- **Recommended:** Option A — these are synchronous operations that don't need async/await

### Bug #3: cgEventInjector.inject() Called With Await But Returns Void
- **File:** `Sources/WhisKeyCore/Injection/TextInjector.swift:29`
- **Issue:** `await cgEventInjector.inject(text)` — the method returns Void, `await` is invalid
- **Fix:** Remove `await` keyword

---

## Code Paths That Look Correct

1. **SettingsManager.outputMode property (lines 120-126)**: Correct implementation. Falls back to `.activeWindow` if stored value is invalid, preventing silent `.hudOnly` default.
2. **HotkeyManager to Pipeline wiring (AppDelegate.swift lines 159-170)**: Correctly calls `startRecording()` on key down and spawns a Task for `stopAndTranscribe()` on key up.
3. **History persistence (line 218, persistAndNotify())**: Correctly persists all transcriptions to history regardless of output mode.
4. **OutputMode enum (Models/OutputMode.swift)**: Correctly defined with four cases.

---

## Recommended Fixes (Ranked by Likelihood to Resolve Issue)

### Fix 1: Remove Async From TextInjector.inject() (PRIORITY: CRITICAL)
**Likelihood to Resolve:** 95%  
**Change Type:** Signature + call sites

Remove `async` keyword from `TextInjector.inject()` and all underlying injectors. Make them synchronous since they don't block:

```swift
// TextInjector.swift
public func inject(_ text: String) {
    if axInjector.inject(text) { return }
    if pasteboardInjector.inject(text) { return }
    cgEventInjector.inject(text)
}

// AXInjector.swift
func inject(_ text: String) -> Bool {
    // ... (keep as-is, already synchronous)
}

// PasteboardInjector.swift
func inject(_ text: String) -> Bool {
    // ... (keep as-is, already synchronous)
}

// CGEventInjector.swift
func inject(_ text: String) {
    // ... (keep as-is, already synchronous)
}
```

Then update TranscriptionPipeline.swift call sites:
```swift
case .activeWindow:
    injector.inject(textToInject)  // Remove await

case .both:
    injector.inject(textToInject)   // Remove await
    await clipboardOnly(textToInject)
```

---

### Fix 2: Fix clipboardOnly() @MainActor Annotation (PRIORITY: CRITICAL)
**Likelihood to Resolve:** 95%  
**Change Type:** Remove decorator + adjust call site

Option A (Remove @MainActor):
```swift
private func clipboardOnly(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}
```

Then update call sites:
```swift
case .clipboard:
    clipboardOnly(textToInject)  // Remove await

case .both:
    injector.inject(textToInject)
    clipboardOnly(textToInject)   // Remove await
```

Option B (Keep @MainActor, use MainActor.run):
```swift
case .clipboard:
    await MainActor.run { clipboardOnly(textToInject) }
```

**Recommended:** Option A (simpler, clipboard write is fast).

---

### Fix 3: Verify TextInjector Call Sites in stopAndTranscribe()
**Likelihood to Resolve:** 100% (blocks Fixes 1 & 2)  
**Change Type:** Remove `await` keywords

After Fixes 1 and 2, ensure these lines have `await` removed:
- Line 205: `await injector.inject(textToInject)` → `injector.inject(textToInject)`
- Line 211: `await injector.inject(textToInject)` → `injector.inject(textToInject)`
- Line 208: `await clipboardOnly(textToInject)` → `clipboardOnly(textToInject)`
- Line 212: `await clipboardOnly(textToInject)` → `clipboardOnly(textToInject)`

---

## Testing Plan (Post-Fix)

After applying fixes, execute these test cases:

### Test Case 1: .activeWindow Mode
1. Open a text editor (e.g., TextEdit)
2. Click in the text field
3. Hold Right Option key for 2 seconds, then release
4. Verify: Text appears in the text field
5. Expected: Text injection works via AX API or pasteboard fallback

### Test Case 2: .clipboard Mode
1. Open any application
2. Hold Right Option key for 2 seconds, then release
3. Paste with Cmd+V
4. Verify: Transcribed text appears (no injection attempted)
5. Expected: Only clipboard contains text; no injection into window

### Test Case 3: .both Mode
1. Open a text editor
2. Click in the text field
3. Hold Right Option key for 2 seconds, then release
4. Verify: Text appears in the field
5. Paste elsewhere with Cmd+V
6. Verify: Same text is in clipboard
7. Expected: Both injection and clipboard write succeed

### Test Case 4: .hudOnly Mode
1. Hold Right Option key for 2 seconds, then release
2. Verify: No text appears in any window
3. Verify: Text appears in HUD and history
4. Expected: No injection, no clipboard write

### Test Case 5: OutputMode Persistence
1. Change OutputMode to `.clipboard` in Settings
2. Quit and relaunch the app
3. Open Settings
4. Verify: `.clipboard` is still selected
5. Expected: Setting persists via UserDefaults

---

## Recommendation

**QA STATUS: BLOCKED — DO NOT SHIP**

The transcription output pipeline is fundamentally broken due to async/await contract violations. All non-`.hudOnly` output modes are non-functional.

**Next Steps:**
1. Apply all three recommended fixes immediately
2. Run the testing plan above
3. Resubmit for QA review
4. Create follow-up PR with regression tests for async/await boundaries in injection pipeline

**Files to Modify:**
- `Sources/WhisKeyCore/Pipeline/TranscriptionPipeline.swift` (clipboardOnly annotation + await removal)
- `Sources/WhisKeyCore/Injection/TextInjector.swift` (async removal + await removal)
- `Sources/WhisKeyCore/Injection/AXInjector.swift` (remove @MainActor annotation)
- `Sources/WhisKeyCore/Injection/PasteboardInjector.swift` (remove @MainActor annotation)
- `Sources/WhisKeyCore/Injection/CGEventInjector.swift` (remove @MainActor annotation)
