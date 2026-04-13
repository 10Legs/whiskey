import XCTest
@testable import WhisKeyCore

final class InjectionContextTests: XCTestCase {

    func testInitStoresBundleID() {
        let ctx = InjectionContext(
            activeAppName: "Safari",
            activeAppBundleID: "com.apple.Safari",
            focusedFieldContent: nil
        )
        XCTAssertEqual(ctx.activeAppName, "Safari")
        XCTAssertEqual(ctx.activeAppBundleID, "com.apple.Safari")
        XCTAssertNil(ctx.focusedFieldContent)
    }

    func testFocusedFieldContentRoundTrips() {
        let ctx = InjectionContext(
            activeAppName: "Notion",
            activeAppBundleID: "notion.id",
            focusedFieldContent: "existing text"
        )
        XCTAssertEqual(ctx.focusedFieldContent, "existing text")
    }
}
