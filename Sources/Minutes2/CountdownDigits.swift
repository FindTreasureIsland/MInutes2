import AppKit

/// Rounded, partially translucent strokes based on the supplied 0–9 references.
/// Paths use a downward y axis; the timer view is flipped.
enum CountdownDigits {
    private struct Stroke {
        let path: NSBezierPath
        let opacity: CGFloat
    }

    static func draw(_ value: Int, in rect: NSRect, height: CGFloat = 96) {
        let digits = String(max(0, value)).compactMap(\.wholeNumberValue)
        let scale = height / 94
        let gap: CGFloat = 9
        let width = digits.reduce(CGFloat(0)) { $0 + advance($1) } + CGFloat(max(0, digits.count - 1)) * gap
        var x = rect.midX - width * scale / 2
        let y = rect.midY - height / 2
        for digit in digits {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: x, yBy: y)
            transform.scale(by: scale)
            transform.concat()
            for stroke in strokes(digit) {
                stroke.path.lineWidth = 8
                stroke.path.lineCapStyle = .round
                stroke.path.lineJoinStyle = .round
                NSColor.white.withAlphaComponent(stroke.opacity).setStroke()
                stroke.path.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
            x += (advance(digit) + gap) * scale
        }
    }

    static func drawTime(seconds: Int, in rect: NSRect, height: CGFloat) {
        let value = max(0, seconds)
        let text = String(format: "%02d:%02d", value / 60, value % 60)
        let scale = height / 94
        let gap: CGFloat = 9
        let widths = text.map { $0.wholeNumberValue.map(advance) ?? 22 }
        let width = widths.reduce(0, +) + CGFloat(text.count - 1) * gap
        var x = rect.midX - width * scale / 2
        for (index, character) in text.enumerated() {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: x, yBy: rect.midY - height / 2)
            transform.scale(by: scale); transform.concat()
            NSColor.white.setFill(); NSColor.white.setStroke()
            if let digit = character.wholeNumberValue {
                for stroke in strokes(digit) {
                    stroke.path.lineWidth = 8; stroke.path.lineCapStyle = .round; stroke.path.lineJoinStyle = .round
                    stroke.path.stroke()
                }
            } else {
                for y in [CGFloat(30), CGFloat(62)] {
                    NSBezierPath(ovalIn: NSRect(x: 7, y: y, width: 8, height: 8)).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            x += (widths[index] + gap) * scale
        }
    }

    private static func advance(_ digit: Int) -> CGFloat { digit == 1 ? 40 : 68 }
    private static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
    private static func path(_ x: CGFloat, _ y: CGFloat, _ build: (NSBezierPath) -> Void) -> NSBezierPath {
        let p = NSBezierPath(); p.move(to: point(x, y)); build(p); return p
    }
    private static func line(_ p: NSBezierPath, _ x: CGFloat, _ y: CGFloat) { p.line(to: point(x, y)) }
    private static func curve(_ p: NSBezierPath, _ x1: CGFloat, _ y1: CGFloat,
                              _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        p.curve(to: point(x, y), controlPoint1: point(x1, y1), controlPoint2: point(x2, y2))
    }
    private static func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h))
    }
    private static func faint(_ p: NSBezierPath) -> Stroke { Stroke(path: p, opacity: 0.45) }
    private static func white(_ p: NSBezierPath) -> Stroke { Stroke(path: p, opacity: 1) }

    private static func strokes(_ digit: Int) -> [Stroke] {
        switch digit {
        case 0:
            return [faint(ellipse(4, 4, 60, 86)), white(path(34, 4) {
                curve($0, 53, 4, 64, 21, 64, 47)
                curve($0, 64, 72, 53, 90, 34, 90)
            })]
        case 1:
            return [faint(path(8, 22) { line($0, 30, 4) }),
                    white(path(30, 4) { line($0, 30, 90) })]
        case 2:
            return [faint(path(8, 90) { line($0, 60, 90) }), white(path(8, 16) {
                curve($0, 25, -3, 52, 0, 58, 16)
                curve($0, 71, 36, 49, 56, 8, 90)
            })]
        case 3:
            return [faint(path(8, 17) {
                curve($0, 22, -1, 47, -1, 57, 8)
                curve($0, 69, 25, 58, 46, 39, 46)
                line($0, 20, 46)
            }), white(path(8, 17) {
                curve($0, 22, -1, 47, -1, 57, 8)
                curve($0, 60, 11, 61, 13, 62, 16)
            }), white(path(20, 46) {
                line($0, 38, 46)
                curve($0, 69, 45, 69, 73, 55, 84)
                curve($0, 40, 97, 17, 91, 6, 80)
            })]
        case 4:
            return [faint(path(64, 68) { line($0, 4, 68); line($0, 56, 4); line($0, 56, 90) }),
                    white(path(4, 68) { line($0, 56, 4) }),
                    white(path(56, 47) { line($0, 56, 90) })]
        case 5:
            return [faint(path(14, 4) { line($0, 14, 39) }),
                    white(path(14, 4) { line($0, 56, 4) }), white(path(14, 39) {
                line($0, 36, 39)
                curve($0, 67, 39, 73, 68, 54, 83)
                curve($0, 41, 94, 20, 92, 10, 80)
            })]
        case 6:
            return [faint(ellipse(8, 38, 56, 52)), white(path(52, 4) {
                curve($0, 25, 18, 8, 41, 8, 63)
                curve($0, 8, 81, 19, 90, 36, 90)
                curve($0, 52, 90, 64, 79, 64, 64)
            })]
        case 7:
            return [faint(path(60, 4) { line($0, 20, 90) }),
                    white(path(4, 4) { line($0, 60, 4) }),
                    white(path(40, 47) { line($0, 20, 90) })]
        case 8:
            return [faint(ellipse(8, 4, 52, 40)), faint(ellipse(4, 44, 60, 46)),
                    white(path(34, 4) {
                        curve($0, 18, 4, 8, 12, 8, 24)
                        curve($0, 8, 38, 19, 44, 34, 44)
                    }), white(path(34, 44) {
                        curve($0, 54, 44, 64, 52, 64, 68)
                        curve($0, 64, 81, 52, 90, 34, 90)
                    })]
        case 9:
            return [faint(ellipse(4, 4, 60, 54)), white(path(34, 58) {
                curve($0, 17, 58, 4, 47, 4, 31)
                curve($0, 4, 15, 17, 4, 34, 4)
                curve($0, 53, 4, 65, 16, 64, 36)
                curve($0, 63, 63, 48, 78, 23, 90)
            })]
        default: return []
        }
    }
}
