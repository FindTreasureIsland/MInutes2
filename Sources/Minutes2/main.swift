import AppKit
import AVFoundation
import UniformTypeIdentifiers
import QuartzCore
#if canImport(MinutesCore)
import MinutesCore
#endif

extension RGB {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

final class TimerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class ReminderWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AudioController {
    private var player: AVAudioPlayer?
    private var previewTimer: Timer?
    var isPlaying: Bool { player?.isPlaying ?? false }
    static let musicFiles = [
        "4e882db9a16e40f182cf105b37e3aa3a.mp3",
        "6f62d80f2b4f40e1879de727b5bd5220.mp3",
        "7f8c82324b6d47cdaca2c09fe5cb2518.mp3",
        "b0ffd21bdf994b7682e07225e8920c1c.mp3",
        "b5554e4d6a5047899250b2dae663f38b.mp3",
        "ccbbdb8aa81c47d0aeceb36b8d2e5b19.mp3",
    ]
    static let soundKeys = musicFiles + ["Silent", "Custom"]
    static let soundTitles = ["禅音", "溪流", "安静", "空灵", "秋天", "轻快", "静音", "自选音乐"]
    private var chosenSound: String
    init() {
        let saved = UserDefaults.standard.string(forKey: "sound")
        // Replace legacy built-in melodies while preserving explicit music and mute choices.
        chosenSound = saved.flatMap { Self.soundKeys.contains($0) ? $0 : nil } ?? Self.musicFiles[0]
    }
    private var chosenFile = UserDefaults.standard.string(forKey: "customSound")
    var selection: String {
        get { chosenSound }
        set { stop(); chosenSound = newValue; UserDefaults.standard.set(newValue, forKey: "sound") }
    }
    var customPath: String? {
        get { chosenFile }
        set { chosenFile = newValue; UserDefaults.standard.set(newValue, forKey: "customSound") }
    }
    var title: String {
        switch selection {
        case "Silent": return "静音"
        case "Custom": return customPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "自选音乐"
        default: return Self.soundKeys.firstIndex(of: selection).map { Self.soundTitles[$0] } ?? Self.soundTitles[0]
        }
    }
    func play(loop: Bool, sound: String? = nil) {
        stop()
        let key = sound ?? selection
        guard key != "Silent" else { return }
        let url: URL?
        if key == "Custom", let path = customPath { url = URL(fileURLWithPath: path) }
        else { url = Self.musicURL(key) }
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            if let fallback = Self.musicURL(Self.musicFiles[0]) {
                player = try? AVAudioPlayer(contentsOf: fallback)
            }
        }
        player?.numberOfLoops = loop ? -1 : 0
        player?.volume = 0.7
        player?.play()
        if !loop && sound == nil {
            previewTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in self?.stop() }
        }
    }
    private static func musicURL(_ filename: String) -> URL? {
        Bundle.main.url(forResource: (filename as NSString).deletingPathExtension,
                        withExtension: "mp3", subdirectory: "music")
    }
    func stop() { previewTimer?.invalidate(); previewTimer = nil; player?.stop(); player = nil }
    func validate(_ url: URL) -> Bool { (try? AVAudioPlayer(contentsOf: url)) != nil }
}

