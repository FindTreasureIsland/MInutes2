import Foundation

/// Several clocks may finish together, but only one reminder is presented at a time.
public struct TimerAlarms {
    public struct Request: Equatable {
        public let timerID: UUID
        public let preview: Bool
    }
    public private(set) var active: Request?
    private var pending: [Request] = []
    public init() {}
    public mutating func enqueue(_ id: UUID, preview: Bool = false) {
        guard active?.timerID != id, !pending.contains(where: { $0.timerID == id }) else { return }
        pending.append(Request(timerID: id, preview: preview))
    }
    public mutating func next() -> Request? {
        guard active == nil, !pending.isEmpty else { return nil }
        active = pending.removeFirst()
        return active
    }
    @discardableResult public mutating func dismiss() -> Request? {
        let previous = active
        active = nil
        return previous
    }
    /// Returns true if the visible overlay must also be dismissed.
    @discardableResult public mutating func remove(_ id: UUID) -> Bool {
        pending.removeAll { $0.timerID == id }
        return active?.timerID == id
    }
}

/// Visuals and the optional clock are independent of the actual rest duration.
public enum ReminderScene: String, CaseIterable {
    case none, bubbles, blackCat
    public var title: String {
        switch self {
        case .none: return "无"
        case .bubbles: return "气泡"
        case .blackCat: return "小黑猫"
        }
    }
}

public struct ReminderAppearance {
    public let scene: ReminderScene
    public let showsCountdown: Bool
    public var hasVisibleOverlay: Bool { scene != .none || showsCountdown }
    public var playsPopSound: Bool { scene == .bubbles }
    public var dismissalSound: String? {
        switch scene {
        case .none: return nil
        case .bubbles: return "BubblePop"
        case .blackCat: return "CatMeow"
        }
    }
    public init(scene: String? = nil, showsCountdown: Bool = true) {
        self.scene = scene.flatMap(ReminderScene.init(rawValue:)) ?? .bubbles
        self.showsCountdown = showsCountdown
    }
}
