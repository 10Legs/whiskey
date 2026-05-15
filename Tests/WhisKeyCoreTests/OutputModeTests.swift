@testable import WhisKeyCore
import XCTest

class OutputModeTests: XCTestCase {

    func test_outputMode_allCasesAreCodable() {
        for mode in OutputMode.allCases {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            do {
                let encoded = try encoder.encode(mode)
                let decoded = try decoder.decode(OutputMode.self, from: encoded)
                XCTAssertEqual(mode, decoded)
            } catch {
                XCTFail("Failed to encode/decode \(mode): \(error)")
            }
        }
    }

    func test_outputMode_rawValueMatches() {
        XCTAssertEqual(OutputMode.activeWindow.rawValue, "activeWindow")
        XCTAssertEqual(OutputMode.clipboard.rawValue, "clipboard")
        XCTAssertEqual(OutputMode.both.rawValue, "both")
    }

    func test_outputMode_initFromRawValue() {
        XCTAssertEqual(OutputMode(rawValue: "activeWindow"), .activeWindow)
        XCTAssertEqual(OutputMode(rawValue: "clipboard"), .clipboard)
        XCTAssertEqual(OutputMode(rawValue: "both"), .both)
        XCTAssertNil(OutputMode(rawValue: "invalid"))
    }

    func test_outputMode_conformsToSendable() {
        let _: OutputMode = .activeWindow
    }
}