enum MusicIcon {
    static func draw(kind: String, in rect: NSRect, color: NSColor = .white) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 100, yBy: rect.height / 100)
        transform.concat()
        color.setFill(); color.setStroke()
        let notes = NSBezierPath()
        notes.move(to: NSPoint(x: 34, y: 27)); notes.line(to: NSPoint(x: 74, y: 27))
        notes.line(to: NSPoint(x: 74, y: 68))
        notes.move(to: NSPoint(x: 34, y: 27)); notes.line(to: NSPoint(x: 34, y: 68))
        notes.lineWidth = 5; notes.lineCapStyle = .round; notes.lineJoinStyle = .round; notes.stroke()
        for x in [CGFloat(26), CGFloat(66)] {
            NSBezierPath(ovalIn: NSRect(x: x - 9, y: 62, width: 18, height: 18)).fill()
        }
        if kind == "Silent" {
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 22, y: 23)); slash.line(to: NSPoint(x: 80, y: 81))
            slash.lineWidth = 6; slash.lineCapStyle = .round; slash.stroke()
        } else if kind == "Custom" {
            let folder = NSBezierPath()
            folder.move(to: NSPoint(x: 54, y: 67)); folder.line(to: NSPoint(x: 54, y: 58))
            folder.line(to: NSPoint(x: 66, y: 58)); folder.line(to: NSPoint(x: 72, y: 65))
            folder.line(to: NSPoint(x: 91, y: 65)); folder.line(to: NSPoint(x: 91, y: 86))
            folder.line(to: NSPoint(x: 54, y: 86)); folder.close()
            folder.lineWidth = 5; folder.lineJoinStyle = .round; folder.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class DialView: NSView {
    // Match the original Minutes on the left (300 px); Minutes2 on the right was 316 px.
    static let scale: CGFloat = 0.528 * 300 / 316
    static let logicalSize = NSSize(width: 440, height: 440)
    static let windowSize = NSSize(width: 440 * scale, height: 440 * scale)
    weak var owner: TimerSession?
    private let glass = NSVisualEffectView()
    private struct Appearance: Equatable {
        var color: RGB
        var glassAmount: Double
        var tintOpacity: Double
        func mixed(with other: Appearance, amount: Double) -> Appearance {
            Appearance(color: color.mixed(with: other.color, amount: amount),
                       glassAmount: glassAmount + (other.glassAmount - glassAmount) * amount,
                       tintOpacity: tintOpacity + (other.tintOpacity - tintOpacity) * amount)
        }
    }
    private var appearanceFrom: Appearance?
    private var appearanceTarget: Appearance?
    private var appearanceStarted: TimeInterval = 0
    private var appearanceTimer: Timer?
    private let transitionDuration: TimeInterval = 0.45

    private func appearance(at time: TimeInterval) -> Appearance? {
        guard let from = appearanceFrom, let target = appearanceTarget else { return nil }
        let progress = min(1, max(0, (time - appearanceStarted) / transitionDuration))
        let eased = progress * progress * (3 - 2 * progress)
        return from.mixed(with: target, amount: eased)
    }
    private func updateAppearance() {
        guard let owner else { return }
        let isGlass = isChoosingMusic || owner.engine.phase == .setting || owner.engine.phase == .paused
        let target = Appearance(color: Dial.color(minutes: owner.engine.remaining(at: Date()) / 60),
                                glassAmount: isGlass ? 1 : 0,
                                tintOpacity: focus.isFocused ? 0.62 : 0.52)
        guard target != appearanceTarget else { return }
        let time = CACurrentMediaTime()
        if appearanceTarget == nil {
            appearanceFrom = target; appearanceTarget = target
            appearanceStarted = time - transitionDuration
            renderAppearance()
            return
        }
        // Retarget from the displayed color so rapid clicks and dragging remain continuous.
        appearanceFrom = appearance(at: time)
        appearanceTarget = target; appearanceStarted = time
        if appearanceTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.renderAppearance()
                if CACurrentMediaTime() - self.appearanceStarted >= self.transitionDuration {
                    timer.invalidate(); self.appearanceTimer = nil
                }
            }
            appearanceTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        renderAppearance()
    }
    var dockColor: NSColor {
        let current = appearance(at: CACurrentMediaTime())
        let color = current?.color.nsColor ?? Dial.color(minutes: (owner?.engine.remaining(at: Date()) ?? 0) / 60).nsColor
        return color.blended(withFraction: ((current?.tintOpacity ?? 0.52) - 0.52) * 0.4, of: .white)!
    }
    private func renderAppearance() {
        if let appearance = appearance(at: CACurrentMediaTime()) {
            glass.alphaValue = appearance.glassAmount
            glass.isHidden = appearance.glassAmount <= 0.001
        }
        subviews.last?.needsDisplay = true
    }
    deinit { appearanceTimer?.invalidate(); carouselTimer?.invalidate() }
    private(set) var isChoosingMusic = false
    private var musicIndex = 0
    private var carouselPosition: CGFloat = 0
    private var carouselTimer: Timer?
    private var musicHover = false
    private var hoveredMusicIndex: Int?
    private var musicTracking: NSTrackingArea?
    private let musicButton = NSRect(x: 198, y: 300, width: 44, height: 44)
    private let musicColors: [NSColor] = [
        NSColor(srgbRed: 1, green: 0.23, blue: 0.33, alpha: 1),
        NSColor(srgbRed: 0.12, green: 0.84, blue: 0.27, alpha: 1),
        NSColor(srgbRed: 0.12, green: 0.62, blue: 1, alpha: 1),
        NSColor(srgbRed: 0.54, green: 0.36, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 1, green: 0.58, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.07, green: 0.82, blue: 0.83, alpha: 1),
        NSColor(srgbRed: 0.28, green: 0.29, blue: 0.29, alpha: 1),
        NSColor(srgbRed: 0.40, green: 0.52, blue: 0.66, alpha: 1)
    ]
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let musicTracking { removeTrackingArea(musicTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        musicTracking = area; addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) {
        if isChoosingMusic {
            let point = convert(event.locationInWindow, from: nil)
            let index = Int((carouselPosition + (point.x - center.x) / 205).rounded())
            if AudioController.soundKeys.indices.contains(index) {
                let x = center.x + (CGFloat(index) - carouselPosition) * 205
                if hypot(point.x - x, point.y - center.y) <= 88 {
                    if hoveredMusicIndex != index { hoveredMusicIndex = index; previewMusic(index); refresh() }
                    return
                }
            }
            if hoveredMusicIndex != nil { hoveredMusicIndex = nil; owner?.audio.stop(); refresh() }
            return
        }
        let hover = !isChoosingMusic && owner?.engine.phase == .setting && musicButton.contains(convert(event.locationInWindow, from: nil))
        if hover != musicHover { musicHover = hover; refresh() }
    }
    override func mouseExited(with event: NSEvent) {
        musicHover = false
        if hoveredMusicIndex != nil { hoveredMusicIndex = nil; owner?.audio.stop() }
        refresh()
    }
    private func previewMusic(_ index: Int) {
        let key = AudioController.soundKeys[index]
        if key != "Custom" || owner?.audio.customPath != nil { owner?.audio.play(loop: false, sound: key) }
        else { owner?.audio.stop() }
    }
    func openMusicSelection() {
        guard let owner else { return }
        cancelPress(); settingDrag = false
        isChoosingMusic = true; musicHover = false; hoveredMusicIndex = nil
        musicIndex = AudioController.soundKeys.firstIndex(of: owner.audio.selection) ?? 0
        carouselPosition = CGFloat(musicIndex)
        window?.makeFirstResponder(self)
        refresh()
    }
    func closeMusicSelection() {
        guard isChoosingMusic else { return }
        isChoosingMusic = false; hoveredMusicIndex = nil; carouselTimer?.invalidate(); carouselTimer = nil
        owner?.audio.stop(); refresh()
    }
    private func moveMusic(_ delta: Int) {
        let next = min(AudioController.soundKeys.count - 1, max(0, musicIndex + delta))
        guard next != musicIndex else { return }
        musicIndex = next; hoveredMusicIndex = nil
        let from = carouselPosition, to = CGFloat(next), started = CACurrentMediaTime()
        carouselTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - started) / 0.24)
            self.carouselPosition = from + (to - from) * CGFloat(t * t * (3 - 2 * t))
            self.subviews.last?.needsDisplay = true
            if t == 1 { timer.invalidate(); self.carouselTimer = nil }
        }
        carouselTimer = timer; RunLoop.main.add(timer, forMode: .common)
        previewMusic(next)
        refresh()
    }
    private func confirmMusic() {
        guard let owner else { return }
        let index = hoveredMusicIndex ?? musicIndex
        let key = AudioController.soundKeys[index]
        if key == "Custom" {
            closeMusicSelection()
            if !owner.chooseMusicFile() {
                openMusicSelection(); musicIndex = index; carouselPosition = CGFloat(index); refresh()
            }
        } else {
            owner.audio.selection = key; closeMusicSelection()
        }
    }
    private func drawMusicSelection() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: circle).addClip()
        // Keep the native behind-window blur visible beneath a light glass tint.
        NSGradient(colors: [.white.withAlphaComponent(0.18), .white.withAlphaComponent(0.06)])?
            .draw(in: circle, angle: 65)
        for index in AudioController.soundKeys.indices {
            let x = center.x + (CGFloat(index) - carouselPosition) * 205
            guard x + 88 >= circle.minX, x - 88 <= circle.maxX else { continue }
            let rect = NSRect(x: x - 88, y: center.y - 88, width: 176, height: 176)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: rect).addClip()
            let color = musicColors[index]
            NSGradient(starting: color.blended(withFraction: 0.3, of: .white)!, ending: color)?.draw(in: rect, angle: 60)
            if index < 6 {
                color.withAlphaComponent(0.65).setFill()
                NSBezierPath(ovalIn: rect.offsetBy(dx: -55, dy: 25)).fill()
                color.blended(withFraction: 0.35, of: .white)!.withAlphaComponent(0.4).setFill()
                NSBezierPath(ovalIn: rect.offsetBy(dx: 60, dy: -50)).fill()
            }
            MusicIcon.draw(kind: AudioController.soundKeys[index], in: rect.insetBy(dx: 14, dy: 14))
            if hoveredMusicIndex == index {
                NSColor.white.withAlphaComponent(0.8).setStroke()
                let border = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)); border.lineWidth = 3; border.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let textShadow = NSShadow(); textShadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        textShadow.shadowBlurRadius = 4; textShadow.shadowOffset = NSSize(width: 0, height: -1)
        (AudioController.soundTitles[musicIndex] as NSString).draw(in: NSRect(x: 130, y: 325, width: 180, height: 24),
            withAttributes: [.font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: style, .shadow: textShadow])
        NSGraphicsContext.restoreGraphicsState()
    }
    private var settingDrag = false
    private var windowDrag = false
    private var lastDialMinutes: Int?
    private var focus = DialFocus()
    private var press = DialPress()
    private var holdTimer: Timer?
    private var pressPointer = NSPoint.zero
    private var pressWindowOrigin = NSPoint.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Deliver the activation click to the dial, rather than its glass subview.
        super.hitTest(point) == nil ? nil : self
    }
    private let circle = NSRect(x: 70, y: 70, width: 300, height: 300)
    private let center = NSPoint(x: 220, y: 220)

    override init(frame: NSRect) {
        super.init(frame: frame)
        // AppKit scales drawing, the glass view and pointer coordinates together.
        setBoundsSize(Self.logicalSize)
        glass.frame = circle
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 150
        glass.layer?.masksToBounds = true
        addSubview(glass)
        // The effect view is behind a transparent drawing surface.
        let foreground = DialDrawingView(frame: bounds)
        foreground.dial = self
        foreground.autoresizingMask = [.width, .height]
        addSubview(foreground)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("番茄钟，拖动圆点设时，长按圆盘移动，空格开始或暂停")
    }
    required init?(coder: NSCoder) { fatalError() }
    func resize(to size: NSSize) {
        setFrameSize(size)
        setBoundsSize(Self.logicalSize)
        glass.frame = circle
        for view in subviews where view is DialDrawingView { view.frame = bounds }
        refresh()
    }
    func clearFocus() {
        closeMusicSelection()
        cancelPress()
        focus.clear()
        refresh()
    }
    private func cancelPress() {
        holdTimer?.invalidate(); holdTimer = nil
        if press.isHolding { NSCursor.arrow.set() }
        press.cancel()
        windowDrag = false
    }
    private var pointerMovement: Double {
        let p = NSEvent.mouseLocation
        return hypot(p.x - pressPointer.x, p.y - pressPointer.y)
    }
    private func beginPress(allowsClick: Bool) {
        cancelPress()
        pressPointer = NSEvent.mouseLocation
        pressWindowOrigin = window?.frame.origin ?? .zero
        press.begin(at: ProcessInfo.processInfo.systemUptime, allowsClick: allowsClick)
        holdTimer = Timer(timeInterval: DialPress.holdDuration, repeats: false) { [weak self] _ in
            guard let self, self.press.isActive else { return }
            self.press.update(at: ProcessInfo.processInfo.systemUptime, movement: self.pointerMovement)
            if self.press.isHolding { self.movePressedWindow() }
        }
        RunLoop.main.add(holdTimer!, forMode: .common)
    }
    private func movePressedWindow() {
        windowDrag = true
        NSCursor.closedHand.set()
        let p = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: pressWindowOrigin.x + p.x - pressPointer.x,
                                      y: pressWindowOrigin.y + p.y - pressPointer.y))
    }
    func containsDialPoint(_ p: NSPoint) -> Bool {
        if hypot(p.x - center.x, p.y - center.y) <= 150 { return true }
        guard let owner, owner.engine.phase == .setting || owner.engine.phase == .paused else { return false }
        let angle = owner.engine.remaining(at: Date()) / 3600 * 2 * .pi
        let handle = NSPoint(x: center.x + 150 * sin(angle), y: center.y - 150 * cos(angle))
        return hypot(p.x - handle.x, p.y - handle.y) <= 36
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        guard focus.isFocused else { return }
        NSGraphicsContext.saveGraphicsState()
        // Draw only the outer shadow, keeping the desktop glass inside untouched.
        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(ovalIn: circle))
        outside.windingRule = .evenOdd
        outside.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 42
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    func refresh() {
        updateAppearance()
        if isChoosingMusic {
            setAccessibilityValue("到时音乐：\(AudioController.soundTitles[musicIndex])，左右键切换，Enter 确认，Esc 取消")
        } else if let owner {
            let now = Date()
            let phase = owner.engine.phase == .running ? "计时中" : owner.engine.phase == .paused ? "已暂停" : "设时"
            let unit = owner.engine.usesSeconds(at: now) ? "秒" : "分钟"
            setAccessibilityValue("\(phase)，\(owner.engine.displayedNumber(at: now)) \(unit)，\(focus.isFocused ? "已选中" : "未选中")")
        }
        subviews.last?.needsDisplay = true
        needsDisplay = true
    }
    func drawDial() {
        guard let owner else { return }
        if isChoosingMusic { drawMusicSelection(); return }
        let now = Date(), phase = owner.engine.phase
        let remaining = owner.engine.remaining(at: now)
        let minutes = remaining / 60
        let isSetting = phase == .setting
        let isGlass = isSetting || phase == .paused
        let displayed = appearance(at: CACurrentMediaTime()) ?? Appearance(
            color: Dial.color(minutes: minutes), glassAmount: isGlass ? 1 : 0, tintOpacity: 0.52)
        let color = displayed.color.nsColor
        let shape = NSBezierPath(ovalIn: circle)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let opaqueAmount = 1 - displayed.glassAmount
        if opaqueAmount > 0 {
            let base = color.blended(withFraction: (displayed.tintOpacity - 0.52) * 0.4, of: .white)!
            let light = base.blended(withFraction: 0.28, of: .white)!
            NSGradient(colors: [light.withAlphaComponent(opaqueAmount),
                                base.withAlphaComponent(opaqueAmount),
                                base.blended(withFraction: 0.10, of: .white)!.withAlphaComponent(opaqueAmount)])?
                .draw(in: circle, angle: -35)
        }
        if displayed.glassAmount > 0 {
            let alpha = displayed.tintOpacity * displayed.glassAmount
            let upper = NSColor(srgbRed: 0.68, green: 0.58, blue: 0.65, alpha: 1)
                .blended(withFraction: 0.12, of: color)!
            let lower = NSColor(srgbRed: 0.57, green: 0.70, blue: 0.79, alpha: 1)
                .blended(withFraction: 0.12, of: color)!
            NSGradient(colors: [upper.withAlphaComponent(alpha), lower.withAlphaComponent(alpha)])?
                .draw(in: circle, angle: 65)
        }
        NSGraphicsContext.restoreGraphicsState()

        let fraction = min(1, max(0, minutes / 60))
        let arc = NSBezierPath()
        let count = max(1, Int(360 * fraction))
        for i in 0...count {
            let angle = Double(i) / Double(count) * fraction * 2 * .pi
            let p = NSPoint(x: center.x + 146 * sin(angle), y: center.y - 146 * cos(angle))
            if i == 0 { arc.move(to: p) } else { arc.line(to: p) }
        }
        arc.lineWidth = 8
        NSColor.white.setStroke(); arc.stroke()

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        drawText(formatter.string(from: owner.engine.endTime(at: now)),
                 rect: NSRect(x: 70, y: 132, width: 300, height: 50), size: 42, weight: .regular)
        CountdownDigits.draw(owner.engine.displayedNumber(at: now),
                             in: NSRect(x: 60, y: 167, width: 320, height: 144))

        if isGlass {
            let angle = minutes / 60 * 2 * .pi
            let p = NSPoint(x: center.x + 150 * sin(angle), y: center.y - 150 * cos(angle))
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 6; shadow.shadowOffset = NSSize(width: 0, height: -3); shadow.set()
            color.setFill(); NSBezierPath(ovalIn: NSRect(x: p.x - 28, y: p.y - 28, width: 56, height: 56)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        if isSetting {
            NSGraphicsContext.saveGraphicsState()
            if musicHover {
                let context = NSGraphicsContext.current!.cgContext
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                NSColor.white.setFill(); NSBezierPath(ovalIn: musicButton).fill()
                context.setBlendMode(.destinationOut)
                MusicIcon.draw(kind: owner.audio.selection, in: musicButton.insetBy(dx: 5, dy: 5))
                context.setBlendMode(.normal); context.endTransparencyLayer()
            } else {
                MusicIcon.draw(kind: owner.audio.selection, in: musicButton.insetBy(dx: 5, dy: 5))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if phase == .paused {
            let label = owner.engine.usesSeconds(at: now) ? "已暂停 · 秒" : "已暂停"
            drawText(label, rect: NSRect(x: 140, y: 312, width: 160, height: 25), size: 14, weight: .medium, alpha: 0.75)
        } else if owner.engine.usesSeconds(at: now) {
            drawText("秒", rect: NSRect(x: 140, y: 312, width: 160, height: 25), size: 14, weight: .medium, alpha: 0.75)
        }
    }
    private func drawText(_ string: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
                                                        .paragraphStyle: style]
        (string as NSString).draw(in: rect, withAttributes: attributes)
    }
    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        let p = convert(event.locationInWindow, from: nil)
        if !containsDialPoint(p) {
            clearFocus()
            window?.performDrag(with: event)
            return
        }
        if isChoosingMusic {
            if p.x < center.x - 88 { moveMusic(-1) }
            else if p.x > center.x + 88 { moveMusic(1) }
            else if hypot(p.x - center.x, p.y - center.y) <= 88 { confirmMusic() }
            return
        }
        if owner.engine.phase == .setting, musicButton.contains(p) { owner.showSounds(); return }
        let allowsClick = focus.click()
        if !allowsClick {
            window?.makeFirstResponder(self)
            refresh()
            beginPress(allowsClick: false)
            return
        }
        let radius = hypot(p.x - center.x, p.y - center.y)
        if owner.engine.phase == .setting || owner.engine.phase == .paused {
            let a = owner.engine.remaining(at: Date()) / 3600 * 2 * .pi
            let handle = NSPoint(x: center.x + 150 * sin(a), y: center.y - 150 * cos(a))
            if hypot(p.x - handle.x, p.y - handle.y) <= 36 || (radius >= 132 && radius <= 165) {
                settingDrag = true
                lastDialMinutes = hypot(p.x - handle.x, p.y - handle.y) <= 36 ? owner.engine.displayedMinutes(at: Date()) : nil
                updateSelection(p); return
            }
        }
        beginPress(allowsClick: true)
    }
    override func mouseDragged(with event: NSEvent) {
        if settingDrag {
            updateSelection(convert(event.locationInWindow, from: nil))
        } else if press.isActive {
            press.update(at: ProcessInfo.processInfo.systemUptime, movement: pointerMovement)
            if press.isHolding { movePressedWindow() }
        }
    }
    override func mouseUp(with event: NSEvent) {
        let moved = windowDrag
        let held = press.isHolding
        let clicked = press.end(at: ProcessInfo.processInfo.systemUptime, movement: pointerMovement)
        holdTimer?.invalidate(); holdTimer = nil
        if held || moved { NSCursor.arrow.set() }
        if moved { window?.saveFrame(usingName: owner?.frameName ?? "MinutesWindow") }
        settingDrag = false; windowDrag = false; lastDialMinutes = nil
        let p = convert(event.locationInWindow, from: nil)
        if clicked && containsDialPoint(p) { owner?.toggleTimer() }
        refresh()
    }
    private func updateSelection(_ p: NSPoint) {
        let dx = p.x - center.x, dy = p.y - center.y
        guard hypot(dx, dy) > 50 else { return }
        var value = Dial.minutes(x: dx, y: dy)
        // Crossing twelve smoothly clamps at the endpoints instead of jumping 60 -> 1.
        if let previous = lastDialMinutes {
            if previous >= 55 && value <= 5 { value = 60 }
            if previous <= 5 && value >= 55 { value = 1 }
        }
        lastDialMinutes = value
        owner?.select(value)
    }
    override func scrollWheel(with event: NSEvent) {
        if isChoosingMusic {
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            if abs(delta) > 1 { moveMusic(delta > 0 ? -1 : 1) }
            return
        }
        guard let owner, owner.engine.phase == .setting || owner.engine.phase == .paused,
              abs(event.scrollingDeltaY) > 0.1 else { return }
        owner.select(owner.engine.displayedMinutes(at: Date()) + (event.scrollingDeltaY > 0 ? 1 : -1))
    }
    override func keyDown(with event: NSEvent) {
        if isChoosingMusic {
            switch event.keyCode {
            case 123: moveMusic(-1)
            case 124: moveMusic(1)
            case 36, 76: confirmMusic()
            case 53: closeMusicSelection()
            default: break
            }
            return
        }
        switch event.keyCode {
        case 49, 36: owner?.toggleTimer()
        case 53: owner?.resetTimer()
        case 126, 124: if let owner { owner.select(owner.engine.displayedMinutes(at: Date()) + 1) }
        case 125, 123: if let owner { owner.select(owner.engine.displayedMinutes(at: Date()) - 1) }
        default: super.keyDown(with: event)
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        closeMusicSelection()
        if let menu = owner?.timerMenu() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

final class DialDrawingView: NSView {
    weak var dial: DialView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { dial?.drawDial() }
}

final class RestDigitsView: NSView {
    var seconds = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let height = min(160, min(bounds.width / 5, bounds.height / 4))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 12; shadow.shadowOffset = .zero; shadow.set()
        CountdownDigits.drawTime(seconds: seconds, in: bounds, height: height)
        NSGraphicsContext.restoreGraphicsState()
    }
}

private enum BubbleAppearance {
    // Cache translucent vector artwork; the desktop remains visible through each bubble.
    static func image(color: NSColor) -> CGImage? {
        let pixels = 384
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(pixels), y: CGFloat(pixels))
        var hue: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        let phase = hue * .pi * 2
        let center = CGPoint(x: 0.5, y: 0.5)
        context.addEllipse(in: CGRect(x: 0.015, y: 0.015, width: 0.97, height: 0.97)); context.clip()
        func glow(_ color: NSColor, at point: CGPoint, radius: CGFloat) {
            guard let gradient = CGGradient(colorsSpace: space,
                colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]) else { return }
            context.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                                       endCenter: point, endRadius: radius, options: [])
        }
        let film = CGGradient(colorsSpace: space,
            colors: [color.withAlphaComponent(0.18).cgColor,
                     color.withAlphaComponent(0.07).cgColor,
                     color.withAlphaComponent(0.32).cgColor] as CFArray,
            locations: [0, 0.62, 1])!
        context.drawRadialGradient(film, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: 0.49, options: [.drawsAfterEndLocation])
        // Nearby hues retain one distinct dominant color for each transparent bubble.
        for index in 0..<12 {
            let angle = CGFloat(index) / 12 * .pi * 2 + phase
            let tint = NSColor(calibratedHue: (hue + sin(angle) * 0.025 + 1).truncatingRemainder(dividingBy: 1), saturation: 0.65,
                               brightness: 1, alpha: 0.48)
            glow(tint, at: CGPoint(x: 0.5 + cos(angle) * 0.44, y: 0.5 + sin(angle) * 0.44), radius: 0.29)
        }
        for band in 0..<5 {
            let ribbon = CGMutablePath()
            for step in 0...160 {
                let angle = CGFloat(step) / 160 * .pi * 2
                let radius = 0.425 + CGFloat(band) * 0.009
                    + sin(angle * 7 + phase + CGFloat(band) * 0.8) * 0.014
                    + sin(angle * 13 - phase) * 0.006
                let point = CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
                if step == 0 { ribbon.move(to: point) } else { ribbon.addLine(to: point) }
            }
            context.addPath(ribbon)
            context.setStrokeColor(NSColor(calibratedHue: (hue + CGFloat(band) * 0.008).truncatingRemainder(dividingBy: 1),
                                           saturation: 0.52, brightness: 1, alpha: 0.16).cgColor)
            context.setLineWidth(0.006); context.strokePath()
        }
        // The rim follows the dominant hue and stays translucent.
        for step in 0..<180 {
            let angle = CGFloat(step) / 180 * .pi * 2
            context.addArc(center: center, radius: 0.482, startAngle: angle,
                           endAngle: angle + .pi * 2 / 180, clockwise: false)
            context.setStrokeColor(NSColor(calibratedHue: (hue + sin(angle) * 0.025 + 1).truncatingRemainder(dividingBy: 1),
                                           saturation: 0.4, brightness: 1, alpha: 0.65).cgColor)
            context.setLineWidth(0.005); context.strokePath()
        }
        glow(.white.withAlphaComponent(0.75), at: CGPoint(x: 0.30, y: 0.79), radius: 0.13)
        glow(.white.withAlphaComponent(0.63), at: CGPoint(x: 0.70, y: 0.58), radius: 0.065)
        glow(.white.withAlphaComponent(0.43), at: CGPoint(x: 0.47, y: 0.51), radius: 0.10)
        context.setLineCap(.round)
        for (radius, start, end, opacity, width) in [(0.455, 1.85, 2.43, 0.85, 0.016),
                                                   (0.46, 4.10, 4.95, 0.62, 0.011)] {
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.setStrokeColor(NSColor.white.withAlphaComponent(opacity).cgColor)
            context.setLineWidth(width); context.strokePath()
        }
        return context.makeImage()
    }
}

