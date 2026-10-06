import XCTest
@testable import MinutesCore

final class RestCountdownTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1000)
    func testAllRestDurationsAndExactDeadline() {
        for minutes in RestCountdown.minuteOptions {
            let rest = RestCountdown(minutes: minutes, at: start)
            XCTAssertEqual(rest.remainingSeconds(at: start), minutes * 60)
            XCTAssertFalse(rest.isFinished(at: rest.deadline.addingTimeInterval(-0.1)))
            XCTAssertEqual(rest.remainingSeconds(at: rest.deadline.addingTimeInterval(-0.1)), 1)
            XCTAssertTrue(rest.isFinished(at: rest.deadline))
            XCTAssertEqual(rest.remainingSeconds(at: rest.deadline), 0)
        }
    }
    func testDelayedWakeDoesNotExtendRestAndInvalidSettingFallsBack() {
        let rest = RestCountdown(minutes: 2, at: start)
        XCTAssertEqual(rest.remainingSeconds(at: start), 300)
        XCTAssertTrue(rest.isFinished(at: start.addingTimeInterval(1000)))
        XCTAssertEqual(rest.remainingSeconds(at: start.addingTimeInterval(1000)), 0)
    }
    func testRepeatingPomodoroWaitsForRestThenStartsFullRound() {
        var timer = TimerEngine(minutes: 1, repeats: true)
        timer.toggle(at: start)
        let expired = start.addingTimeInterval(60)
        XCTAssertTrue(timer.tick(at: expired))
        let rest = RestCountdown(minutes: 5, at: expired)
        XCTAssertEqual(timer.phase, .alarm)
        XCTAssertFalse(rest.isFinished(at: expired.addingTimeInterval(299)))
        XCTAssertTrue(rest.isFinished(at: rest.deadline))
        timer.dismissAlarm(at: rest.deadline)
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(at: rest.deadline), 60)
    }
    func testDoubleClickCancellationDoesNotRestartRepeat() {
        var timer = TimerEngine(minutes: 1, repeats: true)
        timer.toggle(at: start); timer.tick(at: start.addingTimeInterval(60))
        timer.reset()
        XCTAssertEqual(timer.phase, .setting)
        XCTAssertTrue(timer.repeats)
    }
}
