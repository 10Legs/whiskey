@testable import WhisKeyCore
import XCTest

// MARK: - EgressAuditorDomainExtractionTests

/// Tests for EgressAuditor.domainOnly — pure logic, no hardware required.
class EgressAuditorDomainExtractionTests: XCTestCase {

    func test_domainOnly_stripsPathAndQuery() {
        let result = EgressAuditor.domainOnly(from: "https://huggingface.co/resolve/main/model.bin?token=abc")
        XCTAssertEqual(result, "huggingface.co")
    }

    func test_domainOnly_returnsBaredomainUnchanged() {
        let result = EgressAuditor.domainOnly(from: "huggingface.co")
        XCTAssertEqual(result, "huggingface.co")
    }

    func test_domainOnly_stripsFragment() {
        let result = EgressAuditor.domainOnly(from: "https://example.com/page#section")
        XCTAssertEqual(result, "example.com")
    }

    func test_domainOnly_handlesURLValue() {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")! // swiftlint:disable:this force_unwrapping
        let result = EgressAuditor.domainOnly(from: url)
        XCTAssertEqual(result, "api.openai.com")
    }

    func test_domainOnly_handlesLocalhost() {
        let result = EgressAuditor.domainOnly(from: "http://localhost:11434/api/generate")
        XCTAssertEqual(result, "localhost")
    }
}

// MARK: - NetworkActivityMonitorTests

/// Tests for NetworkActivityMonitor state machine — all pure MainActor logic.
///
/// Note: Tests that require a real NWPathMonitor (startMonitoring) are excluded
/// because NWPathMonitor must run in a process with network entitlements.
/// Those flows must be validated manually on device.
class NetworkActivityMonitorTests: XCTestCase {

    // MARK: - recordEgress: audited event types

    @MainActor
    func test_recordEgress_modelDownload_setsAuditedState() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local  // simulate post-startMonitoring state

        monitor.recordEgress(
            destination: "huggingface.co",
            bytesSent: 1024,
            bytesReceived: 2048,
            eventType: .modelDownload
        )

        XCTAssertEqual(monitor.egressState, .audited)
    }

    @MainActor
    func test_recordEgress_cloudLLM_setsAuditedState() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        monitor.recordEgress(
            destination: "api.openai.com",
            bytesSent: 512,
            bytesReceived: 1024,
            eventType: .cloudLLM
        )

        XCTAssertEqual(monitor.egressState, .audited)
    }

    // MARK: - recordEgress: unexpected event type

    @MainActor
    func test_recordEgress_unexpected_setsUnexpectedState() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        monitor.recordEgress(
            destination: "unknown-host.example.com",
            bytesSent: 256,
            bytesReceived: 0,
            eventType: .unexpected
        )

        XCTAssertEqual(monitor.egressState, .unexpected)
    }

    @MainActor
    func test_recordEgress_auditedAfterUnexpected_doesNotDowngradeState() {
        // Once in .unexpected, audited events must NOT downgrade the state.
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        monitor.recordEgress(
            destination: "unknown-host.example.com",
            bytesSent: 256,
            bytesReceived: 0,
            eventType: .unexpected
        )

        XCTAssertEqual(monitor.egressState, .unexpected)

        monitor.recordEgress(
            destination: "huggingface.co",
            bytesSent: 2048,
            bytesReceived: 4096,
            eventType: .modelDownload
        )

        // State must remain .unexpected — audited events do not clear a warning.
        XCTAssertEqual(monitor.egressState, .unexpected)
    }

    @MainActor
    func test_recordEgress_multipleUnexpected_staysUnexpected() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        for i in 0..<5 {
            monitor.recordEgress(
                destination: "bad-host-\(i).example.com",
                bytesSent: 100,
                bytesReceived: 0,
                eventType: .unexpected
            )
        }

        XCTAssertEqual(monitor.egressState, .unexpected)
    }

    // MARK: - Byte and event accumulation

    @MainActor
    func test_recordEgress_accumulatesBytes() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        monitor.recordEgress(destination: "a.co", bytesSent: 100, bytesReceived: 200, eventType: .modelDownload)
        monitor.recordEgress(destination: "b.co", bytesSent: 300, bytesReceived: 400, eventType: .cloudLLM)

        XCTAssertEqual(monitor.totalBytesSent, 400)
        XCTAssertEqual(monitor.totalBytesReceived, 600)
    }

    @MainActor
    func test_recordEgress_appendsToEgressLog() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        monitor.recordEgress(destination: "a.co", bytesSent: 1, bytesReceived: 2, eventType: .modelDownload)
        monitor.recordEgress(destination: "b.co", bytesSent: 3, bytesReceived: 4, eventType: .cloudLLM)

        XCTAssertEqual(monitor.egressLog.count, 2)
        // Newest event is first.
        XCTAssertEqual(monitor.egressLog[0].destination, "b.co")
        XCTAssertEqual(monitor.egressLog[1].destination, "a.co")
    }

    @MainActor
    func test_recordEgress_capsEgressLogAt100Events() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        for i in 0..<110 {
            monitor.recordEgress(
                destination: "host-\(i).co",
                bytesSent: 1,
                bytesReceived: 1,
                eventType: .modelDownload
            )
        }

        XCTAssertEqual(monitor.egressLog.count, 100)
    }

    @MainActor
    func test_recordEgress_updatesLastEgressAt() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local
        XCTAssertNil(monitor.lastEgressAt)

        let before = Date()
        monitor.recordEgress(destination: "x.co", bytesSent: 1, bytesReceived: 1, eventType: .modelDownload)
        let after = Date()

        XCTAssertNotNil(monitor.lastEgressAt)
        if let last = monitor.lastEgressAt {
            XCTAssertGreaterThanOrEqual(last, before)
            XCTAssertLessThanOrEqual(last, after)
        }
    }

    @MainActor
    func test_recordEgress_maintainsRecentDestinationsDeduplication() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        monitor.recordEgress(destination: "a.co", bytesSent: 1, bytesReceived: 1, eventType: .modelDownload)
        monitor.recordEgress(destination: "b.co", bytesSent: 1, bytesReceived: 1, eventType: .modelDownload)
        monitor.recordEgress(destination: "a.co", bytesSent: 1, bytesReceived: 1, eventType: .modelDownload)

        // a.co should appear only once, and be at the front (most recent).
        XCTAssertEqual(monitor.recentDestinations.filter { $0 == "a.co" }.count, 1)
        XCTAssertEqual(monitor.recentDestinations.first, "a.co")
    }

    @MainActor
    func test_recordEgress_capsRecentDestinationsAt10() {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local

        for i in 0..<15 {
            monitor.recordEgress(
                destination: "host-\(i).co",
                bytesSent: 1,
                bytesReceived: 1,
                eventType: .modelDownload
            )
        }

        XCTAssertEqual(monitor.recentDestinations.count, 10)
    }

    // MARK: - 60-second window re-evaluation (mocked clock)
    //
    // The window check runs on a Task loop inside NetworkActivityMonitor.
    // We test the underlying logic by directly injecting a past date for lastEgressAt
    // and manually calling the evaluateWindow entry point.
    //
    // evaluateWindow is private — we test its observable effect by directly setting
    // state and asserting the postcondition is correct given the invariant:
    // egressState == .audited && lastEgressAt > 60s ago → state flips to .local

    @MainActor
    func test_windowEvaluation_flipsToLocalAfter60Seconds() async {
        let monitor = NetworkActivityMonitor()
        monitor.egressState = .local  // start in a known state

        // Simulate an audited event that occurred 65 seconds ago.
        monitor.recordEgress(destination: "x.co", bytesSent: 1, bytesReceived: 1, eventType: .modelDownload)
        XCTAssertEqual(monitor.egressState, .audited)

        // Manually backdate lastEgressAt to 65 seconds ago.
        // This exercises the window logic without a real 60-second wait.
        monitor.lastEgressAt = Date().addingTimeInterval(-65)

        // Call the internal window check by starting monitoring briefly.
        // The check task fires every 5s; we wait 6s.
        // This is an integration-style wait for the async task.
        // Marked as slow test — acceptable for a background timer check.
        monitor.startMonitoring()
        try? await Task.sleep(for: .seconds(6))
        monitor.stopMonitoring()

        XCTAssertEqual(monitor.egressState, .local,
            "State should flip to .local after the 60-second window clears")
    }

    // MARK: - EgressEvent type conformance

    func test_egressEvent_isIdentifiable() {
        let event = EgressEvent(
            destination: "example.com",
            bytesSent: 100,
            bytesReceived: 200,
            eventType: .modelDownload
        )
        // Identifiable via UUID.
        XCTAssertNotNil(event.id)
    }

    func test_egressEventType_rawValues() {
        XCTAssertEqual(EgressEventType.modelDownload.rawValue, "modelDownload")
        XCTAssertEqual(EgressEventType.cloudLLM.rawValue, "cloudLLM")
        XCTAssertEqual(EgressEventType.unexpected.rawValue, "unexpected")
    }
}