final class BallsView: NSView {
    var doubleClicked: (() -> Void)?
    private let restDigits = RestDigitsView()
    func displayRest(seconds: Int) {
        restDigits.seconds = seconds
        setAccessibilityValue("休息剩余 \(seconds / 60) 分 \(seconds % 60) 秒，双击结束")
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { doubleClicked?() }
    }
    private var clock: Timer?
    private var bubbles: [(layer: CALayer, color: NSColor)] = []
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private let palette: [NSColor] = [
        NSColor(srgbRed: 1, green: 0.35, blue: 0.49, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.55, blue: 1, alpha: 1),
        NSColor(srgbRed: 0.82, green: 0.96, blue: 0.13, alpha: 1),
        NSColor(srgbRed: 0.23, green: 0.85, blue: 0.79, alpha: 1),
        NSColor(srgbRed: 0.67, green: 0.35, blue: 1, alpha: 1),
        NSColor(srgbRed: 1, green: 0.37, blue: 0.26, alpha: 1)
    ]
    private lazy var bubbleImages = palette.compactMap { BubbleAppearance.image(color: $0) }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("休息倒计时，彩球提醒，双击结束")
        restDigits.frame = bounds; restDigits.autoresizingMask = [.width, .height]
        addSubview(restDigits)
        addBall()
        clock = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in self?.addBall() }
        RunLoop.main.add(clock!, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError() }
    func stop() { clock?.invalidate(); clock = nil }
    func burst() {
        stop()
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        restDigits.alphaValue = 0
        for (index, bubble) in bubbles.enumerated() {
            let ball = bubble.layer
            ball.removeAllAnimations()
            let delay = Double.random(in: 0...0.12)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.14
            fade.beginTime = CACurrentMediaTime() + delay
            fade.fillMode = .both; fade.isRemovedOnCompletion = false
            ball.add(fade, forKey: "burstFade")
            let expansion = CABasicAnimation(keyPath: "transform.scale")
            expansion.fromValue = 1; expansion.toValue = 1.15; expansion.duration = 0.14
            expansion.beginTime = fade.beginTime; expansion.fillMode = .both
            expansion.isRemovedOnCompletion = false; ball.add(expansion, forKey: "burstExpand")
            // Limit particle work after long rests while every bubble still pops and fades.
            guard index < 120 else { continue }
            let radius = ball.bounds.width / 2
            for part in 0..<8 {
                let angle = CGFloat(part) / 8 * .pi * 2 + CGFloat.random(in: -0.15...0.15)
                let shard = CAShapeLayer()
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: radius * 0.88,
                            startAngle: angle - 0.12, endAngle: angle + 0.12, clockwise: false)
                shard.path = path; shard.fillColor = nil
                shard.strokeColor = bubble.color.blended(withFraction: 0.45, of: .white)?.cgColor
                shard.lineWidth = max(1.5, radius * 0.025); shard.lineCap = .round
                shard.position = ball.position; layer.addSublayer(shard)
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(point: ball.position)
                move.toValue = NSValue(point: NSPoint(x: ball.position.x + cos(angle) * radius * 0.8,
                                                     y: ball.position.y + sin(angle) * radius * 0.8 - radius * 0.2))
                let dissolve = CABasicAnimation(keyPath: "opacity")
                dissolve.fromValue = 0.85; dissolve.toValue = 0
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = CGFloat.random(in: -0.35...0.35)
                let group = CAAnimationGroup(); group.animations = [move, dissolve, spin]
                group.duration = 0.48; group.beginTime = CACurrentMediaTime() + delay
                group.timingFunction = .init(name: .easeOut)
                group.fillMode = .both; group.isRemovedOnCompletion = false
                shard.add(group, forKey: "fragment")
            }
        }
        CATransaction.commit()
    }
    private func addBall() {
        guard let layer else { return }
        let scale = min(bounds.width / 1470, bounds.height / 956)
        let radius = CGFloat.random(in: 36...80) * max(0.5, scale)
        let ball = CALayer()
        ball.bounds = NSRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
        ball.position = NSPoint(x: CGFloat.random(in: 0...bounds.width), y: CGFloat.random(in: 0...bounds.height))
        let colorIndex = Int.random(in: 0..<bubbleImages.count)
        ball.contents = bubbleImages[colorIndex]
        bubbles.append((ball, palette[colorIndex]))
        ball.contentsGravity = .resizeAspect
        ball.contentsScale = window?.backingScaleFactor ?? 2
        ball.shadowColor = NSColor.black.cgColor
        ball.shadowOpacity = 0.08
        ball.shadowRadius = radius * 0.12
        ball.shadowOffset = CGSize(width: radius * 0.05, height: -radius * 0.08)
        ball.shadowPath = CGPath(ellipseIn: ball.bounds.insetBy(dx: radius * 0.04, dy: radius * 0.04), transform: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.insertSublayer(ball, at: 0)
        CATransaction.commit()
        let appear = CAKeyframeAnimation(keyPath: "transform.scale")
        appear.values = [0, 1.22, 0.92, 1]
        appear.keyTimes = [0, 0.55, 0.8, 1]; appear.duration = 0.65
        appear.timingFunctions = [.init(name: .easeOut), .init(name: .easeInEaseOut), .init(name: .easeOut)]
        let lift = CABasicAnimation(keyPath: "position.y")
        lift.fromValue = ball.position.y - radius * 0.5; lift.toValue = ball.position.y
        lift.duration = 0.4; lift.timingFunction = .init(name: .easeOut)
        ball.add(appear, forKey: "appear"); ball.add(lift, forKey: "pop")
        // Each bubble stays in the layer tree until the entire reminder is dismissed.
    }
}

