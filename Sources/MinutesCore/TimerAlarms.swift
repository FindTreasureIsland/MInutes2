import CoreGraphics
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
    case none, bubbles, blackCat, blackCat2, hatsuneMiku
    public var title: String {
        switch self {
        case .none: return "无"
        case .bubbles: return "气泡"
        case .blackCat: return "小黑猫"
        case .blackCat2: return "小黑猫2"
        case .hatsuneMiku: return "初音未来"
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
        case .none, .hatsuneMiku: return nil
        case .bubbles: return "BubblePop"
        case .blackCat, .blackCat2: return "CatMeow"
        }
    }
    public init(scene: String? = nil, showsCountdown: Bool = true) {
        self.scene = scene.flatMap(ReminderScene.init(rawValue:)) ?? .bubbles
        self.showsCountdown = showsCountdown
    }
}

public struct CatPeekPlacement {
    public enum Edge: CaseIterable { case bottom, top, left, right }
    public let position: CGPoint
    public let hiddenPosition: CGPoint
    public let angle: CGFloat
    public init(screen: CGSize, sprite: CGSize, edge: Edge, location: Double) {
        let t = CGFloat(min(1, max(0, location)))
        let horizontal = edge == .bottom || edge == .top
        let length = horizontal ? screen.width : screen.height
        let margin = min(sprite.width / 2, length / 2)
        let along = margin + t * max(0, length - 2 * margin)
        let depth = sprite.height * 0.15
        let outside = sprite.height * 0.5 + 2
        switch edge {
        case .bottom:
            angle = 0; position = CGPoint(x: along, y: depth)
            hiddenPosition = CGPoint(x: along, y: -outside)
        case .top:
            angle = .pi; position = CGPoint(x: along, y: screen.height - depth)
            hiddenPosition = CGPoint(x: along, y: screen.height + outside)
        case .left:
            angle = -.pi / 2; position = CGPoint(x: depth, y: along)
            hiddenPosition = CGPoint(x: -outside, y: along)
        case .right:
            angle = .pi / 2; position = CGPoint(x: screen.width - depth, y: along)
            hiddenPosition = CGPoint(x: screen.width + outside, y: along)
        }
    }
}

/// Shared geometry keeps the character above the actual countdown glyphs.
public enum ReminderGeometry {
    public static func countdownHeight(in screen: CGSize) -> CGFloat {
        min(160, min(screen.width / 5, screen.height / 4))
    }
}

public struct MikuLandingPlacement {
    public let size: CGSize
    public let position: CGPoint
    public let hiddenPosition: CGPoint
    public let visibleFrame: CGRect
    public init(screen: CGSize, showsCountdown: Bool, visibleRect: CGRect) {
        let width = max(1, screen.width), height = max(1, screen.height)
        let margin = min(24, min(width, height) * 0.04)
        let gap = min(20, height * 0.025)
        let clockTop = height / 2 + ReminderGeometry.countdownHeight(in: screen) / 2
        let room = showsCountdown ? height - margin - clockTop - gap : height - 2 * margin
        let bodyWidth = max(0.01, visibleRect.width), bodyHeight = max(0.01, visibleRect.height)
        let side = max(1, min(440, width * 0.34, height * 0.43,
                              (width - 2 * margin) / bodyWidth, max(1, room) / bodyHeight))
        size = CGSize(width: side, height: side)
        let x = width / 2 - visibleRect.midX * side
        let y = showsCountdown ? clockTop + gap - visibleRect.minY * side
            : height / 2 - visibleRect.midY * side
        position = CGPoint(x: x + side / 2, y: y + side / 2)
        hiddenPosition = CGPoint(x: position.x, y: height + side / 2 + 8)
        visibleFrame = CGRect(x: x + visibleRect.minX * side, y: y + visibleRect.minY * side,
                              width: bodyWidth * side, height: bodyHeight * side)
    }
}
