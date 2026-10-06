import AppKit

private final class AboutBackgroundView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 1, green: 0.96, blue: 0, alpha: 1).setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        context.scaleBy(x: bounds.width / 720, y: bounds.height / 360)
        func wash(_ color: NSColor, center: CGPoint, radius: CGFloat) {
            let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
        }
        wash(NSColor(srgbRed: 1, green: 0.12, blue: 0.37, alpha: 1), center: CGPoint(x: 105, y: 20), radius: 540)
        wash(NSColor(srgbRed: 0, green: 0.78, blue: 0.79, alpha: 1), center: CGPoint(x: 80, y: 410), radius: 530)
        wash(NSColor(srgbRed: 0.46, green: 0.92, blue: 0.03, alpha: 1), center: CGPoint(x: 720, y: 390), radius: 460)
    }
}

final class AboutWindowController: NSWindowController {
    init() {
        let scale: CGFloat = 0.5
        func scaled(_ rect: NSRect) -> NSRect {
            NSRect(x: rect.minX * scale, y: rect.minY * scale,
                   width: rect.width * scale, height: rect.height * scale)
        }
        let window = NSWindow(contentRect: scaled(NSRect(x: 0, y: 0, width: 720, height: 360)),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "关于 Minutes2"
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.center()
        let content = AboutBackgroundView(frame: scaled(NSRect(x: 0, y: 0, width: 720, height: 360)))
        window.contentView = content
        let logo = NSImageView(frame: scaled(NSRect(x: 100, y: 82, width: 136, height: 136)))
        logo.image = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityLabel("Minutes2 Logo")
        content.addSubview(logo)
        func label(_ text: String, frame: NSRect, size: CGFloat, color: NSColor,
                   alignment: NSTextAlignment = .left, weight: NSFont.Weight = .regular) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = scaled(frame); field.textColor = color; field.font = .systemFont(ofSize: size * scale, weight: weight)
            field.alignment = alignment; field.isSelectable = true
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
            paragraph.minimumLineHeight = 28 * scale; paragraph.maximumLineHeight = 28 * scale
            field.attributedStringValue = NSAttributedString(string: text,
                attributes: [.font: field.font!, .foregroundColor: color, .paragraphStyle: paragraph])
            content.addSubview(field)
        }
        label("Minutes2", frame: NSRect(x: 65, y: 239, width: 206, height: 40), size: 28,
              color: .white, alignment: .center, weight: .semibold)
        label("致敬", frame: NSRect(x: 282, y: 82, width: 124, height: 30), size: 21, color: .white, alignment: .right)
        label("HANDS MEMORY", frame: NSRect(x: 425, y: 82, width: 270, height: 30), size: 21, color: .black)
        label("感谢", frame: NSRect(x: 282, y: 128, width: 124, height: 30), size: 21, color: .white, alignment: .right)
        label("Yosuke Ito\nYuri Miyauchi\nK Sasaki\nKenzo Yamaguchi",
              frame: NSRect(x: 425, y: 128, width: 270, height: 116), size: 21, color: .black)
        label("开发人员", frame: NSRect(x: 282, y: 258, width: 124, height: 30), size: 21, color: .white, alignment: .right)
        label("Whiplasher", frame: NSRect(x: 425, y: 258, width: 270, height: 30), size: 21, color: .black)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        label("Minutes2 · 版本 \(version)", frame: NSRect(x: 30, y: 322, width: 660, height: 28),
              size: 13, color: .white, alignment: .center)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
}
