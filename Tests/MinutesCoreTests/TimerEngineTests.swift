import XCTest
@testable import MinutesCore

final class TimerEngineTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000)
    func testFirstClickSelectsSecondClickStarts() {
        var timer = TimerEngine(minutes: 25)
        var focus = DialFocus()
        if focus.click() { timer.toggle(at: start) }
        XCTAssertTrue(focus.isFocused)
        XCTAssertEqual(timer.phase, .setting)
        if focus.click() { timer.toggle(at: start) }
        XCTAssertEqual(timer.phase, .running)
    }
    func testOutsideClickClearsShadowAndRefocusingDoesNotPause() {
        var timer = TimerEngine(minutes: 25)
        var focus = DialFocus()
        _ = focus.click()
        if focus.click() { timer.toggle(at: start) }
        focus.clear()
        XCTAssertFalse(focus.isFocused)
        XCTAssertEqual(timer.phase, .running)
        if focus.click() { timer.toggle(at: start.addingTimeInterval(10)) }
        XCTAssertEqual(timer.phase, .running)
        if focus.click() { timer.toggle(at: start.addingTimeInterval(20)) }
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertEqual(timer.remaining(at: start), 1480)
    }
    func testRefocusingPausedClockDoesNotResumeOrAlterRemaining() {
        var timer = TimerEngine(minutes: 15)
        var focus = DialFocus()
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(30))
        focus.clear()
        if focus.click() { timer.toggle(at: start.addingTimeInterval(500)) }
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertEqual(timer.remaining(at: start), 870)
        if focus.click() { timer.toggle(at: start.addingTimeInterval(600)) }
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(1470))
    }
    func testDeadlineAndRounding() {
        var timer = TimerEngine(minutes: 25)
        timer.toggle(at: start)
        XCTAssertEqual(timer.endTime(at: start), start.addingTimeInterval(1500))
        XCTAssertEqual(timer.displayedMinutes(at: start.addingTimeInterval(1)), 25)
        XCTAssertEqual(timer.displayedMinutes(at: start.addingTimeInterval(60)), 24)
    }
    func testCountdownSwitchesToSecondsAtExactlyOneMinute() {
        var timer = TimerEngine(minutes: 2)
        timer.toggle(at: start)
        let before = start.addingTimeInterval(59.99)
        XCTAssertFalse(timer.usesSeconds(at: before))
        XCTAssertEqual(timer.displayedNumber(at: before), 2)
        let boundary = start.addingTimeInterval(60)
        XCTAssertTrue(timer.usesSeconds(at: boundary))
        XCTAssertEqual(timer.displayedNumber(at: boundary), 60)
        XCTAssertEqual(timer.displayedNumber(at: start.addingTimeInterval(61)), 59)
        XCTAssertEqual(timer.displayedNumber(at: start.addingTimeInterval(119.9)), 1)
        XCTAssertEqual(timer.displayedNumber(at: start.addingTimeInterval(120)), 0)
        XCTAssertTrue(timer.tick(at: start.addingTimeInterval(120)))
    }
    func testSettingStillUsesMinutesAndOneMinuteSessionStartsWithSeconds() {
        var timer = TimerEngine(minutes: 1)
        XCTAssertFalse(timer.usesSeconds(at: start))
        XCTAssertEqual(timer.displayedNumber(at: start), 1)
        timer.toggle(at: start)
        XCTAssertTrue(timer.usesSeconds(at: start))
        XCTAssertEqual(timer.displayedNumber(at: start), 60)
    }
    func testSecondsPauseResumeAndAdjustmentBackToMinutes() {
        var timer = TimerEngine(minutes: 2)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(80))
        let later = start.addingTimeInterval(500)
        XCTAssertTrue(timer.usesSeconds(at: later))
        XCTAssertEqual(timer.displayedNumber(at: later), 40)
        timer.toggle(at: later)
        XCTAssertEqual(timer.displayedNumber(at: later.addingTimeInterval(1)), 39)
        timer.toggle(at: later.addingTimeInterval(1))
        timer.select(5)
        XCTAssertFalse(timer.usesSeconds(at: later))
        XCTAssertEqual(timer.displayedNumber(at: later), 5)
    }
    func testPauseResumePreservesSeconds() {
        var timer = TimerEngine(minutes: 2)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(17))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(500)), 103)
        timer.toggle(at: start.addingTimeInterval(500))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(510)), 93)
    }
    func testSleepAndDelayedTicksFireOnlyOnce() {
        var timer = TimerEngine(minutes: 1)
        timer.toggle(at: start)
        XCTAssertTrue(timer.tick(at: start.addingTimeInterval(600)))
        XCTAssertEqual(timer.phase, .alarm)
        XCTAssertFalse(timer.tick(at: start.addingTimeInterval(601)))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(600)), 0)
    }
    func testResetAndSelectionLimits() {
        var timer = TimerEngine(minutes: 99)
        XCTAssertEqual(timer.selectedMinutes, 60)
        timer.select(0)
        XCTAssertEqual(timer.selectedMinutes, 1)
        timer.toggle(at: start)
        timer.select(40)
        XCTAssertEqual(timer.selectedMinutes, 1)
        timer.reset()
        XCTAssertEqual(timer.phase, .setting)
        XCTAssertEqual(timer.remaining(at: start), 60)
    }
    func testPausedTimerDoesNotExpire() {
        var timer = TimerEngine(minutes: 1)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(10))
        XCTAssertFalse(timer.tick(at: start.addingTimeInterval(500)))
    }
    func testAdjustPausedTimerAndResumeWithNewDeadline() {
        var timer = TimerEngine(minutes: 25)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(90))
        XCTAssertEqual(timer.remaining(at: start), 1410)
        timer.select(15)
        XCTAssertEqual(timer.phase, .paused)
        XCTAssertNil(timer.deadline)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(5000)), 900)
        XCTAssertFalse(timer.tick(at: start.addingTimeInterval(5000)))
        let resumed = start.addingTimeInterval(5000)
        timer.toggle(at: resumed)
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.deadline, resumed.addingTimeInterval(900))
        XCTAssertFalse(timer.tick(at: resumed.addingTimeInterval(899)))
        XCTAssertTrue(timer.tick(at: resumed.addingTimeInterval(900)))
    }
    func testPausedAdjustmentsClampToDialLimits() {
        var timer = TimerEngine(minutes: 25)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(10))
        timer.select(0)
        XCTAssertEqual(timer.remaining(at: start), 60)
        timer.select(100)
        XCTAssertEqual(timer.remaining(at: start), 3600)
        XCTAssertEqual(timer.phase, .paused)
    }
    func testRemainingFractionForAnySessionLength() {
        for minutes in [1, 25, 60] {
            var timer = TimerEngine(minutes: minutes)
            timer.toggle(at: start)
            XCTAssertEqual(timer.remainingFraction(at: start), 1)
            XCTAssertEqual(timer.remainingFraction(at: start.addingTimeInterval(Double(minutes * 30))), 0.5)
            XCTAssertEqual(timer.remainingFraction(at: start.addingTimeInterval(Double(minutes * 60))), 0)
        }
    }
    func testDialClockwiseGeometry() {
        XCTAssertEqual(Dial.minutes(x: 150, y: 0), 15)
        XCTAssertEqual(Dial.minutes(x: 0, y: 150), 30)
        XCTAssertEqual(Dial.minutes(x: -150, y: 0), 45)
        XCTAssertEqual(Dial.minutes(x: -0.01, y: -150), 60)
        XCTAssertEqual(Dial.minutes(x: 0, y: -150), 1)
    }
    func testPaletteStopsAndInterpolation() {
        XCTAssertEqual(Dial.color(minutes: 60), RGB(0.06, 0.59, 0.98))
        XCTAssertEqual(Dial.color(minutes: 45), RGB(0.23, 0.83, 0.09))
        XCTAssertEqual(Dial.color(minutes: 30), RGB(1, 0.81, 0))
        XCTAssertEqual(Dial.color(minutes: 15), RGB(1, 0.57, 0))
        XCTAssertEqual(Dial.color(minutes: 0), RGB(1, 0.20, 0.20))
        XCTAssertEqual(Dial.color(minutes: -1), Dial.color(minutes: 0))
        XCTAssertEqual(Dial.color(minutes: 99), Dial.color(minutes: 60))
        XCTAssertEqual(Dial.color(minutes: 52.5).red, (0.23 + 0.06) / 2, accuracy: 0.00001)
        XCTAssertEqual(Dial.color(minutes: 22.5).green, (0.57 + 0.81) / 2, accuracy: 0.00001)
        // There is no abrupt jump at a color anchor, even at fractional seconds.
        for anchor in [15.0, 30.0, 45.0] {
            let before = Dial.color(minutes: anchor - 0.001)
            let after = Dial.color(minutes: anchor + 0.001)
            XCTAssertEqual(before.red, after.red, accuracy: 0.0001)
            XCTAssertEqual(before.green, after.green, accuracy: 0.0001)
            XCTAssertEqual(before.blue, after.blue, accuracy: 0.0001)
        }
    }
}
