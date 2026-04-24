import Testing
@testable import WhisKeyCore

struct InjectionContextTests {

    @Test func initStoresBundleID() {
        let ctx = InjectionContext(
            activeAppName: "Safari",
            activeAppBundleID: "com.apple.Safari",
            focusedFieldContent: nil
        )
        #expect(ctx.activeAppName == "Safari")
        #expect(ctx.activeAppBundleID == "com.apple.Safari")
        #expect(ctx.focusedFieldContent == nil)
    }

    @Test func focusedFieldContentRoundTrips() {
        let ctx = InjectionContext(
            activeAppName: "Notion",
            activeAppBundleID: "notion.id",
            focusedFieldContent: "existing text"
        )
        #expect(ctx.focusedFieldContent == "existing text")
    }
}
