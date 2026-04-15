import Testing
@testable import WhisKeyCore

@Suite struct TextInjectorTests {
    // Full tests require Accessibility permission at runtime
    @Test func injectorInitializes() {
        _ = TextInjector() // Verify initialization doesn't crash
    }
}
