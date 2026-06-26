@testable import WhisKeyCore
import XCTest

/// Tests for ADR-009: Per-App Injection-Method Override.
///
/// Covers:
///   #1 Codable forward-migration — old profiles with no injectionMethod key decode to .auto
///   #2 Codable unknown value — unrecognized raw string resolves to .auto without throwing
///   #3 .auto regression invariant — call order AX → Pasteboard → CGEvent, short-circuit on first success
///   #4 Explicit .pasteboard on Telegram — AX not invoked, Pasteboard first, CGEvent skipped on success
///   #5 Explicit-method fallthrough — .pasteboard failure → CGEvent; .ax failure → Pasteboard → CGEvent
///   #6 Secondary call sites unchanged — voice-command / HistoryViewModel path defaults to .auto
final class InjectionMethodTests: XCTestCase {

    // MARK: - #1 Codable forward-migration

    /// Decoding a persisted AppProfile JSON that has NO injectionMethod key must
    /// succeed and default the field to .auto. This is the primary backward-compat
    /// invariant (ADR-009 §2).
    func testDecodeProfileWithoutInjectionMethodDefaultsToAuto() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "bundleIdentifier": "com.example.app",
          "displayName": "Example",
          "cleanupProfile": {
            "removeFillers": true,
            "addPunctuation": true,
            "toneStyle": "casual",
            "rawMode": false
          },
          "enabled": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let profile = try JSONDecoder().decode(AppProfile.self, from: data)
        XCTAssertEqual(profile.injectionMethod, .auto,
                       "Missing injectionMethod key must decode as .auto")
        XCTAssertEqual(profile.bundleIdentifier, "com.example.app")
        XCTAssertEqual(profile.displayName, "Example")
        XCTAssertTrue(profile.enabled)
    }

    /// Round-trip: decode an old-format profile (no injectionMethod), encode it,
    /// decode again — all other fields must be preserved and injectionMethod must
    /// now be present as "auto".
    func testRoundTripPreservesAllFields() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "bundleIdentifier": "com.example.roundtrip",
          "displayName": "Round Trip",
          "modelID": "ggml-base.en",
          "languageHint": "en",
          "cleanupProfile": {
            "removeFillers": false,
            "addPunctuation": true,
            "toneStyle": "formal",
            "rawMode": true
          },
          "enabled": false
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let profile = try JSONDecoder().decode(AppProfile.self, from: data)

        let reencoded = try JSONEncoder().encode(profile)
        let decoded2 = try JSONDecoder().decode(AppProfile.self, from: reencoded)

        XCTAssertEqual(decoded2.bundleIdentifier, "com.example.roundtrip")
        XCTAssertEqual(decoded2.displayName, "Round Trip")
        XCTAssertEqual(decoded2.modelID, "ggml-base.en")
        XCTAssertEqual(decoded2.languageHint, "en")
        XCTAssertFalse(decoded2.cleanupProfile.removeFillers)
        XCTAssertTrue(decoded2.cleanupProfile.rawMode)
        XCTAssertFalse(decoded2.enabled)
        XCTAssertEqual(decoded2.injectionMethod, .auto)
    }

    // MARK: - #2 Codable unknown value

    /// A persisted profile whose injectionMethod contains an unrecognized string
    /// must decode to .auto without throwing. Protects against reading a profile
    /// written by a newer build in an older build.
    func testDecodeUnknownInjectionMethodFallsBackToAuto() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000003",
          "bundleIdentifier": "com.example.future",
          "displayName": "Future",
          "injectionMethod": "xr_hologram",
          "cleanupProfile": {
            "removeFillers": true,
            "addPunctuation": true,
            "toneStyle": "casual",
            "rawMode": false
          },
          "enabled": true
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        // Must not throw even though "xr_hologram" is not a known InjectionMethod case.
        let profile = try JSONDecoder().decode(AppProfile.self, from: data)
        XCTAssertEqual(profile.injectionMethod, .auto,
                       "Unrecognized injectionMethod raw value must fall back to .auto")
    }

    // MARK: - #3 .auto regression invariant

    /// With method == .auto, TextInjector must call AX → Pasteboard → CGEvent in
    /// order and short-circuit on the first success. Uses SpyInjector test doubles
    /// to record call order without requiring Accessibility permission.
    func testAutoMethodCallsAXThenPasteboardThenCGEventInOrder() async {
        let spy = SpyTextInjector()
        spy.axResult = false
        spy.pasteboardResult = false

        await spy.inject("hello", capturedElement: nil, method: .auto)

        XCTAssertEqual(spy.callLog, [.ax, .pasteboard, .cgEvent],
                       ".auto must attempt AX → Pasteboard → CGEvent in that order")
    }

    func testAutoShortCircuitsOnAXSuccess() async {
        let spy = SpyTextInjector()
        spy.axResult = true

        await spy.inject("hello", capturedElement: nil, method: .auto)

        XCTAssertEqual(spy.callLog, [.ax],
                       ".auto must short-circuit after AX success — Pasteboard/CGEvent must not be called")
    }

    func testAutoShortCircuitsOnPasteboardSuccess() async {
        let spy = SpyTextInjector()
        spy.axResult = false
        spy.pasteboardResult = true

        await spy.inject("hello", capturedElement: nil, method: .auto)

        XCTAssertEqual(spy.callLog, [.ax, .pasteboard],
                       ".auto must short-circuit after Pasteboard success — CGEvent must not be called")
    }

    // MARK: - #4 Explicit .pasteboard (Telegram/Messages fix)

    /// With method == .pasteboard, AX must NOT be invoked and Pasteboard must be
    /// attempted first. On success, CGEvent must not be called.
    func testExplicitPasteboardSkipsAXAndSucceeds() async {
        let spy = SpyTextInjector()
        spy.pasteboardResult = true

        await spy.inject("hello", capturedElement: nil, method: .pasteboard)

        XCTAssertFalse(spy.callLog.contains(.ax),
                       ".pasteboard method must not invoke AX")
        XCTAssertEqual(spy.callLog.first, .pasteboard,
                       ".pasteboard method must invoke Pasteboard first")
        XCTAssertFalse(spy.callLog.contains(.cgEvent),
                       ".pasteboard method on success must not invoke CGEvent")
    }

    // MARK: - #5 Explicit-method fallthrough

    /// .pasteboard failure must fall through to CGEvent (never silently drop).
    func testExplicitPasteboardFailureFallsThroughToCGEvent() async {
        let spy = SpyTextInjector()
        spy.pasteboardResult = false

        await spy.inject("hello", capturedElement: nil, method: .pasteboard)

        XCTAssertEqual(spy.callLog, [.pasteboard, .cgEvent],
                       ".pasteboard failure must fall through to CGEvent")
    }

    /// .ax failure must fall through to Pasteboard, then CGEvent.
    func testExplicitAXFailureFallsThroughToPasteboardThenCGEvent() async {
        let spy = SpyTextInjector()
        spy.axResult = false
        spy.pasteboardResult = false

        await spy.inject("hello", capturedElement: nil, method: .ax)

        XCTAssertEqual(spy.callLog, [.ax, .pasteboard, .cgEvent],
                       ".ax failure must fall through to Pasteboard → CGEvent")
    }

    /// .ax failure with Pasteboard success must stop before CGEvent.
    func testExplicitAXFailurePasteboardSuccessStopsBeforeCGEvent() async {
        let spy = SpyTextInjector()
        spy.axResult = false
        spy.pasteboardResult = true

        await spy.inject("hello", capturedElement: nil, method: .ax)

        XCTAssertEqual(spy.callLog, [.ax, .pasteboard],
                       ".ax failure + Pasteboard success must not invoke CGEvent")
    }

    // MARK: - #6 Secondary call sites default to .auto

    /// The no-method-param overload (used by voice-command and HistoryViewModel paths)
    /// must behave identically to passing .auto explicitly.
    func testNoMethodParamDefaultsToAutoWaterfall() async {
        let spy = SpyTextInjector()
        spy.axResult = false
        spy.pasteboardResult = false

        // Calls the default-param overload (method omitted)
        await spy.inject("hello", capturedElement: nil)

        XCTAssertEqual(spy.callLog, [.ax, .pasteboard, .cgEvent],
                       "No-method-param overload must run the same .auto waterfall")
    }

    // MARK: - InjectionMethod enum basics

    func testAllCasesExist() {
        XCTAssertEqual(InjectionMethod.allCases.count, 4)
        XCTAssertTrue(InjectionMethod.allCases.contains(.auto))
        XCTAssertTrue(InjectionMethod.allCases.contains(.ax))
        XCTAssertTrue(InjectionMethod.allCases.contains(.pasteboard))
        XCTAssertTrue(InjectionMethod.allCases.contains(.cgEvent))
    }

    func testRawValues() {
        XCTAssertEqual(InjectionMethod.auto.rawValue, "auto")
        XCTAssertEqual(InjectionMethod.ax.rawValue, "ax")
        XCTAssertEqual(InjectionMethod.pasteboard.rawValue, "pasteboard")
        XCTAssertEqual(InjectionMethod.cgEvent.rawValue, "cgEvent")
    }

    // MARK: - Seeded profile factories

    func testSeededMessagesProfile() {
        let profile = AppProfile.seededMessages()
        XCTAssertEqual(profile.bundleIdentifier, "com.apple.MobileSMS")
        XCTAssertEqual(profile.injectionMethod, .pasteboard)
        XCTAssertTrue(profile.enabled)
    }

    func testSeededTelegramDesktopProfile() {
        let profile = AppProfile.seededTelegramDesktop()
        XCTAssertEqual(profile.bundleIdentifier, "com.tdesktop.Telegram")
        XCTAssertEqual(profile.injectionMethod, .pasteboard)
    }

    func testSeededTelegramAltProfile() {
        let profile = AppProfile.seededTelegramAlt()
        XCTAssertEqual(profile.bundleIdentifier, "ru.keepcoder.Telegram")
        XCTAssertEqual(profile.injectionMethod, .pasteboard)
    }
}

