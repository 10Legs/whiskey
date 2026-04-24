import XCTest
@testable import WhisKeyCore

class TextInjectorTests: XCTestCase {
    // Full tests require Accessibility permission at runtime
    func testInjectorInitializes() {
        _ = TextInjector() // Verify initialization doesn't crash
    }
}
