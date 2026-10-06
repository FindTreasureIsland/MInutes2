import XCTest
@testable import MinutesCore

final class TimerAlarmsTests: XCTestCase {
    func testSimultaneousAlarmsAreQueuedOnceInOrder() {
        var queue = TimerAlarms()
        let first = UUID(), second = UUID()
        queue.enqueue(first); queue.enqueue(second); queue.enqueue(first)
        XCTAssertEqual(queue.next()?.timerID, first)
        queue.enqueue(first)
        XCTAssertNil(queue.next())
        XCTAssertEqual(queue.dismiss()?.timerID, first)
        XCTAssertEqual(queue.next()?.timerID, second)
        queue.dismiss()
        XCTAssertNil(queue.next())
    }
    func testClosingOnlyRemovesThatTimersReminder() {
        var queue = TimerAlarms()
        let first = UUID(), second = UUID(), third = UUID()
        queue.enqueue(first); queue.enqueue(second); queue.enqueue(third)
        _ = queue.next()
        XCTAssertFalse(queue.remove(second))
        XCTAssertTrue(queue.remove(first))
        queue.dismiss()
        XCTAssertEqual(queue.next()?.timerID, third)
    }
    func testPreviewIsDistinguishedFromRealExpiry() {
        var queue = TimerAlarms(); queue.enqueue(UUID(), preview: true)
        XCTAssertEqual(queue.next()?.preview, true)
        XCTAssertEqual(queue.dismiss()?.preview, true)
    }
}

final class RepeatingTimerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1000)
    func testRepeatStartsFreshFullDurationAfterReminderDismissal() {
        var timer = TimerEngine(minutes: 3, repeats: true)
        timer.toggle(at: start)
        XCTAssertTrue(timer.tick(at: start.addingTimeInterval(180)))
        let dismissed = start.addingTimeInterval(200)
        timer.dismissAlarm(at: dismissed)
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(at: dismissed), 180)
        XCTAssertEqual(timer.deadline, dismissed.addingTimeInterval(180))
    }
    func testNonRepeatingTimerReturnsToSettingAndManualResetDoesNotRepeat() {
        var timer = TimerEngine(minutes: 1)
        timer.toggle(at: start); timer.tick(at: start.addingTimeInterval(60))
        timer.dismissAlarm(at: start.addingTimeInterval(70))
        XCTAssertEqual(timer.phase, .setting)
        timer.repeats = true
        timer.toggle(at: start); timer.tick(at: start.addingTimeInterval(60)); timer.reset()
        timer.dismissAlarm(at: start.addingTimeInterval(70))
        XCTAssertEqual(timer.phase, .setting)
        XCTAssertTrue(timer.repeats)
    }
    func testIndependentTimersKeepSeparatePauseExpiryAndRepeatState() {
        var first = TimerEngine(minutes: 1, repeats: true)
        var second = TimerEngine(minutes: 3)
        first.toggle(at: start); second.toggle(at: start)
        second.toggle(at: start.addingTimeInterval(20))
        XCTAssertTrue(first.tick(at: start.addingTimeInterval(60)))
        XCTAssertFalse(second.tick(at: start.addingTimeInterval(60)))
        first.dismissAlarm(at: start.addingTimeInterval(80))
        XCTAssertEqual(first.phase, .running)
        XCTAssertEqual(second.phase, .paused)
        XCTAssertEqual(second.remaining(at: start.addingTimeInterval(80)), 160)
        XCTAssertFalse(second.repeats)
    }
}