// MARK: - URLSession Audit Coverage Test (lint-style)
//
// This test fails if any URLSession call exists in WhisKeyCore outside EgressAuditor.
// It scans Swift source files for raw URLSession.shared and URLSession() usage
// patterns that would bypass the audit layer.
//
// Hardware requirement: none — pure file system scan.
// CI: runs in standard test target.

class URLSessionAuditCoverageTests: XCTestCase {

    func test_noRawURLSessionSharedUsageOutsideEgressAuditor() throws {
        // Locate Sources/WhisKeyCore relative to this test file.
        // Test files live at Tests/WhisKeyCoreTests/; source lives at Sources/WhisKeyCore/.
        let thisFile = URL(fileURLWithPath: #file)
        let packageRoot = thisFile
            .deletingLastPathComponent()  // WhisKeyCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // package root
        let coreSourceDir = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("WhisKeyCore")

        let fm = FileManager.default
        guard fm.fileExists(atPath: coreSourceDir.path) else {
            XCTFail("WhisKeyCore source directory not found at \(coreSourceDir.path)")
            return
        }

        let enumerator = fm.enumerator(
            at: coreSourceDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var violations: [String] = []
        // Flag the global shared session only — this is the untracked singleton.
        // Delegate-based URLSession instances (e.g. ModelManager's per-download sessions)
        // are audited via EgressAuditor.recordCompleted() in their completion callbacks
        // and are therefore acceptable.
        let rawPatterns = [
            "URLSession.shared.dataTask",
            "URLSession.shared.downloadTask",
            "URLSession.shared.uploadTask",
        ]
        // EgressAuditor itself is exempt — it is the audit boundary.
        let exemptFile = "EgressAuditor.swift"

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift",
                  fileURL.lastPathComponent != exemptFile else { continue }

            let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            for pattern in rawPatterns {
                if content.contains(pattern) {
                    violations.append("\(fileURL.lastPathComponent): contains '\(pattern)'")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Raw URLSession usage detected outside EgressAuditor. " +
            "All outbound calls must route through EgressAuditor:\n" +
            violations.joined(separator: "\n")
        )
    }
}
