import AppKit
#if canImport(MinutesCore)
import MinutesCore
#endif

private enum StatsFormat {
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds)), h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? "\(h)小时 \(m)分" : "\(m)分 \(s)秒"
    }
    static func date(_ date: Date, format: String = "M/d") -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format; return formatter.string(from: date)
    }
    static func detail(_ day: UsageDay) -> String {
        "\(date(day.date, format: "yyyy年M月d日"))  ·  工作 \(duration(day.summary.workSeconds))（\(day.summary.workCount)次）  ·  休息 \(duration(day.summary.restSeconds))（\(day.summary.restCount)次）"
    }
    static func draw(_ text: String, in rect: NSRect, size: CGFloat = 11, color: NSColor = .secondaryLabelColor,
                     weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: color, .paragraphStyle: style])
    }
}

private final class StatisticsChart: NSView {
    var days: [UsageDay] = [] { didSet { selected = nil; needsDisplay = true } }
    var timeMode = true { didSet { needsDisplay = true } }
    var bars = true { didSet { needsDisplay = true } }
    private var selected: Int?
    override var isFlipped: Bool { true }
    private var plot: NSRect { NSRect(x: 56, y: 40, width: max(1, bounds.width - 76), height: max(1, bounds.height - 98)) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        selected = plot.contains(p) && !days.isEmpty ? min(days.count - 1, max(0, Int((p.x - plot.minX) / plot.width * CGFloat(days.count)))) : nil
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { selected = nil; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let workColor = NSColor.systemBlue, restColor = NSColor.systemGreen, otherColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.3)
        let legend = timeMode ? ["工作时间", bars ? "休息时间" : "休息时间（虚线）"] : ["工作次数", bars ? "休息次数" : "休息次数（虚线）"]
        for (index, label) in legend.enumerated() {
            (index == 0 ? workColor : restColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: 58 + index * 108, y: 15, width: 10, height: 10), xRadius: 3, yRadius: 3).fill()
            StatsFormat.draw(label, in: NSRect(x: 75 + index * 108, y: 11, width: 90, height: 18))
        }
        if timeMode && bars {
            otherColor.setFill(); NSBezierPath(rect: NSRect(x: 274, y: 15, width: 10, height: 10)).fill()
            StatsFormat.draw("其他时间", in: NSRect(x: 291, y: 11, width: 120, height: 18))
        }
        guard !days.isEmpty else { return }
        let rect = plot, stepWidth = rect.width / CGFloat(days.count)
        func value(_ day: UsageDay, work: Bool) -> Double {
            if timeMode { return (work ? day.summary.workSeconds : day.summary.restSeconds) / 3600 }
            return Double(work ? day.summary.workCount : day.summary.restCount)
        }
        let largest = days.map { max(value($0, work: true), value($0, work: false)) }.max() ?? 0
        let maximum: Double = timeMode && bars ? 24 : timeMode ? max(0.25, ceil(largest * 1.1 * 4) / 4) : max(4, ceil(largest / 4) * 4)
        func y(_ amount: Double) -> CGFloat { rect.maxY - CGFloat(amount / maximum) * rect.height }
        for tick in 0...4 {
            let value = maximum * Double(tick) / 4, at = y(value)
            NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
            let grid = NSBezierPath(); grid.move(to: NSPoint(x: rect.minX, y: at)); grid.line(to: NSPoint(x: rect.maxX, y: at)); grid.lineWidth = 0.5; grid.stroke()
            let text = timeMode ? (maximum <= 1 ? String(format: "%g分", value * 60) : String(format: "%g时", value)) : "\(Int(value))次"
            StatsFormat.draw(text, in: NSRect(x: 0, y: at - 8, width: 47, height: 18), alignment: .right)
        }
        if let selected {
            NSColor.systemBlue.withAlphaComponent(0.07).setFill()
            NSBezierPath(rect: NSRect(x: rect.minX + CGFloat(selected) * stepWidth, y: rect.minY, width: stepWidth, height: rect.height)).fill()
        }
        if bars {
            for (index, day) in days.enumerated() {
                let center = rect.minX + (CGFloat(index) + 0.5) * stepWidth
                let width = min(44, stepWidth * 0.78)
                if timeMode {
                    var accumulated: Double = 0
                    for (seconds, color) in [(day.summary.workSeconds, workColor), (day.summary.restSeconds, restColor), (day.otherSeconds, otherColor)] {
                        // Every daily column has a 24-hour height; DST days are normalized.
                        let hours = seconds / day.daySeconds * 24
                        let top = y(accumulated + hours), bottom = y(accumulated)
                        color.setFill(); NSBezierPath(rect: NSRect(x: center - width / 2, y: top, width: width, height: max(0, bottom - top))).fill()
                        accumulated += hours
                    }
                } else {
                    let barWidth = max(0.2, width * 0.44)
                    for (work, color, x) in [(true, workColor, center - width / 2), (false, restColor, center + width * 0.06)] {
                        let top = y(value(day, work: work))
                        color.setFill(); NSBezierPath(rect: NSRect(x: x, y: top, width: barWidth, height: max(0, rect.maxY - top))).fill()
                    }
                }
            }
        } else {
            for (work, color) in [(true, workColor), (false, restColor)] {
                let path = NSBezierPath(); path.lineWidth = 2; path.lineJoinStyle = .round; path.lineCapStyle = .round
                for (index, day) in days.enumerated() {
                    let point = NSPoint(x: rect.minX + (CGFloat(index) + 0.5) * stepWidth, y: y(value(day, work: work)))
                    if index == 0 { path.move(to: point) } else { path.line(to: point) }
                    if days.count < 35 {
                        color.setFill(); NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
                    }
                }
                if !work { path.setLineDash([5, 3], count: 2, phase: 0) }
                color.setStroke(); path.stroke()
            }
        }
        let tickCount = min(7, max(1, days.count - 1))
        var drawn: Set<Int> = []
        for tick in 0...tickCount {
            let index = Int((Double(tick) / Double(tickCount) * Double(days.count - 1)).rounded())
            guard drawn.insert(index).inserted else { continue }
            let x = rect.minX + (CGFloat(index) + 0.5) * stepWidth
            StatsFormat.draw(StatsFormat.date(days[index].date), in: NSRect(x: x - 24, y: rect.maxY + 8, width: 48, height: 18), alignment: .center)
        }
        let detail = selected.map { StatsFormat.detail(days[$0]) } ?? "移动鼠标查看每日明细"
        StatsFormat.draw(detail, in: NSRect(x: 20, y: bounds.height - 25, width: bounds.width - 40, height: 20), size: 11)
        setAccessibilityLabel("\(timeMode ? "时间" : "次数")\(bars ? "柱状图" : "折线图")，工作蓝色，休息绿色，\(days.count)天")
    }
}

