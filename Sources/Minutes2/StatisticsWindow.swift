import AppKit
#if canImport(MinutesCore)
import MinutesCore
#endif

private enum StatsStyle {
    static var dark: Bool { NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    static var secondary: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.73, green: 0.75, blue: 0.76, alpha: 1)
                : NSColor(srgbRed: 0.34, green: 0.37, blue: 0.39, alpha: 1)
        }
    }
    static var work: NSColor { dark ? .systemTeal : NSColor(srgbRed: 0, green: 0.43, blue: 0.57, alpha: 1) }
    static var rest: NSColor { dark ? .systemOrange : NSColor(srgbRed: 0.69, green: 0.30, blue: 0.13, alpha: 1) }
    static func rounded(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }
    static func card(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20)
        NSColor.controlBackgroundColor.withAlphaComponent(dark ? 0.58 : 0.72).setFill(); path.fill()
        NSColor.labelColor.withAlphaComponent(0.08).setStroke(); path.lineWidth = 1; path.stroke()
    }
}

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
    static func draw(_ text: String, in rect: NSRect, size: CGFloat = 11, color: NSColor = StatsStyle.secondary,
                     weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle(); style.alignment = alignment
        (text as NSString).draw(in: rect, withAttributes: [.font: StatsStyle.rounded(size, weight: weight),
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
        StatsStyle.card(bounds)
        let workColor = StatsStyle.work, restColor = StatsStyle.rest, otherColor = NSColor.labelColor.withAlphaComponent(0.10)
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
        let detail = selected.map { StatsFormat.detail(days[$0]) } ?? "悬停查看每日数据 · 也可打开明细"
        StatsFormat.draw(detail, in: NSRect(x: 20, y: bounds.height - 25, width: bounds.width - 40, height: 20), size: 11)
        setAccessibilityLabel("\(timeMode ? "时间" : "次数")\(bars ? "柱状图" : "折线图")，工作青色，休息橙色，\(days.count)天")
    }
}

private final class StatisticsHeatmap: NSView {
    var days: [UsageDay] = [] { didSet { needsDisplay = true } }
    var timeMode = true { didSet { needsDisplay = true } }
    private var cells: [(NSRect, UsageDay)] = []
    private var hovered: UsageDay?
    override var isFlipped: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        hovered = cells.first { $0.0.contains(convert(event.locationInWindow, from: nil)) }?.1; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        StatsStyle.card(bounds); cells.removeAll()
        let calendar = Calendar.current
        let largest = max(timeMode ? 7200 : 4, days.map { timeMode ? $0.summary.workSeconds : Double($0.summary.workCount) }.max() ?? 0)
        // Two half-year strips keep each daily cell legible in the compact window.
        let middle = days.count / 2
        for (block, group) in [Array(days.prefix(middle)), Array(days.dropFirst(middle))].enumerated() {
            guard let first = group.first else { continue }
            let offset = (calendar.component(.weekday, from: first.date) + 5) % 7
            let weeks = (group.count + offset + 6) / 7
            let blockHeight = (bounds.height - 48) / 2
            let pitch = min(20, (bounds.width - 76) / CGFloat(weeks), (blockHeight - 36) / 7), side = pitch - 4
            let top = CGFloat(block) * blockHeight + 16
            let yStart = top + 24
            let xStart = (bounds.width - CGFloat(weeks) * pitch) / 2 + 8
            for row in [0, 2, 4, 6] {
                StatsFormat.draw(["一", "二", "三", "四", "五", "六", "日"][row], in: NSRect(x: xStart - 28, y: yStart + CGFloat(row) * pitch, width: 18, height: 18))
            }
            var previousMonth = -1
            for (index, day) in group.enumerated() {
                let rect = NSRect(x: xStart + CGFloat((index + offset) / 7) * pitch,
                                  y: yStart + CGFloat((index + offset) % 7) * pitch, width: side, height: side)
                let value = timeMode ? day.summary.workSeconds : Double(day.summary.workCount)
                let strength = value <= 0 ? 0 : min(1, max(0.18, value / largest))
                (strength == 0 ? NSColor.labelColor.withAlphaComponent(0.06) : StatsStyle.work.withAlphaComponent(0.2 + strength * 0.8)).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill(); cells.append((rect, day))
                let month = calendar.component(.month, from: day.date)
                if month != previousMonth && index >= 14 {
                    StatsFormat.draw("\(month)月", in: NSRect(x: rect.minX, y: top, width: 36, height: 18))
                }
                previousMonth = month
                if hovered?.date == day.date {
                    NSColor.labelColor.setStroke(); NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4).stroke()
                }
            }
        }
        StatsFormat.draw(hovered.map(StatsFormat.detail) ?? "每格一天 · 悬停查看明细 · 颜色越深，专注越多", in: NSRect(x: 18, y: bounds.height - 30, width: bounds.width - 36, height: 22), size: 11)
        setAccessibilityLabel("近一年专注热图，每格一天，按\(timeMode ? "工作时间" : "完成次数")着色。可通过每日明细查看完整数据。")
    }
}

