import XCTest
@testable import Kinetic

final class DebouncedTriggerTests: XCTestCase {
    @MainActor
    func testDebounceBehavior() async throws {
        let classifier = GestureClassifier()

        // First trigger should be allowed
        XCTAssertTrue(classifier.shouldTrigger(gestureName: "tap"), "First trigger should be allowed")

        // Immediately after — should be blocked by cooldown
        XCTAssertFalse(classifier.shouldTrigger(gestureName: "tap"), "Second trigger within cooldown should be blocked")

        // Different gesture should be independent
        XCTAssertTrue(classifier.shouldTrigger(gestureName: "swipe"), "Different gesture should be independent")

        // Wait longer than the default cooldown (0.5s)
        try await Task.sleep(nanoseconds: 600_000_000)

        // After cooldown elapsed, should be allowed again
        XCTAssertTrue(classifier.shouldTrigger(gestureName: "tap"), "Trigger after cooldown should be allowed")
    }
}