private final class StatisticsHeatmap: NSView {
    var days: [UsageDay] = [] { didSet { hovered = nil; needsDisplay = true } }
    var timeMode = true { didSet { needsDisplay = true } }
    private var cells: [(NSRect, UsageDay)] = []
    private var hovered: UsageDay?
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hovered = cells.first { $0.0.contains(point) }?.1; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        cells.removeAll(); guard let first = days.first else { return }
        let calendar = Calendar.current
        let offset = (calendar.component(.weekday, from: first.date) + 5) % 7
        let weeks = (days.count + offset + 6) / 7
        let pitch = min(17, (bounds.width - 72) / CGFloat(weeks)), side = max(2, pitch - 3)
        let xStart: CGFloat = 43, yStart: CGFloat = 28
        let largest = max(timeMode ? 7200 : 4, days.map { timeMode ? $0.summary.workSeconds : Double($0.summary.workCount) }.max() ?? 0)
        for row in [0, 2, 4, 6] {
            StatsFormat.draw(["一", "二", "三", "四", "五", "六", "日"][row], in: NSRect(x: 17, y: yStart + CGFloat(row) * pitch, width: 18, height: 18), size: 10)
        }
        var previousMonth = -1
        for (index, day) in days.enumerated() {
            let column = (index + offset) / 7, row = (index + offset) % 7
            let rect = NSRect(x: xStart + CGFloat(column) * pitch, y: yStart + CGFloat(row) * pitch, width: side, height: side)
            let value = timeMode ? day.summary.workSeconds : Double(day.summary.workCount)
            let strength = value <= 0 ? 0 : min(1, max(0.18, value / largest))
            (strength == 0 ? NSColor.quaternaryLabelColor.withAlphaComponent(0.12) : NSColor.systemBlue.withAlphaComponent(0.2 + strength * 0.8)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill(); cells.append((rect, day))
            let month = calendar.component(.month, from: day.date)
            if month != previousMonth {
                StatsFormat.draw("\(month)月", in: NSRect(x: rect.minX, y: 7, width: 36, height: 17), size: 10)
                previousMonth = month
            }
        }
        let legendY = yStart + 7 * pitch + 9
        StatsFormat.draw(hovered.map(StatsFormat.detail) ?? "每格代表一天 · 移动鼠标查看日期、次数和时间", in: NSRect(x: 18, y: legendY, width: bounds.width - 150, height: 20), size: 10)
        StatsFormat.draw("少", in: NSRect(x: bounds.width - 136, y: legendY, width: 18, height: 18), size: 10)
        for i in 0..<5 {
            NSColor.systemBlue.withAlphaComponent(0.12 + CGFloat(i) * 0.22).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 115 + CGFloat(i) * 15, y: legendY + 2, width: 11, height: 11), xRadius: 2, yRadius: 2).fill()
        }
        StatsFormat.draw("多", in: NSRect(x: bounds.width - 33, y: legendY, width: 20, height: 18), size: 10)
        setAccessibilityLabel("近一年番茄钟使用热图，每格一天，按\(timeMode ? "工作时间" : "完成次数")着色")
    }
}