private final class StatisticsOverview: NSView {
    var total = UsageSummary() { didSet { needsDisplay = true } }
    var today = UsageSummary() { didSet { needsDisplay = true } }
    var available = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let width = bounds.width, primaryHeight = bounds.height * 0.57
        let hero = NSRect(x: 0, y: 0, width: width, height: primaryHeight)
        StatsStyle.card(hero)
        let circle = NSRect(x: 28, y: (primaryHeight - 142) / 2, width: 142, height: 142)
        let path = NSBezierPath(ovalIn: circle)
        NSGradient(colors: [NSColor(srgbRed: 0.04, green: 0.49, blue: 0.60, alpha: 1),
                            NSColor(srgbRed: 0.03, green: 0.37, blue: 0.53, alpha: 1)])!.draw(in: path, angle: -35)
        let arc = NSBezierPath(ovalIn: circle.insetBy(dx: 5, dy: 5)); arc.lineWidth = 3
        NSColor.white.withAlphaComponent(0.65).setStroke(); arc.stroke()
        StatsFormat.draw("累计完成", in: NSRect(x: 28, y: circle.minY + 29, width: 142, height: 24), size: 12, color: .white, alignment: .center)
        let countRect = NSRect(x: 28, y: circle.minY + 51, width: 142, height: 57)
        if available {
            let digits = CGFloat(String(total.workCount).count)
            CountdownDigits.draw(total.workCount, in: countRect, height: min(44, 126 * 94 / (digits * 79)))
        } else {
            StatsFormat.draw("—", in: countRect, size: 40, color: .white, weight: .light, alignment: .center)
        }
        StatsFormat.draw("次专注", in: NSRect(x: 28, y: circle.minY + 105, width: 142, height: 22), size: 12, color: .white, alignment: .center)
        StatsFormat.draw("累计工作时间", in: NSRect(x: 198, y: primaryHeight / 2 - 58, width: width - 220, height: 25), size: 13)
        StatsFormat.draw(available ? StatsFormat.duration(total.workSeconds) : "—", in: NSRect(x: 198, y: primaryHeight / 2 - 24, width: width - 220, height: 46), size: 29, color: StatsStyle.work, weight: .medium)
        StatsFormat.draw(available ? "今天  \(today.workCount)次 · \(StatsFormat.duration(today.workSeconds))" : "统计记录暂不可用", in: NSRect(x: 198, y: primaryHeight / 2 + 35, width: width - 220, height: 22), size: 12)
        let y = primaryHeight + 16, cardWidth = (width - 16) / 2, height = bounds.height - y
        for (index, pair) in [("累计休息次数", "\(total.restCount) 次"), ("累计休息时间", StatsFormat.duration(total.restSeconds))].enumerated() {
            let x = CGFloat(index) * (cardWidth + 16)
            StatsStyle.card(NSRect(x: x, y: y, width: cardWidth, height: height))
            let symbol = NSImage(systemSymbolName: index == 0 ? "cup.and.saucer" : "leaf", accessibilityDescription: pair.0)
            symbol?.withSymbolConfiguration(.init(paletteColors: [StatsStyle.rest]))?.draw(in: NSRect(x: x + 22, y: y + 20, width: 24, height: 24))
            StatsFormat.draw(pair.0, in: NSRect(x: x + 56, y: y + 24, width: cardWidth - 78, height: 23), size: 13)
            StatsFormat.draw(available ? pair.1 : "—", in: NSRect(x: x + 22, y: y + 58, width: cardWidth - 44, height: 37), size: 25, color: StatsStyle.rest, weight: .medium)
            StatsFormat.draw(index == 0 ? "工作之后，也给自己片刻放松" : "只记录实际经过的休息时间", in: NSRect(x: x + 22, y: y + height - 36, width: cardWidth - 44, height: 22), size: 11)
        }
        setAccessibilityLabel(available ? "累计完成\(total.workCount)次，工作\(StatsFormat.duration(total.workSeconds))，休息\(total.restCount)次，\(StatsFormat.duration(total.restSeconds))。今天完成\(today.workCount)次。" : "统计记录暂不可读取")
    }
}

