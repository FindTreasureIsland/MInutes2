import Foundation

public enum UsageKind: String, Codable { case work, rest }

public struct UsageInterval: Codable, Equatable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = max(start, end) }
    public var seconds: TimeInterval { end.timeIntervalSince(start) }
}

public struct UsageRecord: Codable, Identifiable {
    public let id: UUID
    public let kind: UsageKind
    public let startedAt: Date
    public var finishedAt: Date?
    public var completed: Bool
    public var intervals: [UsageInterval]
    public init(kind: UsageKind, startedAt: Date, finishedAt: Date? = nil,
                completed: Bool = false, intervals: [UsageInterval] = []) {
        id = UUID(); self.kind = kind; self.startedAt = startedAt
        self.finishedAt = finishedAt; self.completed = completed; self.intervals = intervals
    }
}

public struct UsageLedger: Codable {
    public let recordingSince: Date
    public var records: [UsageRecord]
    public init(recordingSince: Date = Date(), records: [UsageRecord] = []) {
        self.recordingSince = recordingSince; self.records = records
    }
}

public enum UsagePeriod: Int, CaseIterable {
    case today, week, month, threeMonths, sixMonths, year
    public var title: String {
        switch self {
        case .today: return "今天"
        case .week: return "近7天"
        case .month: return "近1个月"
        case .threeMonths: return "近3个月"
        case .sixMonths: return "近6个月"
        case .year: return "近1年"
        }
    }
    public func start(at now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)!
        case .month, .threeMonths, .sixMonths, .year:
            let months = self == .month ? 1 : self == .threeMonths ? 3 : self == .sixMonths ? 6 : 12
            let end = calendar.date(byAdding: .day, value: 1, to: today)!
            return calendar.date(byAdding: .month, value: -months, to: end)!
        }
    }
}

public struct UsageSummary {
    public var workCount = 0
    public var restCount = 0
    public var workSeconds: TimeInterval = 0
    public var restSeconds: TimeInterval = 0
    public init() {}
}

public struct UsageDay {
    public let date: Date
    public let daySeconds: TimeInterval
    public let summary: UsageSummary
    /// Civil hour for the 24 buckets in today's chart; nil for daily buckets.
    public let hour: Int?
    public init(date: Date, daySeconds: TimeInterval, summary: UsageSummary, hour: Int? = nil) {
        self.date = date; self.daySeconds = daySeconds; self.summary = summary; self.hour = hour
    }
    public var otherSeconds: TimeInterval { max(0, daySeconds - summary.workSeconds - summary.restSeconds) }
}

