import XCTest
@testable import MinutesCore

final class TimerSpeedTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testAllSpeedsAdvanceAndFinishAtScaledDeadlines() {
        for speed in TimerEngine.speedOptions {
            var timer = TimerEngine(minutes: 1, speedMultiplier: speed)
            XCTAssertEqual(timer.endTime(at: start), start.addingTimeInterval(60 / Double(speed)))
            timer.toggle(at: start)
            XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(1)), 60 - Double(speed), accuracy: 0.001)
            XCTAssertFalse(timer.tick(at: start.addingTimeInterval(60 / Double(speed) - 0.01)))
            XCTAssertTrue(timer.tick(at: start.addingTimeInterval(60 / Double(speed))))
        }
    }

    func testChangingSpeedPreservesRemainingTimeAndRecalculatesFinish() {
        var timer = TimerEngine(minutes: 2)
        timer.toggle(at: start)
        let changed = start.addingTimeInterval(20)
        timer.setSpeed(4, at: changed)
        XCTAssertEqual(timer.remaining(at: changed), 100, accuracy: 0.001)
        XCTAssertEqual(timer.endTime(at: changed), changed.addingTimeInterval(25))
        timer.setSpeed(1, at: changed.addingTimeInterval(5))
        XCTAssertEqual(timer.remaining(at: changed.addingTimeInterval(5)), 80, accuracy: 0.001)
        XCTAssertEqual(timer.deadline, changed.addingTimeInterval(85))
    }

    func testPauseAndResumeRetainLogicalSeconds() {
        var timer = TimerEngine(minutes: 1, speedMultiplier: 4)
        timer.toggle(at: start)
        timer.toggle(at: start.addingTimeInterval(5))
        timer.setSpeed(8, at: start.addingTimeInterval(100))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(100)), 40, accuracy: 0.001)
        timer.toggle(at: start.addingTimeInterval(100))
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(105))
        XCTAssertTrue(timer.usesSeconds(at: start.addingTimeInterval(100)))
    }

    func testRepeatingAndResetRetainSelectedSpeed() {
        var timer = TimerEngine(minutes: 1, repeats: true, speedMultiplier: 16)
        timer.toggle(at: start)
        let finish = start.addingTimeInterval(60 / 16)
        XCTAssertTrue(timer.tick(at: finish))
        timer.dismissAlarm(at: finish.addingTimeInterval(300))
        XCTAssertEqual(timer.speedMultiplier, 16)
        XCTAssertEqual(timer.deadline, finish.addingTimeInterval(300 + 60 / 16))
        timer.reset()
        XCTAssertEqual(timer.speedMultiplier, 16)
    }

    func testInvalidSpeedIsRejectedAndCannotReviveExpiredTimer() {
        var timer = TimerEngine(minutes: 1, speedMultiplier: 3)
        XCTAssertEqual(timer.speedMultiplier, 1)
        timer.toggle(at: start)
        timer.setSpeed(0, at: start)
        XCTAssertEqual(timer.speedMultiplier, 1)
        timer.setSpeed(8, at: start.addingTimeInterval(61))
        XCTAssertTrue(timer.tick(at: start.addingTimeInterval(61)))
        timer.setSpeed(16, at: start.addingTimeInterval(61))
        XCTAssertEqual(timer.speedMultiplier, 8)
    }
}