private final class StatisticsDetails: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var days: [UsageDay] = []
    private let table = NSTableView()
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 60, width: 560, height: 300))
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        for (index, title) in ["日期", "工作次数", "工作时间", "休息次数", "休息时间"].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
            column.title = title; column.width = [110, 80, 130, 80, 130][index]; table.addTableColumn(column)
        }
        table.frame = scroll.bounds; table.autoresizingMask = [.width]
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 28; table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self; table.delegate = self; scroll.documentView = table; view.addSubview(scroll); table.reloadData()
        let close = NSButton(title: "完成", target: self, action: #selector(done)); close.bezelStyle = .rounded
        close.keyEquivalent = "\r"; close.frame = NSRect(x: 500, y: 16, width: 80, height: 32); view.addSubview(close)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { days.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let day = days[row], summary = day.summary
        let values = [StatsFormat.date(day.date, format: "yyyy/M/d"), "\(summary.workCount)", StatsFormat.duration(summary.workSeconds), "\(summary.restCount)", StatsFormat.duration(summary.restSeconds)]
        let label = NSTextField(labelWithString: values[Int(tableColumn?.identifier.rawValue ?? "0") ?? 0])
        label.font = .systemFont(ofSize: 12); label.isSelectable = true; return label
    }
    @objc private func done() { if let window = view.window { window.sheetParent?.endSheet(window) } }
}

