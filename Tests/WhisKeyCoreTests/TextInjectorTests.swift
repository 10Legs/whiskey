@testable import WhisKeyCore
import XCTest

class TextInjectorTests: XCTestCase {
    // Full tests require Accessibility permission at runtime
    func testInjectorInitializes() {
        _ = TextInjector() // Verify initialization doesn't crash
    }
}
