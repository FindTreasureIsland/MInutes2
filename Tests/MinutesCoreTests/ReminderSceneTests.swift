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
    func testEachSceneUsesItsOwnClosingSound() {
        XCTAssertNil(ReminderAppearance(scene: "none").dismissalSound)
        XCTAssertEqual(ReminderAppearance(scene: "bubbles").dismissalSound, "BubblePop")
        XCTAssertEqual(ReminderAppearance(scene: "blackCat").dismissalSound, "CatMeow")
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

final class CatPeekPlacementTests: XCTestCase {
    func testEachEdgeStartsOutsideAndMovesInwardWithMatchingAngle() {
        let screen = CGSize(width: 1000, height: 700)
        let sprite = CGSize(width: 120, height: 180)
        for edge in CatPeekPlacement.Edge.allCases {
            let placement = CatPeekPlacement(screen: screen, sprite: sprite, edge: edge, location: 0.5)
            let dx = placement.position.x - placement.hiddenPosition.x
            let dy = placement.position.y - placement.hiddenPosition.y
            let inward = dx * -sin(placement.angle) + dy * cos(placement.angle)
            XCTAssertTrue(inward > 0)
            switch edge {
            case .bottom: XCTAssertTrue(placement.hiddenPosition.y + sprite.height / 2 < 0)
            case .top: XCTAssertTrue(placement.hiddenPosition.y - sprite.height / 2 > screen.height)
            case .left: XCTAssertTrue(placement.hiddenPosition.x + sprite.height / 2 < 0)
            case .right: XCTAssertTrue(placement.hiddenPosition.x - sprite.height / 2 > screen.width)
            }
        }
    }
    func testLocationsStayWithinEdgeAndSmallScreensRemainValid() {
        for edge in CatPeekPlacement.Edge.allCases {
            for location in [-1.0, 0.0, 0.5, 1.0, 2.0] {
                let placement = CatPeekPlacement(screen: CGSize(width: 100, height: 80),
                                                 sprite: CGSize(width: 200, height: 300),
                                                 edge: edge, location: location)
                let horizontal = edge == .bottom || edge == .top
                let along = horizontal ? placement.position.x : placement.position.y
                XCTAssertEqual(along, horizontal ? 50 : 40)
            }
        }
    }
    func testSecondCatSceneHasItsOwnPersistedKeyAndMeow() {
        let appearance = ReminderAppearance(scene: "blackCat2", showsCountdown: false)
        XCTAssertEqual(appearance.scene, .blackCat2)
        XCTAssertEqual(appearance.scene.title, "小黑猫2")
        XCTAssertEqual(appearance.dismissalSound, "CatMeow")
        XCTAssertTrue(appearance.hasVisibleOverlay)
    }
}