// MARK: - SpyTextInjector

/// A `TextInjecting` test double that records which strategies were invoked
/// without requiring Accessibility permission or real system resources.
///
/// Deliberately NOT `@MainActor` — tests are sequential, actor isolation is
/// unnecessary here, and keeping it off the main actor lets test methods call
/// it without `await MainActor.run { }` wrappers.
final class SpyTextInjector: TextInjecting, @unchecked Sendable {

    enum StrategyCall: Equatable {
        case ax, pasteboard, cgEvent
    }

    var callLog: [StrategyCall] = []
    var axResult: Bool = false
    var pasteboardResult: Bool = false
    // CGEvent never returns a meaningful Bool; calling it is the terminal action.

    func inject(_ text: String, capturedElement: AXUIElement?, method: InjectionMethod) async {
        switch method {
        case .auto:
            if callAX() { return }
            if callPasteboard() { return }
            callCGEvent()

        case .ax:
            if callAX() { return }
            if callPasteboard() { return }
            callCGEvent()

        case .pasteboard:
            if callPasteboard() { return }
            callCGEvent()

        case .cgEvent:
            callCGEvent()
        }
    }

    private func callAX() -> Bool {
        callLog.append(.ax)
        return axResult
    }

    private func callPasteboard() -> Bool {
        callLog.append(.pasteboard)
        return pasteboardResult
    }

    private func callCGEvent() {
        callLog.append(.cgEvent)
    }
}