private final class StatisticsDashboard: NSView {
    let store: UsageStore
    private let chart = StatisticsChart()
    private let heatmap = StatisticsHeatmap()
    private let overview = StatisticsOverview()
    let tabs = NSSegmentedControl(labels: ["概览", "趋势", "热图"], trackingMode: .selectOne, target: nil, action: nil)
    let ranges = NSPopUpButton()
    let metrics = NSSegmentedControl(labels: ["时间", "次数"], trackingMode: .selectOne, target: nil, action: nil)
    let styles = NSSegmentedControl(labels: ["柱状图", "折线图"], trackingMode: .selectOne, target: nil, action: nil)
    private let titleLabel = NSTextField(labelWithString: "使用统计")
    private let sinceLabel = NSTextField(labelWithString: "")
    private let periodLabel = NSTextField(labelWithString: "")
    private let note = NSTextField(labelWithString: "数据仅保存在此 Mac")
    private let info = NSButton(title: "统计说明", target: nil, action: nil)
    private let details = NSButton(title: "每日明细", target: nil, action: nil)
    private let logo = NSImageView()
    private var detailsController: StatisticsDetails?
    override var isFlipped: Bool { true }
    init(store: UsageStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 680, height: 570))
        titleLabel.font = StatsStyle.rounded(22, weight: .medium)
        for label in [sinceLabel, periodLabel, note] { label.font = .systemFont(ofSize: 11); label.textColor = StatsStyle.secondary }
        periodLabel.font = .systemFont(ofSize: 12)
        logo.image = NSImage(size: NSSize(width: 48, height: 48), flipped: false) { _ in MinutesLogo.draw(size: 48); return true }
        logo.setAccessibilityLabel("Minutes2")
        for control in [tabs, metrics, styles] {
            control.selectedSegment = 0; control.segmentStyle = .rounded; control.font = .systemFont(ofSize: 13)
            control.target = self; control.action = #selector(selectionChanged)
        }
        ranges.addItems(withTitles: UsagePeriod.allCases.map(\.title)); ranges.selectItem(at: UsagePeriod.week.rawValue)
        ranges.target = self; ranges.action = #selector(selectionChanged)
        tabs.setAccessibilityLabel("统计页面"); ranges.setAccessibilityLabel("统计周期")
        metrics.setAccessibilityLabel("统计指标"); styles.setAccessibilityLabel("图表类型")
        for (index, symbol) in ["circle.dotted", "chart.xyaxis.line", "square.grid.3x3"].enumerated() {
            tabs.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: index)
        }
        for button in [info, details] { button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 11); button.target = self }
        info.action = #selector(showInfo); details.action = #selector(showDetails)
        info.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        details.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        info.imagePosition = .imageLeading; details.imagePosition = .imageLeading
        for page in [overview, chart, heatmap] { page.setAccessibilityElement(true); page.setAccessibilityRole(.image) }
        chart.toolTip = "悬停查看每日数据，或点按每日明细打开数据表"
        heatmap.toolTip = "每格代表一天，深色表示更多专注；每日明细支持键盘和辅助功能"
        for view in [logo, titleLabel, sinceLabel, tabs, ranges, metrics, styles, periodLabel, overview, chart, heatmap, note, info, details] { addSubview(view) }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height
        logo.frame = NSRect(x: 26, y: 36, width: 44, height: 44)
        titleLabel.frame = NSRect(x: 84, y: 34, width: width - 112, height: 30)
        sinceLabel.frame = NSRect(x: 84, y: 66, width: width - 112, height: 20)
        tabs.frame = NSRect(x: 24, y: 104, width: width - 48, height: 32)
        for index in 0..<3 { tabs.setWidth((width - 58) / 3, forSegment: index) }
        overview.frame = NSRect(x: 24, y: 156, width: width - 48, height: height - 218)
        ranges.frame = NSRect(x: 24, y: 156, width: 138, height: 30)
        metrics.frame = NSRect(x: width - 316, y: 156, width: 120, height: 30)
        styles.frame = NSRect(x: width - 180, y: 156, width: 156, height: 30)
        periodLabel.frame = NSRect(x: 28, y: 202, width: width - 56, height: 22)
        chart.frame = NSRect(x: 24, y: 236, width: width - 48, height: height - 298)
        heatmap.frame = NSRect(x: 24, y: 198, width: width - 48, height: height - 260)
        if tabs.selectedSegment == 2 {
            metrics.frame = NSRect(x: width - 144, y: 156, width: 120, height: 30)
            periodLabel.frame = NSRect(x: 28, y: 160, width: width - 192, height: 24)
        }
        note.frame = NSRect(x: 28, y: height - 38, width: width - 280, height: 20)
        info.frame = NSRect(x: width - 134, y: height - 43, width: 110, height: 30)
        details.frame = NSRect(x: width - 252, y: height - 43, width: 110, height: 30)
    }
    override func draw(_ dirtyRect: NSRect) {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        NSColor.windowBackgroundColor.withAlphaComponent(opaque ? 1 : 0.86).setFill(); bounds.fill()
        guard !opaque else { return }
        let colors = [NSColor.systemTeal.withAlphaComponent(0.10), NSColor.systemOrange.withAlphaComponent(0.07), NSColor.clear]
        NSGradient(colors: colors)?.draw(in: bounds, angle: 25)
    }
    @objc private func selectionChanged() {
        refresh()
        // Native controls keep focus; only the new page fades, without moving content.
        let page: NSView = tabs.selectedSegment == 0 ? overview : tabs.selectedSegment == 1 ? chart : heatmap
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            page.alphaValue = 0.5
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.18; page.animator().alphaValue = 1 }
        }
    }
    func refresh(at now: Date = Date()) {
        let ledger = store.snapshot(at: now), total = UsageAggregation.total(ledger, at: now)
        let period = UsagePeriod(rawValue: ranges.indexOfSelectedItem) ?? .week
        let summary = UsageAggregation.summary(ledger, from: period.start(at: now, calendar: .current), to: now.addingTimeInterval(0.001))
        overview.total = total; overview.available = store.historyAvailable
        overview.today = UsageAggregation.summary(ledger, from: Calendar.current.startOfDay(for: now), to: now.addingTimeInterval(0.001))
        sinceLabel.stringValue = "Minutes2 · 从 \(StatsFormat.date(ledger.recordingSince, format: "yyyy/M/d")) 开始记录"
        chart.timeMode = metrics.selectedSegment == 0; chart.bars = styles.selectedSegment == 0
        chart.days = store.historyAvailable ? UsageAggregation.days(ledger, period: period, at: now) : []
        heatmap.timeMode = chart.timeMode; heatmap.days = store.historyAvailable ? UsageAggregation.days(ledger, period: .year, at: now) : []
        let tab = tabs.selectedSegment
        overview.isHidden = tab != 0; chart.isHidden = tab != 1; heatmap.isHidden = tab != 2
        ranges.isHidden = tab != 1; styles.isHidden = tab != 1; metrics.isHidden = tab == 0; periodLabel.isHidden = tab == 0
        periodLabel.stringValue = tab == 2 ? "近一年 · \(chart.timeMode ? "工作时间" : "完成次数")" : "工作 \(summary.workCount)次 · \(StatsFormat.duration(summary.workSeconds))    休息 \(summary.restCount)次 · \(StatsFormat.duration(summary.restSeconds))"
        note.stringValue = store.persistenceError == nil ? "数据仅保存在此 Mac" : "统计数据暂不可用 · 查看说明"
        note.textColor = store.persistenceError == nil ? StatsStyle.secondary : .systemRed
        if !store.historyAvailable { sinceLabel.stringValue = "统计记录暂不可读取，原文件未修改"; periodLabel.stringValue = "无法读取统计记录" }
        ranges.isEnabled = store.historyAvailable; metrics.isEnabled = store.historyAvailable
        styles.isEnabled = store.historyAvailable; details.isEnabled = store.historyAvailable
        needsLayout = true
    }
    @objc private func showInfo() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "统计说明"
        alert.informativeText = store.persistenceError ?? "工作次数按完成计算，休息次数按实际开始计算。暂停和场景预览不计入时长，倍速按实际经过的时间记录。\n\n时间柱每根代表24小时，其他时间包含未记录与当天尚未到达的时段。多个番茄钟的重叠时长去重，工作优先。\n\n统计从此功能启用后开始记录，无法补回此前历史。数据仅保存在当前 Mac。"
        alert.addButton(withTitle: "知道了"); alert.beginSheetModal(for: window)
    }
    @objc private func showDetails() {
        guard let window else { return }
        let controller = StatisticsDetails()
        controller.days = tabs.selectedSegment != 1 ? heatmap.days.reversed() : chart.days.reversed()
        let sheet = NSWindow(contentViewController: controller)
        sheet.title = tabs.selectedSegment == 1 ? "\(ranges.titleOfSelectedItem ?? "") · 每日明细" : "近一年 · 每日明细"; detailsController = controller
        window.beginSheet(sheet) { [weak self] _ in self?.detailsController = nil }
    }
}

final class StatisticsWindowController: NSWindowController, NSWindowDelegate {
    private let dashboard: StatisticsDashboard
    private var refreshTimer: Timer?
    init(store: UsageStore) {
        dashboard = StatisticsDashboard(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 570),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Minutes2 · 使用统计"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.acceptsMouseMovedEvents = true; window.delegate = self
        window.isOpaque = false; window.backgroundColor = .clear
        let glass = NSVisualEffectView(frame: dashboard.frame)
        glass.material = .hudWindow; glass.blendingMode = .behindWindow; glass.state = .active
        dashboard.autoresizingMask = [.width, .height]; glass.addSubview(dashboard)
        window.contentView = glass; window.center()
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
