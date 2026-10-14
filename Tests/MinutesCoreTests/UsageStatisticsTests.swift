import XCTest
@testable import MinutesCore

final class UsageStatisticsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func store() -> UsageStore {
        UsageStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("Minutes2-Usage-\(UUID()).json"), now: start)
    }
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    func testPauseResumeExcludesPauseAndCountsOnceOnCompletion() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginWork(id, at: start, deadline: start.addingTimeInterval(60))
        store.pauseWork(id, at: start.addingTimeInterval(15))
        let paused = UsageAggregation.total(store.snapshot(at: start.addingTimeInterval(60)), at: start.addingTimeInterval(60))
        XCTAssertEqual(paused.workSeconds, 15); XCTAssertEqual(paused.workCount, 0)
        store.beginWork(id, at: start.addingTimeInterval(60), deadline: start.addingTimeInterval(90), continuing: true)
        store.finishWork(id, at: start.addingTimeInterval(90))
        store.finishWork(id, at: start.addingTimeInterval(91))
        let result = UsageAggregation.total(store.ledger, at: start.addingTimeInterval(100))
        XCTAssertEqual(result.workSeconds, 45); XCTAssertEqual(result.workCount, 1)
    }
    func testResetRetainsPartialTimeWithoutCompletedCount() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginWork(id, at: start, deadline: start.addingTimeInterval(60))
        store.abandon(id, at: start.addingTimeInterval(12))
        store.beginWork(id, at: start.addingTimeInterval(20), deadline: start.addingTimeInterval(50))
        store.finishWork(id, at: start.addingTimeInterval(50))
        let result = UsageAggregation.total(store.ledger, at: start.addingTimeInterval(60))
        XCTAssertEqual(result.workSeconds, 42); XCTAssertEqual(result.workCount, 1)
    }
    func testSpeedTracksWallTimeAndDelayedTickStopsAtDeadline() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginWork(id, at: start, deadline: start.addingTimeInterval(60))
        store.updateDeadline(id, deadline: start.addingTimeInterval(22.5))
        XCTAssertEqual(UsageAggregation.total(store.snapshot(at: start.addingTimeInterval(100)), at: start.addingTimeInterval(100)).workSeconds, 22.5)
        store.finishWork(id, at: start.addingTimeInterval(22.5))
        XCTAssertEqual(UsageAggregation.total(store.ledger, at: start.addingTimeInterval(100)).workSeconds, 22.5)
    }
    func testWorkAndRestOverlapsNeverInflateDailyTime() {
        let a = UsageRecord(kind: .work, startedAt: start, finishedAt: start.addingTimeInterval(60), completed: true,
                            intervals: [UsageInterval(start: start, end: start.addingTimeInterval(60))])
        let b = UsageRecord(kind: .work, startedAt: start.addingTimeInterval(30), finishedAt: start.addingTimeInterval(90), completed: true,
                            intervals: [UsageInterval(start: start.addingTimeInterval(30), end: start.addingTimeInterval(90))])
        let rest = UsageRecord(kind: .rest, startedAt: start.addingTimeInterval(50), intervals: [UsageInterval(start: start.addingTimeInterval(50), end: start.addingTimeInterval(110))])
        let ledger = UsageLedger(recordingSince: start, records: [a, b, rest])
        let result = UsageAggregation.total(ledger, at: start.addingTimeInterval(200))
        XCTAssertEqual(result.workSeconds, 90); XCTAssertEqual(result.restSeconds, 20)
        XCTAssertEqual(result.workCount, 2); XCTAssertEqual(result.restCount, 1)
    }
    func testCrossMidnightSplitsTimeAndPlacesCompletionOnCorrectDay() {
        let calendar = calendar(), midnight = date(2026, 10, 14, calendar: calendar)
        let record = UsageRecord(kind: .work, startedAt: midnight.addingTimeInterval(-600), finishedAt: midnight.addingTimeInterval(600), completed: true,
                                 intervals: [UsageInterval(start: midnight.addingTimeInterval(-600), end: midnight.addingTimeInterval(600))])
        let data = UsageAggregation.days(UsageLedger(recordingSince: record.startedAt, records: [record]), period: .week, at: midnight.addingTimeInterval(1200), calendar: calendar)
        XCTAssertEqual(data.count, 7)
        XCTAssertEqual(data[data.count - 2].summary.workSeconds, 600)
        XCTAssertEqual(data.last!.summary.workSeconds, 600)
        XCTAssertEqual(data[data.count - 2].summary.workCount, 0)
        XCTAssertEqual(data.last!.summary.workCount, 1)
    }
    func testPeriodsUseCalendarMonthsAndIncludeLeapDay() {
        let calendar = calendar(), now = date(2024, 2, 29, 12, calendar: calendar), ledger = UsageLedger(recordingSince: now)
        XCTAssertEqual(UsageAggregation.days(ledger, period: .today, at: now, calendar: calendar).count, 1)
        XCTAssertEqual(UsageAggregation.days(ledger, period: .week, at: now, calendar: calendar).count, 7)
        XCTAssertEqual(UsageAggregation.days(ledger, period: .month, at: now, calendar: calendar).count, 29)
        XCTAssertEqual(UsageAggregation.days(ledger, period: .year, at: now, calendar: calendar).count, 366)
        for period in UsagePeriod.allCases {
            let days = UsageAggregation.days(ledger, period: period, at: now, calendar: calendar)
            XCTAssertTrue(days.allSatisfy { $0.summary.workSeconds + $0.summary.restSeconds + $0.otherSeconds == $0.daySeconds })
        }
    }
    func testDayCapacityHandlesDaylightSavingWithoutNegativeOtherTime() {
        let calendar = calendar("America/Los_Angeles"), now = date(2026, 3, 8, 23, calendar: calendar)
        let day = calendar.startOfDay(for: now), end = calendar.date(byAdding: .day, value: 1, to: day)!
        let record = UsageRecord(kind: .work, startedAt: day, intervals: [UsageInterval(start: day, end: end)])
        let result = UsageAggregation.days(UsageLedger(records: [record]), period: .today, at: end.addingTimeInterval(-0.001), calendar: calendar).last!
        XCTAssertEqual(result.daySeconds, end.timeIntervalSince(day))
        XCTAssertEqual(result.otherSeconds, 0)
        XCTAssertEqual((result.summary.workSeconds + result.summary.restSeconds) / result.daySeconds * 24, 24, accuracy: 0.001)
    }
    func testRestCountsOnStartAndManualFinishKeepsActualTime() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginRest(id, at: start, deadline: start.addingTimeInterval(300))
        XCTAssertEqual(UsageAggregation.total(store.snapshot(at: start.addingTimeInterval(5)), at: start.addingTimeInterval(5)).restCount, 1)
        store.finishRest(id, at: start.addingTimeInterval(5))
        let result = UsageAggregation.total(store.ledger, at: start.addingTimeInterval(10))
        XCTAssertEqual(result.restSeconds, 5); XCTAssertEqual(result.restCount, 1)
    }
    func testCheckpointRecoveryNeverCountsAppDowntimeOrDuplicatesTime() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginWork(id, at: start, deadline: start.addingTimeInterval(120))
        store.checkpoint(at: start.addingTimeInterval(20), force: true)
        let reopened = UsageStore(url: store.url, now: start.addingTimeInterval(500))
        XCTAssertEqual(UsageAggregation.total(reopened.ledger, at: start.addingTimeInterval(500)).workSeconds, 20)
        XCTAssertEqual(UsageAggregation.total(reopened.ledger, at: start.addingTimeInterval(500)).workCount, 0)
        reopened.checkpoint(at: start.addingTimeInterval(500), force: true)
        let again = UsageStore(url: store.url, now: start.addingTimeInterval(1000))
        XCTAssertEqual(UsageAggregation.total(again.ledger, at: start.addingTimeInterval(1000)).workSeconds, 20)
    }
    func testQuitAndRepeatKeepIndependentWorkAndRestRecords() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginWork(id, at: start, deadline: start.addingTimeInterval(60)); store.finishWork(id, at: start.addingTimeInterval(60))
        store.beginRest(id, at: start.addingTimeInterval(60), deadline: start.addingTimeInterval(360)); store.finishRest(id, at: start.addingTimeInterval(100))
        store.beginWork(id, at: start.addingTimeInterval(100), deadline: start.addingTimeInterval(160))
        store.finishAll(at: start.addingTimeInterval(110))
        let reopened = UsageStore(url: store.url, now: start.addingTimeInterval(1000))
        let result = UsageAggregation.total(reopened.ledger, at: start.addingTimeInterval(1000))
        XCTAssertEqual(result.workCount, 1); XCTAssertEqual(result.restCount, 1)
        XCTAssertEqual(result.workSeconds, 70); XCTAssertEqual(result.restSeconds, 40)
    }
    func testCorruptArchiveIsPreservedInsteadOfOverwritten() {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.url) }
        let data = Data("invalid-json".utf8); try! data.write(to: store.url)
        let broken = UsageStore(url: store.url, now: start)
        broken.beginWork(UUID(), at: start, deadline: start.addingTimeInterval(60)); broken.checkpoint(at: start, force: true)
        XCTAssertTrue(broken.persistenceError != nil)
        XCTAssertFalse(broken.historyAvailable)
        XCTAssertEqual(try! Data(contentsOf: store.url), data)
    }
    func testLiveSnapshotDoesNotMutateOrDoubleCountTheLedger() {
        let store = store(), id = UUID()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.beginWork(id, at: start, deadline: start.addingTimeInterval(60))
        let now = start.addingTimeInterval(10)
        XCTAssertEqual(UsageAggregation.total(store.snapshot(at: now), at: now).workSeconds, 10)
        XCTAssertEqual(UsageAggregation.total(store.snapshot(at: now), at: now).workSeconds, 10)
        XCTAssertTrue(store.ledger.records[0].intervals.isEmpty)
    }
    func testDailyAggregationMatchesIndependentSummaryForMixedOverlaps() {
        let calendar = calendar(), today = calendar.startOfDay(for: start)
        var records: [UsageRecord] = []
        for index in 0..<80 {
            let began = today.addingTimeInterval(Double(index * 12000 - 700000))
            let ended = began.addingTimeInterval(Double(10000 + index % 5 * 7000))
            records.append(UsageRecord(kind: index % 3 == 0 ? .rest : .work, startedAt: began,
                                       finishedAt: ended, completed: true,
                                       intervals: [UsageInterval(start: began, end: ended)]))
        }
        let ledger = UsageLedger(recordingSince: today.addingTimeInterval(-700000), records: records)
        for period in UsagePeriod.allCases {
            let days = UsageAggregation.days(ledger, period: period, at: start, calendar: calendar)
            for day in days {
                let end = min(calendar.date(byAdding: .day, value: 1, to: day.date)!, start.addingTimeInterval(0.001))
                let expected = UsageAggregation.summary(ledger, from: day.date, to: end)
                XCTAssertEqual(day.summary.workSeconds, expected.workSeconds, accuracy: 0.001)
                XCTAssertEqual(day.summary.restSeconds, expected.restSeconds, accuracy: 0.001)
                XCTAssertEqual(day.summary.workCount, expected.workCount)
                XCTAssertEqual(day.summary.restCount, expected.restCount)
            }
        }
    }
    func testIdleCheckpointsDoNotRewriteUnchangedHistory() {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.url) }
        store.checkpoint(at: start, force: true)
        let before = try! Data(contentsOf: store.url)
        store.checkpoint(at: start.addingTimeInterval(60))
        XCTAssertEqual(try! Data(contentsOf: store.url), before)
    }

    func testFailedCheckpointRetriesAreThrottled() {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("Minutes2-UsageBlocked-\(UUID())")
        try! Data("not-a-directory".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = UsageStore(url: parent.appendingPathComponent("statistics.json"), now: start)
        var attempts = 0; store.changed = { attempts += 1 }
        store.beginWork(UUID(), at: start, deadline: start.addingTimeInterval(60))
        XCTAssertTrue(store.persistenceError != nil)
        store.checkpoint(at: start.addingTimeInterval(16))
        store.checkpoint(at: start.addingTimeInterval(17))
        XCTAssertEqual(attempts, 2)
    }

}
