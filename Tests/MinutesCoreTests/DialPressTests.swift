import XCTest
@testable import MinutesCore

final class DialPressTests: XCTestCase {
    func testShortClickStillStartsAndPausesClock() {
        var timer = TimerEngine(minutes: 25)
        var press = DialPress()
        press.begin(at: 10, allowsClick: true)
        if press.end(at: 10.1, movement: 0) { timer.toggle(at: Date(timeIntervalSince1970: 10)) }
        XCTAssertEqual(timer.phase, .running)
        press.begin(at: 11, allowsClick: true)
        if press.end(at: 11.1, movement: 0) { timer.toggle(at: Date(timeIntervalSince1970: 11)) }
        XCTAssertEqual(timer.phase, .paused)
    }
    func testLongDragDoesNotPauseRunningClock() {
        var timer = TimerEngine(minutes: 25)
        let start = Date(timeIntervalSince1970: 100)
        timer.toggle(at: start)
        var press = DialPress()
        press.begin(at: 100, allowsClick: true)
        press.update(at: 100.5, movement: 80)
        XCTAssertTrue(press.isHolding)
        if press.end(at: 101, movement: 120) { timer.toggle(at: start.addingTimeInterval(1)) }
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(1)), 1499)
        XCTAssertFalse(press.isActive)
    }
    func testLongHoldWithoutMovementIsNotAClick() {
        var press = DialPress()
        press.begin(at: 0, allowsClick: true)
        XCTAssertFalse(press.end(at: 1, movement: 0))
    }
    func testInactiveClockCanBeLongPressedWithoutStarting() {
        var press = DialPress()
        press.begin(at: 0, allowsClick: false)
        press.update(at: 1, movement: 50)
        XCTAssertTrue(press.isHolding)
        XCTAssertFalse(press.end(at: 2, movement: 50))
    }
    func testQuickDragAndCancelledPressDoNotToggle() {
        var press = DialPress()
        press.begin(at: 0, allowsClick: true)
        press.update(at: 0.1, movement: 20)
        XCTAssertFalse(press.end(at: 0.2, movement: 0))
        press.begin(at: 1, allowsClick: true)
        press.cancel()
        XCTAssertFalse(press.end(at: 1.1, movement: 0))
    }
}
