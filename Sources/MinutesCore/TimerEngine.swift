import Foundation

public struct RGB: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        red = r; green = g; blue = b
    }
    public func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        if t == 0 { return self }
        if t == 1 { return other }
        return RGB(red + (other.red - red) * t,
                   green + (other.green - green) * t,
                   blue + (other.blue - blue) * t)
    }
}

public enum Dial {
    // Clockwise from twelve o'clock. The dial is fixed to a 60-minute scale.
    public static func minutes(x: Double, y: Double) -> Int {
        var angle = atan2(x, -y)
        if angle < 0 { angle += 2 * .pi }
        return min(60, max(1, Int((angle / (2 * .pi) * 60).rounded())))
    }
    public static func color(minutes: Double) -> RGB {
        let stops: [(Double, RGB)] = [
            (0, RGB(1, 0.20, 0.20)), (15, RGB(1, 0.57, 0)),
            (30, RGB(1, 0.81, 0)), (45, RGB(0.23, 0.83, 0.09)),
            (60, RGB(0.06, 0.59, 0.98))
        ]
        let m = min(60, max(0, minutes))
        for i in 1..<stops.count where m <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            return a.1.mixed(with: b.1, amount: (m - a.0) / (b.0 - a.0))
        }
        return stops.last!.1
    }
}

public struct TimerEngine {
    public enum Phase: Equatable { case setting, running, paused, alarm }
    public private(set) var phase: Phase = .setting
    public private(set) var selectedMinutes: Int
    public var repeats: Bool
    public static let speedOptions = [1, 2, 4, 8, 16]
    public private(set) var speedMultiplier: Int
    public private(set) var deadline: Date?
    private var pausedRemaining: TimeInterval = 0

    public init(minutes: Int = 25, repeats: Bool = false, speedMultiplier: Int = 1) {
        selectedMinutes = min(60, max(1, minutes))
        self.repeats = repeats
        self.speedMultiplier = Self.speedOptions.contains(speedMultiplier) ? speedMultiplier : 1
    }
    public mutating func setSpeed(_ multiplier: Int, at now: Date) {
        guard Self.speedOptions.contains(multiplier), phase != .alarm else { return }
        let remainingTime = remaining(at: now)
        speedMultiplier = multiplier
        if phase == .running { deadline = now.addingTimeInterval(remainingTime / Double(multiplier)) }
    }
    public mutating func select(_ minutes: Int) {
        guard phase == .setting || phase == .paused else { return }
        selectedMinutes = min(60, max(1, minutes))
        if phase == .paused { pausedRemaining = Double(selectedMinutes * 60) }
    }
    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .setting: return Double(selectedMinutes * 60)
        case .running: return max(0, deadline!.timeIntervalSince(now) * Double(speedMultiplier))
        case .paused: return pausedRemaining
        case .alarm: return 0
        }
    }
    public func endTime(at now: Date) -> Date {
        phase == .running ? deadline! : now.addingTimeInterval(remaining(at: now) / Double(speedMultiplier))
    }
    public func displayedMinutes(at now: Date) -> Int {
        Int(ceil(remaining(at: now) / 60))
    }
    public func usesSeconds(at now: Date) -> Bool {
        (phase == .running || phase == .paused) && remaining(at: now) <= 60
    }
    public func displayedNumber(at now: Date) -> Int {
        let seconds = remaining(at: now)
        return Int(ceil(usesSeconds(at: now) ? seconds : seconds / 60))
    }
    public func remainingFraction(at now: Date) -> Double {
        min(1, max(0, remaining(at: now) / Double(selectedMinutes * 60)))
    }
    public mutating func toggle(at now: Date) {
        switch phase {
        case .setting:
            deadline = now.addingTimeInterval(Double(selectedMinutes * 60) / Double(speedMultiplier))
            phase = .running
        case .running:
            pausedRemaining = remaining(at: now)
            deadline = nil
            phase = pausedRemaining > 0 ? .paused : .alarm
        case .paused:
            deadline = now.addingTimeInterval(pausedRemaining / Double(speedMultiplier))
            phase = .running
        case .alarm: break
        }
    }
    @discardableResult public mutating func tick(at now: Date) -> Bool {
        guard phase == .running, remaining(at: now) <= 0 else { return false }
        phase = .alarm
        deadline = nil
        return true
    }
    public mutating func reset() {
        phase = .setting; deadline = nil; pausedRemaining = 0
    }
    public mutating func dismissAlarm(at now: Date) {
        guard phase == .alarm else { return }
        reset()
        if repeats { toggle(at: now) }
    }
}

public struct DialFocus {
    public private(set) var isFocused = false
    public init() {}
    // The first click selects the clock. Subsequent clicks may operate it.
    public mutating func click() -> Bool {
        guard isFocused else { isFocused = true; return false }
        return true
    }
    public mutating func clear() { isFocused = false }
}

public struct DialPress {
    public static let holdDuration: TimeInterval = 0.35
    public private(set) var isHolding = false
    public var isActive: Bool { began != nil }
    private var began: TimeInterval?
    private var allowsClick = false
    private var maxMovement: Double = 0
    public init() {}
    public mutating func begin(at time: TimeInterval, allowsClick: Bool) {
        began = time; self.allowsClick = allowsClick
        isHolding = false; maxMovement = 0
    }
    public mutating func update(at time: TimeInterval, movement: Double) {
        guard let began else { return }
        maxMovement = max(maxMovement, movement)
        if time - began >= Self.holdDuration { isHolding = true }
    }
    // A long press or drag must never also start/pause the timer on release.
    public mutating func end(at time: TimeInterval, movement: Double) -> Bool {
        guard isActive else { return false }
        update(at: time, movement: movement)
        let clicked = allowsClick && !isHolding && maxMovement < 4
        cancel()
        return clicked
    }
    public mutating func cancel() {
        began = nil; isHolding = false; allowsClick = false; maxMovement = 0
    }
}

/// The rest period uses a deadline, so delayed frames and system wake cannot extend it.
public struct RestCountdown {
    public static let minuteOptions = [5, 10, 15, 30]
    public let deadline: Date
    public init(minutes: Int, at now: Date) {
        let duration = Self.minuteOptions.contains(minutes) ? minutes : 5
        deadline = now.addingTimeInterval(Double(duration * 60))
    }
    public func remainingSeconds(at now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }
    public func isFinished(at now: Date) -> Bool { now >= deadline }
}