final class AlarmController {
    private var windows: [ReminderWindow] = []
    private var views: [BallsView] = []
    private var watcher: Timer?
    private var countdown: RestCountdown?
    var dismissed: ((Bool) -> Void)?
    private var bursting = false
    private var burstSound: AVAudioPlayer?
    private var burstCompletion: Timer?
    func show(restMinutes: Int) {
        countdown = RestCountdown(minutes: restMinutes, at: Date())
        for screen in NSScreen.screens {
            let window = ReminderWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            let view = BallsView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.doubleClicked = { [weak self] in self?.burstAndDismiss() }
            view.displayRest(seconds: countdown!.remainingSeconds(at: Date()))
            window.contentView = view; window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window); views.append(view)
        }
        watcher = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(watcher!, forMode: .common)
    }
    private func tick() {
        guard let countdown else { return }
        let now = Date(), seconds = countdown.remainingSeconds(at: Date())
        views.forEach { $0.displayRest(seconds: seconds) }
        if countdown.isFinished(at: now) { dismiss(completed: true) }
    }
    private func burstAndDismiss() {
        guard !bursting, !windows.isEmpty else { return }
        bursting = true; watcher?.invalidate(); watcher = nil
        if let url = Bundle.main.url(forResource: "BubblePop", withExtension: "wav") {
            burstSound = try? AVAudioPlayer(contentsOf: url)
            burstSound?.volume = 0.4; burstSound?.play()
        }
        views.forEach { $0.burst() }
        let animationEndsAt = Date().addingTimeInterval(0.7)
        burstCompletion = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self, Date() >= animationEndsAt, self.burstSound?.isPlaying != true else { return }
            // finishAlarm stops the reminder music only after the water-pop sound finishes.
            self.dismiss()
        }
    }
    func dismiss(completed: Bool = false) {
        burstCompletion?.invalidate(); burstCompletion = nil
        bursting = false; burstSound?.stop(); burstSound = nil
        guard !windows.isEmpty else { return }
        watcher?.invalidate(); watcher = nil; countdown = nil
        views.forEach { $0.stop() }; views.removeAll()
        windows.forEach { $0.orderOut(nil); $0.close() }; windows.removeAll()
        dismissed?(completed)
    }
}