public enum UsageAggregation {
    /// Merge overlap so multiple clocks cannot inflate the real time in one day.
    private static func merged(_ intervals: [UsageInterval]) -> [UsageInterval] {
        let sorted = intervals.filter { $0.seconds > 0 }.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return [] }
        var start = first.start, end = first.end, result: [UsageInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= end { end = max(end, interval.end) }
            else { result.append(UsageInterval(start: start, end: end)); start = interval.start; end = interval.end }
        }
        result.append(UsageInterval(start: start, end: end)); return result
    }
    public static func unionSeconds(_ intervals: [UsageInterval]) -> TimeInterval {
        merged(intervals).reduce(0) { $0 + $1.seconds }
    }
    public static func summary(_ ledger: UsageLedger, from start: Date, to end: Date) -> UsageSummary {
        func clipped(_ kind: UsageKind) -> [UsageInterval] {
            ledger.records.filter { $0.kind == kind }.flatMap(\.intervals).compactMap {
                let a = max(start, $0.start), b = min(end, $0.end)
                return b > a ? UsageInterval(start: a, end: b) : nil
            }
        }
        let work = clipped(.work), rest = clipped(.rest)
        var result = UsageSummary()
        result.workSeconds = unionSeconds(work)
        // Work takes priority if a rest overlaps another running clock.
        result.restSeconds = max(0, unionSeconds(work + rest) - result.workSeconds)
        result.workCount = ledger.records.filter {
            $0.kind == .work && $0.completed && $0.finishedAt.map { $0 >= start && $0 < end } == true
        }.count
        result.restCount = ledger.records.filter { $0.kind == .rest && $0.startedAt >= start && $0.startedAt < end }.count
        return result
    }
    public static func days(_ ledger: UsageLedger, period: UsagePeriod, at now: Date, calendar: Calendar = .current) -> [UsageDay] {
        let start = period.start(at: now, calendar: calendar), final = calendar.startOfDay(for: now)
        let end = now.addingTimeInterval(0.001)
        var dates: [Date] = [], day = start
        while day <= final {
            dates.append(day); day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        var workTimes: [Date: Double] = [:], occupiedTimes: [Date: Double] = [:]
        var workCounts: [Date: Int] = [:], restCounts: [Date: Int] = [:]
        let work = ledger.records.filter { $0.kind == .work }.flatMap(\.intervals)
        let rest = ledger.records.filter { $0.kind == .rest }.flatMap(\.intervals)
        func distribute(_ intervals: [UsageInterval]) -> [Date: Double] {
            var result: [Date: Double] = [:]
            for interval in merged(intervals) {
                var cursor = max(start, interval.start)
                let limit = min(end, interval.end)
                while cursor < limit {
                    let date = calendar.startOfDay(for: cursor)
                    let next = calendar.date(byAdding: .day, value: 1, to: date)!
                    let stop = min(next, limit)
                    result[date, default: 0] += stop.timeIntervalSince(cursor)
                    cursor = stop
                }
            }
            return result
        }
        workTimes = distribute(work); occupiedTimes = distribute(work + rest)
        for record in ledger.records {
            if record.kind == .work, record.completed, let finished = record.finishedAt, finished >= start, finished < end {
                workCounts[calendar.startOfDay(for: finished), default: 0] += 1
            } else if record.kind == .rest, record.startedAt >= start, record.startedAt < end {
                restCounts[calendar.startOfDay(for: record.startedAt), default: 0] += 1
            }
        }
        return dates.map { date in
            let next = calendar.date(byAdding: .day, value: 1, to: date)!
            var summary = UsageSummary()
            summary.workCount = workCounts[date] ?? 0; summary.restCount = restCounts[date] ?? 0
            summary.workSeconds = workTimes[date] ?? 0
            summary.restSeconds = max(0, (occupiedTimes[date] ?? 0) - summary.workSeconds)
            return UsageDay(date: date, daySeconds: next.timeIntervalSince(date), summary: summary)
        }
    }
    /// Always returns civil hours 0...23. Repeated DST hours share a bucket;
    /// a skipped hour is empty. Time totals still use actual elapsed seconds.
    public static func hours(_ ledger: UsageLedger, at now: Date, calendar: Calendar = .current) -> [UsageDay] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let cutoff = min(end, now.addingTimeInterval(0.001))
        let records = ledger.records.filter { record in
            record.intervals.contains { $0.start < end && $0.end > start }
                || (record.kind == .rest && record.startedAt >= start && record.startedAt < end)
                || (record.completed && record.finishedAt.map { $0 >= start && $0 < end } == true)
        }
        let today = UsageLedger(recordingSince: ledger.recordingSince, records: records)
        var summaries = Array(repeating: UsageSummary(), count: 24)
        var durations = Array(repeating: TimeInterval(0), count: 24)
        var dates: [Date?] = Array(repeating: nil, count: 24)
        var cursor = start
        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let boundary = calendar.dateInterval(of: .hour, for: cursor)?.end ?? cursor.addingTimeInterval(3600)
            let next = min(end, boundary > cursor ? boundary : cursor.addingTimeInterval(3600))
            dates[hour] = dates[hour] ?? cursor
            durations[hour] += next.timeIntervalSince(cursor)
            if cursor < cutoff {
                let value = summary(today, from: cursor, to: min(next, cutoff))
                summaries[hour].workSeconds += value.workSeconds; summaries[hour].restSeconds += value.restSeconds
                summaries[hour].workCount += value.workCount; summaries[hour].restCount += value.restCount
            }
            cursor = next
        }
        return (0..<24).map { hour in
            UsageDay(date: dates[hour] ?? start, daySeconds: durations[hour], summary: summaries[hour], hour: hour)
        }
    }
    public static func total(_ ledger: UsageLedger, at now: Date) -> UsageSummary {
        summary(ledger, from: .distantPast, to: now.addingTimeInterval(0.001))
    }
}

/// All mutation is on the app's main thread. Active spans are checkpointed for crash recovery.
public final class UsageStore {
    private struct OpenSpan: Codable {
        let timerID: UUID
        let recordID: UUID
        let since: Date
        var deadline: Date
    }
    private struct Archive: Codable {
        let version: Int
        let ledger: UsageLedger
        let open: [OpenSpan]
        let checkpoint: Date
    }
    public private(set) var ledger: UsageLedger
    public private(set) var persistenceError: String?
    public var historyAvailable: Bool { !unreadable }
    public var changed: (() -> Void)?
    public let url: URL
    private var current: [UUID: UUID] = [:]
    private var open: [UUID: OpenSpan] = [:]
    private var lastSaved: Date
    private var unreadable = false