private final class StatisticsDashboard: NSView {
    let store: UsageStore
    private let chart = StatisticsChart()
    private let heatmap = StatisticsHeatmap()
    private let ranges = NSSegmentedControl(labels: UsagePeriod.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let metrics = NSSegmentedControl(labels: ["时间", "次数"], trackingMode: .selectOne, target: nil, action: nil)
    private let styles = NSSegmentedControl(labels: ["柱状图", "折线图"], trackingMode: .selectOne, target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "使用统计")
    private let sinceLabel = NSTextField(labelWithString: "")
    private let periodLabel = NSTextField(labelWithString: "")
    private let heatLabel = NSTextField(labelWithString: "近一年使用热图")
    private let note = NSTextField(wrappingLabelWithString: "")
    private var cards: [NSBox] = []
    private var values: [NSTextField] = []
    override var isFlipped: Bool { true }
    init(store: UsageStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 824))
        titleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        sinceLabel.font = .systemFont(ofSize: 11); sinceLabel.textColor = .secondaryLabelColor
        periodLabel.font = .systemFont(ofSize: 12); periodLabel.textColor = .secondaryLabelColor
        heatLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        for view in [titleLabel, sinceLabel, periodLabel, heatLabel, note, ranges, metrics, styles, chart, heatmap] { addSubview(view) }
        for (index, text) in ["累计完成番茄钟", "累计工作时间", "累计休息次数", "累计休息时间"].enumerated() {
            let box = NSBox(); box.boxType = .custom; box.borderWidth = 1
            box.borderColor = NSColor.separatorColor.withAlphaComponent(0.35); box.fillColor = .controlBackgroundColor
            box.cornerRadius = 10; box.contentViewMargins = .zero
            let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor
            let value = NSTextField(labelWithString: "0"); value.font = .systemFont(ofSize: 23, weight: .semibold)
            value.textColor = index < 2 ? .systemBlue : .systemGreen
            box.addSubview(label); box.addSubview(value)
            label.frame = NSRect(x: 15, y: 54, width: 205, height: 18)
            value.frame = NSRect(x: 15, y: 19, width: 210, height: 28)
            cards.append(box); values.append(value); addSubview(box)
        }
        for control in [ranges, metrics, styles] {
            control.target = self; control.action = #selector(selectionChanged)
            control.selectedSegment = 0
        }
        ranges.selectedSegment = UsagePeriod.week.rawValue
        ranges.setAccessibilityLabel("统计周期"); metrics.setAccessibilityLabel("统计指标"); styles.setAccessibilityLabel("图表类型")
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let width = bounds.width
        titleLabel.frame = NSRect(x: 24, y: 16, width: 200, height: 34)
        sinceLabel.frame = NSRect(x: 24, y: 51, width: width - 48, height: 20)
        let cardWidth = (width - 84) / 4
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: 24 + CGFloat(index) * (cardWidth + 12), y: 82, width: cardWidth, height: 93)
            for view in (card.contentView?.subviews ?? []) + card.subviews where view is NSTextField { view.frame.size.width = cardWidth - 30 }
        }
        ranges.frame = NSRect(x: 24, y: 196, width: width - 354, height: 28)
        metrics.frame = NSRect(x: width - 314, y: 196, width: 118, height: 28)
        styles.frame = NSRect(x: width - 176, y: 196, width: 152, height: 28)
        periodLabel.frame = NSRect(x: 24, y: 234, width: width - 48, height: 22)
        chart.frame = NSRect(x: 24, y: 266, width: width - 48, height: 280)
        heatLabel.frame = NSRect(x: 24, y: 565, width: width - 48, height: 24)
        heatmap.frame = NSRect(x: 24, y: 599, width: width - 48, height: 170)
        note.frame = NSRect(x: 24, y: 782, width: width - 48, height: 40)
    }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
    @objc private func selectionChanged() { refresh() }
    func refresh(at now: Date = Date()) {
        let ledger = store.snapshot(at: now), total = UsageAggregation.total(ledger, at: now)
        values[0].stringValue = "\(total.workCount) 次"
        values[1].stringValue = StatsFormat.duration(total.workSeconds)
        values[2].stringValue = "\(total.restCount) 次"
        values[3].stringValue = StatsFormat.duration(total.restSeconds)
        sinceLabel.stringValue = "从 \(StatsFormat.date(ledger.recordingSince, format: "yyyy年M月d日")) 开始记录 · 数据仅保存在此 Mac"
        guard store.historyAvailable else {
            values.forEach { $0.stringValue = "—" }
            sinceLabel.stringValue = "统计数据暂不可读取，原文件未修改"
            periodLabel.stringValue = "无法读取统计记录"
            chart.days = []; heatmap.days = []
            for control in [ranges, metrics, styles] { control.isEnabled = false }
            note.stringValue = store.persistenceError ?? "统计记录暂不可用"
            note.textColor = .systemRed; needsLayout = true; return
        }
        let period = UsagePeriod(rawValue: ranges.selectedSegment) ?? .week
        let data = UsageAggregation.days(ledger, period: period, at: now)
        chart.timeMode = metrics.selectedSegment == 0; chart.bars = styles.selectedSegment == 0; chart.days = data
        heatmap.timeMode = chart.timeMode; heatmap.days = UsageAggregation.days(ledger, period: .year, at: now)
        heatLabel.stringValue = "近一年使用热图 · \(chart.timeMode ? "工作时间" : "完成次数")"
        let summary = UsageAggregation.summary(ledger, from: period.start(at: now, calendar: .current), to: now.addingTimeInterval(0.001))
        periodLabel.stringValue = "\(period.title)  ·  工作 \(summary.workCount)次 / \(StatsFormat.duration(summary.workSeconds))  ·  休息 \(summary.restCount)次 / \(StatsFormat.duration(summary.restSeconds))"
        note.stringValue = store.persistenceError ?? "工作次数按完成计算，休息次数按实际开始计算；暂停和预览不计入时长。时间按真实经过时长记录，重叠时间去重，工作优先。\n每根时间柱代表24小时；其他时间含未记录及当天尚未到达的时段。此前未记录的使用历史无法补回。"
        note.textColor = store.persistenceError == nil ? .secondaryLabelColor : .systemRed
        needsLayout = true
    }
}

final class StatisticsWindowController: NSWindowController, NSWindowDelegate {
    private let dashboard: StatisticsDashboard
    private var refreshTimer: Timer?
    init(store: UsageStore) {
        dashboard = StatisticsDashboard(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 810),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Minutes2 · 使用统计"; window.minSize = NSSize(width: 860, height: 620)
        window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true; window.delegate = self
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 960, height: 810))
        scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]
        dashboard.autoresizingMask = [.width]; scroll.documentView = dashboard
        window.contentView = scroll; window.center()
        store.changed = { [weak self] in
            guard self?.window?.isVisible == true else { return }; self?.dashboard.refresh()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func present() {
        dashboard.refresh(); NSApp.activate(ignoringOtherApps: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.dashboard.refresh() }
        }
    }
    func windowWillClose(_ notification: Notification) { refreshTimer?.invalidate(); refreshTimer = nil }
}
