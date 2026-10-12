import XCTest
@testable import MinutesCore

final class ReminderSceneTests: XCTestCase {
    func testExistingPreferencesDefaultToBubblesAndCountdown() {
        let appearance = ReminderAppearance()
        XCTAssertEqual(appearance.scene, .bubbles)
        XCTAssertTrue(appearance.showsCountdown)
        XCTAssertTrue(appearance.playsPopSound)
        XCTAssertEqual(ReminderAppearance(scene: "invalid").scene, .bubbles)
    }
    func testEverySceneAllowsIndependentCountdown() {
        for scene in ReminderScene.allCases {
            for showsClock in [true, false] {
                let appearance = ReminderAppearance(scene: scene.rawValue, showsCountdown: showsClock)
                XCTAssertEqual(appearance.scene, scene)
                XCTAssertEqual(appearance.showsCountdown, showsClock)
                XCTAssertEqual(appearance.hasVisibleOverlay, scene != .none || showsClock)
                XCTAssertEqual(appearance.playsPopSound, scene == .bubbles)
            }
        }
    }
    func testHidingVisualsDoesNotShortenTheRestPeriod() {
        let start = Date(timeIntervalSince1970: 1000)
        let appearance = ReminderAppearance(scene: "none", showsCountdown: false)
        let rest = RestCountdown(minutes: 5, at: start)
        XCTAssertFalse(appearance.hasVisibleOverlay)
        XCTAssertEqual(rest.remainingSeconds(at: start.addingTimeInterval(60)), 240)
        XCTAssertTrue(rest.isFinished(at: start.addingTimeInterval(300)))
    }
}