    public init(url: URL, now: Date = Date()) {
        self.url = url; ledger = UsageLedger(recordingSince: now); lastSaved = now
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
                guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                ledger = archive.ledger
                for span in archive.open {
                    if let index = ledger.records.firstIndex(where: { $0.id == span.recordID }) {
                        let end = max(span.since, min(archive.checkpoint, span.deadline))
                        if end > span.since { ledger.records[index].intervals.append(UsageInterval(start: span.since, end: end)) }
                        ledger.records[index].finishedAt = end
                    }
                }
            } catch {
                unreadable = true
                persistenceError = "统计文件无法读取，原文件已保留。请检查数据文件后重新打开应用。"
            }
        }
    }
    private func index(for timer: UUID) -> Int? {
        guard let id = current[timer] else { return nil }
        return ledger.records.firstIndex { $0.id == id }
    }
    public func beginWork(_ timer: UUID, at now: Date, deadline: Date, continuing: Bool = false) {
        guard !unreadable else { return }
        if !continuing || index(for: timer) == nil {
            abandon(timer, at: now)
            let record = UsageRecord(kind: .work, startedAt: now)
            ledger.records.append(record); current[timer] = record.id
        }
        guard let id = current[timer], open[timer] == nil else { return }
        open[timer] = OpenSpan(timerID: timer, recordID: id, since: now, deadline: deadline)
        checkpoint(at: now, force: true)
    }
    public func beginRest(_ timer: UUID, at now: Date, deadline: Date) {
        guard !unreadable else { return }
        abandon(timer, at: now)
        let record = UsageRecord(kind: .rest, startedAt: now)
        ledger.records.append(record); current[timer] = record.id
        open[timer] = OpenSpan(timerID: timer, recordID: record.id, since: now, deadline: deadline)
        checkpoint(at: now, force: true)
    }
    private func closeSpan(_ timer: UUID, at now: Date) {
        guard let span = open.removeValue(forKey: timer), let index = index(for: timer) else { return }
        let end = max(span.since, min(now, span.deadline))
        if end > span.since { ledger.records[index].intervals.append(UsageInterval(start: span.since, end: end)) }
    }
    public func pauseWork(_ timer: UUID, at now: Date) {
        closeSpan(timer, at: now); checkpoint(at: now, force: true)
    }
    public func updateDeadline(_ timer: UUID, deadline: Date) { open[timer]?.deadline = deadline }
    public func finishWork(_ timer: UUID, at now: Date) {
        guard let index = index(for: timer), ledger.records[index].kind == .work else { return }
        closeSpan(timer, at: now)
        ledger.records[index].completed = true; ledger.records[index].finishedAt = now
        current.removeValue(forKey: timer); checkpoint(at: now, force: true)
    }
    public func finishRest(_ timer: UUID, at now: Date) { abandon(timer, at: now) }
    public func abandon(_ timer: UUID, at now: Date) {
        guard let index = index(for: timer) else { return }
        let finish = open[timer].map { min(now, $0.deadline) } ?? now
        closeSpan(timer, at: now); ledger.records[index].finishedAt = finish
        current.removeValue(forKey: timer); checkpoint(at: now, force: true)
    }
    public func snapshot(at now: Date) -> UsageLedger {
        var result = ledger
        for span in open.values {
            if let index = result.records.firstIndex(where: { $0.id == span.recordID }) {
                let end = max(span.since, min(now, span.deadline))
                if end > span.since { result.records[index].intervals.append(UsageInterval(start: span.since, end: end)) }
            }
        }
        return result
    }
    public func checkpoint(at now: Date, force: Bool = false) {
        guard !unreadable, force || (!open.isEmpty && now.timeIntervalSince(lastSaved) >= 15) else { return }
        // Throttle failed writes as well, rather than retrying on every animation tick.
        lastSaved = now
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let archive = Archive(version: 1, ledger: ledger, open: Array(open.values), checkpoint: now)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(archive).write(to: url, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = "统计尚未保存：\(error.localizedDescription)" }
        changed?()
    }
    public func finishAll(at now: Date) {
        Array(current.keys).forEach { abandon($0, at: now) }
        checkpoint(at: now, force: true)
    }
}