final class TimerSession: NSObject, NSWindowDelegate, NSPopoverDelegate {
    let id = UUID()
    let frameName: String
    weak var app: AppDelegate?
    var engine = TimerEngine(minutes: UserDefaults.standard.object(forKey: "minutes") as? Int ?? 25,
                             repeats: UserDefaults.standard.bool(forKey: "repeats"),
                             speedMultiplier: UserDefaults.standard.object(forKey: "speedMultiplier") as? Int ?? 1)
    let audio = AudioController()
    let window: TimerWindow
    let dial: DialView
    let soundPopover = NSPopover()
    var showingAlarm = false
    var closed = false
    private(set) var sizePercent = 100
    static let sizeOptions = [150, 120, 100, 80, 50]
    private(set) var opacityPercent = 100
    static let opacityOptions = [100, 75, 50, 25, 0]
    private static func size(for percent: Int) -> NSSize {
        let factor = CGFloat(percent) / 100
        return NSSize(width: DialView.windowSize.width * factor, height: DialView.windowSize.height * factor)
    }

    init(app: AppDelegate, number: Int, origin: NSPoint?) {
        self.app = app
        frameName = number == 1 ? "MinutesWindow" : "MinutesWindow-\(number)"
        window = TimerWindow(contentRect: NSRect(origin: .zero, size: DialView.windowSize), styleMask: .borderless, backing: .buffered, defer: false)
        dial = DialView(frame: NSRect(origin: .zero, size: DialView.windowSize))
        super.init()
        let savedSize = UserDefaults.standard.integer(forKey: "sizePercent")
        sizePercent = Self.sizeOptions.contains(savedSize) ? savedSize : 100
        let savedOpacity = UserDefaults.standard.object(forKey: "opacityPercent") as? Int ?? 100
        opacityPercent = Self.opacityOptions.contains(savedOpacity) ? savedOpacity : 100
        window.alphaValue = CGFloat(opacityPercent) / 100
        window.ignoresMouseEvents = opacityPercent == 0
        window.title = "Minutes2 \(number)"
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.level = app.stayOnTop ? .floating : .normal
        window.collectionBehavior = [.fullScreenAuxiliary]
        let restoredFrame = window.setFrameUsingName(frameName, force: true)
        let restoredOrigin = window.frame.origin
        window.setFrameAutosaveName(frameName)
        window.setContentSize(Self.size(for: sizePercent))
        let desiredOrigin: NSPoint?
        if origin == nil, let saved = UserDefaults.standard.string(forKey: "lastClosedTimerOrigin") {
            desiredOrigin = NSPointFromString(saved)
        } else if restoredFrame {
            desiredOrigin = restoredOrigin
        } else if let origin {
            desiredOrigin = NSPoint(x: origin.x + 36, y: origin.y - 36)
        } else { desiredOrigin = nil }
        if let desiredOrigin {
            let proposed = NSRect(origin: desiredOrigin, size: window.frame.size)
            let screen = NSScreen.screens.first { $0.visibleFrame.intersects(proposed) }
                ?? window.screen ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: min(max(visible.minX, desiredOrigin.x), visible.maxX - window.frame.width),
                                              y: min(max(visible.minY, desiredOrigin.y), visible.maxY - window.frame.height)))
            } else { window.setFrameOrigin(desiredOrigin) }
        } else { window.center() }
        dial.owner = self; window.contentView = dial; window.delegate = self
        dial.resize(to: Self.size(for: sizePercent))
        soundPopover.behavior = .transient; soundPopover.delegate = self
    }
    func setOpacity(_ percent: Int) {
        guard Self.opacityOptions.contains(percent), !closed else { return }
        soundPopover.close()
        opacityPercent = percent
        window.alphaValue = CGFloat(percent) / 100
        // A fully invisible clock must not intercept clicks on the desktop.
        window.ignoresMouseEvents = percent == 0
        UserDefaults.standard.set(percent, forKey: "opacityPercent")
        app?.sessionChanged(self)
    }
    func setSize(_ percent: Int) {
        guard Self.sizeOptions.contains(percent), !closed else { return }
        soundPopover.close()
        let previous = window.frame
        let size = Self.size(for: percent)
        var frame = NSRect(x: previous.midX - size.width / 2, y: previous.midY - size.height / 2,
                           width: size.width, height: size.height)
        if let visible = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        sizePercent = percent
        window.setFrame(frame, display: false)
        dial.resize(to: size)
        window.saveFrame(usingName: frameName)
        UserDefaults.standard.set(percent, forKey: "sizePercent")
        app?.sessionChanged(self)
    }
    func select(_ minutes: Int) {
        dial.closeMusicSelection()
        engine.select(minutes)
        UserDefaults.standard.set(engine.selectedMinutes, forKey: "minutes")
        app?.sessionChanged(self)
    }
    func setSpeed(_ multiplier: Int) {
        guard !closed, app?.isPresentingAlarm == false, engine.phase != .alarm,
              TimerEngine.speedOptions.contains(multiplier) else { return }
        let now = Date()
        engine.setSpeed(multiplier, at: now)
        UserDefaults.standard.set(engine.speedMultiplier, forKey: "speedMultiplier")
        if engine.tick(at: now) { app?.enqueueAlarm(self) }
        app?.sessionChanged(self)
    }
    func toggleTimer() {
        guard !closed, !dial.isChoosingMusic, app?.isPresentingAlarm == false, engine.phase != .alarm else { return }
        audio.stop(); soundPopover.close(); engine.toggle(at: Date())
        if engine.phase == .alarm { app?.enqueueAlarm(self) }
        app?.sessionChanged(self)
    }
    func resetTimer() {
        dial.closeMusicSelection()
        engine.reset(); audio.stop(); app?.cancelAlarm(id); app?.sessionChanged(self)
    }
    func showWindow() {
        guard !closed, app?.isPresentingAlarm == false else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(dial)
        app?.activateSession(self)
    }
    func showSounds() {
        guard !closed, app?.isPresentingAlarm == false, engine.phase != .alarm else { return }
        showWindow(); dial.openMusicSelection()
    }
    @discardableResult func chooseMusicFile() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.title = "选择到时播放的音乐"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard audio.validate(url) else {
            let alert = NSAlert(); alert.messageText = "无法播放此音乐文件"
            alert.informativeText = "请选择 MP3、M4A、WAV 或 AIFF 格式的音频。"; alert.runModal()
            return false
        }
        audio.customPath = url.path; audio.selection = "Custom"; dial.refresh()
        return true
    }
    func timerMenu() -> NSMenu {
        window.makeKeyAndOrderFront(nil); app?.activateSession(self)
        return app?.timerMenu(includeQuit: true) ?? NSMenu()
    }
    func popoverDidClose(_ notification: Notification) { if !showingAlarm { audio.stop() } }
    func windowDidBecomeKey(_ notification: Notification) { app?.activateSession(self) }
    func windowDidResignKey(_ notification: Notification) { dial.clearFocus() }
    func savePosition() {
        window.saveFrame(usingName: frameName)
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "lastClosedTimerOrigin")
    }
    func windowWillClose(_ notification: Notification) {
        savePosition()
        app?.removeSession(self)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var sessions: [TimerSession] = []
    private weak var lastActive: TimerSession?
    private var nextNumber = 1
    var stayOnTop = UserDefaults.standard.bool(forKey: "stayOnTop")
    private let alarm = AlarmController()
    private var alarms = TimerAlarms()
    var isPresentingAlarm: Bool { alarms.active != nil }
    private var ticker: Timer?
    private var statusItem: NSStatusItem!
    private var activity: NSObjectProtocol?
    private lazy var aboutWindow = AboutWindowController()
    private var dockIconWasDynamic = false
    private var dockLastUpdated: TimeInterval = 0
    private let defaultDockIcon = NSImage(named: "AppIcon")
    private var terminating = false
    private var restMinutes: Int = {
        let saved = UserDefaults.standard.integer(forKey: "restMinutes")
        return RestCountdown.minuteOptions.contains(saved) ? saved : 5
    }()
    private var clickMonitor: Any?
    private var active: TimerSession? {
        sessions.first(where: { $0.window === NSApp.keyWindow }) ?? lastActive ?? sessions.last
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Minutes2 番茄钟")
        alarm.dismissed = { [weak self] completed in self?.finishAlarm(completed: completed) }
        newTimer()
        ticker = Timer(timeInterval: 0.20, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            for session in self?.sessions ?? [] {
                if event.window !== session.window || !session.dial.containsDialPoint(session.dial.convert(event.locationInWindow, from: nil)) {
                    session.dial.clearFocus()
                }
            }
            return event
        }
        if CommandLine.arguments.contains("--demo-alarm") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.previewAlarm() }
        }
    }
    @objc private func newTimer() {
        if sessions.isEmpty { nextNumber = 1 }
        let session = TimerSession(app: self, number: nextNumber, origin: active?.window.frame.origin)
        nextNumber += 1; sessions.append(session); lastActive = session
        session.showWindow(); sessionChanged(session)
    }
    @objc private func closeTimer() { active?.window.close() }
    func removeSession(_ session: TimerSession) {
        guard !session.closed else { return }
        session.closed = true; session.soundPopover.close(); session.audio.stop(); session.dial.clearFocus()
        sessions.removeAll { $0 === session }
        if lastActive === session { lastActive = sessions.last }
        cancelAlarm(session.id)
        active?.showWindow(); refresh(); syncActivity()
    }
    func activateSession(_ session: TimerSession) { guard !session.closed else { return }; lastActive = session; refresh() }
    func sessionChanged(_ session: TimerSession) { session.dial.refresh(); syncActivity(); refresh() }
    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    func timerMenu(includeQuit: Bool = false, includeRest: Bool = false) -> NSMenu {
        let menu = NSMenu(title: "计时器")
        let new = menuItem("新建番茄钟", #selector(newTimer), key: "n")
        new.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil); menu.addItem(new)
        let close = menuItem("关闭番茄钟", #selector(closeTimer), key: "w")
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil); menu.addItem(close)
        menu.addItem(.separator())
        let toggle = menuItem(active?.engine.phase == .running ? "暂停计时" : "开始计时", #selector(toggleTimer), key: " ")
        toggle.keyEquivalentModifierMask = []; menu.addItem(toggle)
        let repeats = menuItem("重复计时", #selector(toggleRepeats)); repeats.state = active?.engine.repeats == true ? .on : .off
        menu.addItem(repeats)
        if includeRest {
            let item = NSMenuItem(title: "休息时间", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "休息时间")
            for minutes in RestCountdown.minuteOptions {
                let choice = menuItem("\(minutes) 分钟", #selector(changeRest(_:)))
                choice.tag = minutes; choice.state = minutes == restMinutes ? .on : .off
                submenu.addItem(choice)
            }
            item.submenu = submenu; menu.addItem(item)
        }
        menu.addItem(.separator())
        for (minutes, key, option) in [(1,"1",false), (3,"3",false), (5,"5",false), (10,"1",true), (20,"2",true), (30,"3",true), (50,"5",true), (60,"6",true)] {
            let item = menuItem("\(minutes) 分钟", #selector(preset(_:)), key: key)
            item.tag = minutes; item.keyEquivalentModifierMask = option ? [.command, .option] : [.command]
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("重置计时", #selector(resetTimer), key: "r"))
        menu.addItem(menuItem("到时音乐…", #selector(showSounds)))
        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(menuItem("退出 Minutes2", #selector(quit), key: "q"))
        }
        return menu
    }
    private func makeMenu() {
        let main = NSMenu()
        func add(_ title: String, _ menu: NSMenu) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = menu; main.addItem(item)
        }
        let appMenu = NSMenu(title: "Minutes2")
        appMenu.addItem(menuItem("关于 Minutes2", #selector(about)))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Minutes2", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部应用", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Minutes2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add("Minutes2", appMenu); add("计时器", timerMenu(includeRest: true))
        let view = NSMenu(title: "视图")
        view.addItem(menuItem("保持在前台", #selector(toggleTop))); view.addItem(.separator())
        view.addItem(menuItem("预览彩球提醒", #selector(previewAlarm))); view.addItem(.separator())
        let sizeItem = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "大小")
        for percent in TimerSession.sizeOptions {
            let item = menuItem("\(percent)%", #selector(changeSize(_:)))
            item.tag = percent; sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu; view.addItem(sizeItem)
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu(title: "透明度")
        for percent in TimerSession.opacityOptions {
            let item = menuItem("\(percent)%", #selector(changeOpacity(_:)))
            item.tag = percent; opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu; view.addItem(opacityItem)
        let speedItem = NSMenuItem(title: "倍速模式", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu(title: "倍速模式")
        for multiplier in TimerEngine.speedOptions {
            let item = menuItem(multiplier == 1 ? "正常速度（1 倍）" : "\(multiplier) 倍速", #selector(changeSpeed(_:)))
            item.tag = multiplier; speedMenu.addItem(item)
        }
        speedItem.submenu = speedMenu; view.addItem(speedItem)
        add("视图", view)
        let windows = NSMenu(title: "窗口")
        windows.addItem(menuItem("居中显示", #selector(centerWindow)))
        windows.addItem(menuItem("窗口置顶", #selector(toggleTop))); windows.addItem(.separator())
        windows.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        add("窗口", windows)
        let help = NSMenu(title: "帮助"); help.addItem(menuItem("Minutes2 使用说明", #selector(showUsage))); add("帮助", help)
        NSApp.mainMenu = main; NSApp.windowsMenu = windows; NSApp.helpMenu = help
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(newTimer): return !isPresentingAlarm
        case #selector(closeTimer): return active != nil
        case #selector(toggleTimer), #selector(showSounds): return active != nil && active?.engine.phase != .alarm && !isPresentingAlarm
        case #selector(preset(_:)): return (active?.engine.phase == .setting || active?.engine.phase == .paused) && !isPresentingAlarm
        case #selector(changeSpeed(_:)): return active != nil && active?.engine.phase != .alarm && !isPresentingAlarm
        case #selector(changeOpacity(_:)), #selector(changeSize(_:)), #selector(toggleRepeats), #selector(resetTimer), #selector(centerWindow): return active != nil && !isPresentingAlarm
        case #selector(previewAlarm): return active?.engine.phase == .setting && !isPresentingAlarm
        default: return true
        }
    }
    private func refresh() {
        statusItem?.menu = timerMenu()
        statusItem?.menu?.addItem(.separator())
        statusItem?.menu?.addItem(menuItem("显示番茄钟", #selector(showWindow), key: "0"))
        statusItem?.menu?.addItem(menuItem("退出 Minutes2", #selector(quit), key: "q"))
        NSApp.mainMenu?.items.first(where: { $0.title == "计时器" })?.submenu = timerMenu(includeRest: true)
        let view = NSApp.mainMenu?.items.first(where: { $0.title == "视图" })?.submenu
        for menu in [NSApp.windowsMenu, view] {
            menu?.items.first(where: { $0.action == #selector(toggleTop) })?.state = stayOnTop ? .on : .off
        }
        view?.items.first(where: { $0.title == "大小" })?.submenu?.items.forEach {
            $0.state = $0.tag == active?.sizePercent ? .on : .off
        }
        view?.items.first(where: { $0.title == "透明度" })?.submenu?.items.forEach {
            $0.state = $0.tag == active?.opacityPercent ? .on : .off
        }
        view?.items.first(where: { $0.title == "倍速模式" })?.submenu?.items.forEach {
            $0.state = $0.tag == active?.engine.speedMultiplier ? .on : .off
        }
        updateStatus()
    }
    @objc private func changeSpeed(_ sender: NSMenuItem) {
        guard validateMenuItem(sender) else { return }
        active?.setSpeed(sender.tag)
    }
    @objc private func changeRest(_ sender: NSMenuItem) {
        guard RestCountdown.minuteOptions.contains(sender.tag) else { return }
        restMinutes = sender.tag; UserDefaults.standard.set(restMinutes, forKey: "restMinutes"); refresh()
    }
    @objc private func changeOpacity(_ sender: NSMenuItem) {
        guard validateMenuItem(sender) else { return }
        active?.setOpacity(sender.tag)
    }
    @objc private func changeSize(_ sender: NSMenuItem) {
        guard validateMenuItem(sender) else { return }
        active?.setSize(sender.tag)
    }
    @objc private func toggleTimer() { active?.toggleTimer() }
    @objc private func resetTimer() { active?.resetTimer() }
    @objc private func preset(_ sender: NSMenuItem) {
        guard validateMenuItem(sender) else { return }; active?.select(sender.tag); active?.showWindow()
    }
    @objc private func toggleRepeats() {
        guard let active else { return }
        active.engine.repeats.toggle(); UserDefaults.standard.set(active.engine.repeats, forKey: "repeats"); refresh()
    }
    @objc private func showSounds() { active?.showSounds() }
    @objc private func showWindow() { if sessions.isEmpty { newTimer() } else { active?.showWindow() } }
    @objc private func centerWindow() { active?.window.center(); active?.showWindow() }
    @objc private func toggleTop() {
        stayOnTop.toggle(); UserDefaults.standard.set(stayOnTop, forKey: "stayOnTop")
        sessions.forEach { $0.window.level = stayOnTop ? .floating : .normal }; refresh()
    }
    @objc private func previewAlarm() {
        guard let active, active.engine.phase == .setting, !isPresentingAlarm else { return }
        enqueueAlarm(active, preview: true)
    }
    func enqueueAlarm(_ session: TimerSession, preview: Bool = false) {
        alarms.enqueue(session.id, preview: preview); presentNextAlarm(); refresh(); syncActivity()
    }
    func cancelAlarm(_ id: UUID) { if alarms.remove(id) { alarm.dismiss() } }
    private func presentNextAlarm() {
        guard !terminating, let request = alarms.next() else { return }
        guard let session = sessions.first(where: { $0.id == request.timerID }) else {
            alarms.dismiss(); presentNextAlarm(); return
        }
        session.showingAlarm = true; session.soundPopover.close(); session.audio.stop(); session.window.orderOut(nil)
        alarm.show(restMinutes: restMinutes); session.audio.play(loop: true)
    }
    private func finishAlarm(completed: Bool) {
        guard let request = alarms.dismiss() else { return }
        if let session = sessions.first(where: { $0.id == request.timerID }) {
            session.audio.stop(); session.showingAlarm = false
            if !terminating {
                if !request.preview {
                    session.engine.dismissAlarm(at: Date())
                }
                session.showWindow(); session.dial.refresh()
            }
        }
        guard !terminating else { return }
        presentNextAlarm(); syncActivity(); refresh()
    }
    private func tick() {
        let now = Date()
        var ended = false
        for session in sessions {
            if session.engine.tick(at: now) {
                session.window.orderOut(nil); alarms.enqueue(session.id); ended = true
            }
            if !session.showingAlarm { session.dial.refresh() }
        }
        presentNextAlarm()
        if ended { refresh(); syncActivity() } else { updateStatus() }
    }
    @objc private func wokeUp() { tick() }
    private func updateStatus() {
        updateDockIcon()
        guard let button = statusItem?.button else { return }
        let session = active?.engine.phase == .running ? active : sessions.filter { $0.engine.phase == .running }.min {
            $0.engine.remaining(at: Date()) < $1.engine.remaining(at: Date())
        } ?? active
        if let session, session.engine.phase == .running || session.engine.phase == .paused {
            let seconds = Int(ceil(session.engine.remaining(at: Date())))
            button.title = String(format: " %d:%02d%@", seconds / 60, seconds % 60, session.engine.phase == .paused ? " Ⅱ" : "")
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        } else { button.title = "" }
        button.toolTip = isPresentingAlarm ? "休息倒计时，双击结束提醒" : "Minutes2 · \(sessions.count) 个番茄钟"
    }
    private func updateDockIcon() {
        let now = Date()
        let running = active?.engine.phase == .running ? active : sessions.filter { $0.engine.phase == .running }.min {
            $0.engine.remaining(at: now) < $1.engine.remaining(at: now)
        }
        guard let running else {
            if dockIconWasDynamic { NSApp.applicationIconImage = defaultDockIcon; dockIconWasDynamic = false }
            return
        }
        let time = CACurrentMediaTime()
        guard !dockIconWasDynamic || time - dockLastUpdated >= 0.2 else { return }
        dockLastUpdated = time; dockIconWasDynamic = true
        NSApp.applicationIconImage = MinutesLogo.image(color: running.dial.dockColor,
            fraction: running.engine.remaining(at: now) / 3600)
    }
    private func syncActivity() {
        if isPresentingAlarm || sessions.contains(where: { $0.engine.phase == .running }) {
            if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Minutes2 倒计时") }
        } else { endActivity() }
    }
    private func endActivity() { if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil }
    @objc private func showUsage() {
        let alert = NSAlert(); alert.messageText = "Minutes2 使用说明"
        alert.informativeText = "第一次单击圆盘显示阴影，再次单击开始、暂停或继续。点击其他地方取消阴影。长按圆盘约 0.35 秒后拖动可移动番茄钟。暂停后可拖动时间圆点调整剩余分钟。\n\n计时器：⌘N 新建独立番茄钟，⌘W 关闭当前番茄钟，空格开始或暂停。重复计时开启后，休息倒计时结束后会自动开始下一轮。预设时长只在设时或暂停时可用。\n\n视图菜单可保持在前台或预览泡泡。到时泡泡持续叠加在桌面上；双击结束提醒。多个番茄钟到时会依次提醒。"
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
    @objc private func about() { aboutWindow.present() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidResignActive(_ notification: Notification) { sessions.forEach { $0.dial.clearFocus() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        terminating = true; ticker?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        sessions.forEach { $0.window.saveFrame(usingName: $0.frameName); $0.soundPopover.close(); $0.audio.stop() }
        active?.savePosition()
        alarm.dismiss(); endActivity(); NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
