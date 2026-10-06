import AppKit

/// Shared vector artwork for the ICNS representations and the live Dock icon.
enum MinutesLogo {
    static func draw(size n: CGFloat, color: NSColor? = nil, fraction: Double = 1) {
        let circleRect = NSRect(x: n * 0.018, y: n * 0.018, width: n * 0.964, height: n * 0.964)
        let circle = NSBezierPath(ovalIn: circleRect)
        if let color {
            NSGradient(colors: [color.blended(withFraction: 0.28, of: .white)!, color,
                                color.blended(withFraction: 0.10, of: .white)!])!.draw(in: circle, angle: 35)
        } else {
            NSGradient(colors: [NSColor(srgbRed: 1, green: 0.38, blue: 0.25, alpha: 1),
                                NSColor(srgbRed: 1, green: 0.18, blue: 0.36, alpha: 1)])!.draw(in: circle, angle: 90)
        }
        let progress = min(1, max(0, fraction))
        if progress > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: n / 2, y: n / 2), radius: n * 0.964 * 146 / 300,
                          startAngle: 90, endAngle: 90 - CGFloat(progress * 360), clockwise: true)
            arc.lineWidth = n * 0.964 * 8 / 300
            NSColor.white.setStroke(); arc.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        let enlarge = NSAffineTransform()
        enlarge.translateX(by: n / 2, yBy: n / 2)
        enlarge.scale(by: 0.94 / 0.82)
        enlarge.translateX(by: -n / 2, yBy: -n / 2)
        enlarge.concat()
        func stroke(_ points: [NSPoint], opacity: CGFloat) {
            let path = NSBezierPath(); path.move(to: points[0])
            for point in points.dropFirst() { path.line(to: point) }
            path.lineWidth = n * 0.062; path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(opacity).setStroke(); path.stroke()
        }
        stroke([NSPoint(x: n * 0.315, y: n * 0.655), NSPoint(x: n * 0.50, y: n * 0.455)], opacity: 0.65)
        stroke([NSPoint(x: n * 0.685, y: n * 0.655), NSPoint(x: n * 0.685, y: n * 0.34)], opacity: 0.55)
        stroke([NSPoint(x: n * 0.50, y: n * 0.455), NSPoint(x: n * 0.685, y: n * 0.655)], opacity: 1)
        stroke([NSPoint(x: n * 0.315, y: n * 0.34), NSPoint(x: n * 0.315, y: n * 0.655)], opacity: 1)
        let two = NSBezierPath()
        two.move(to: NSPoint(x: n * 0.76, y: n * 0.41))
        two.curve(to: NSPoint(x: n * 0.825, y: n * 0.385),
                  controlPoint1: NSPoint(x: n * 0.805, y: n * 0.455), controlPoint2: NSPoint(x: n * 0.865, y: n * 0.43))
        // 0.34 - 0.062/2 == 0.318 - 0.018/2: visible bottoms align exactly.
        two.line(to: NSPoint(x: n * 0.76, y: n * 0.318))
        two.line(to: NSPoint(x: n * 0.845, y: n * 0.318))
        two.lineWidth = n * 0.018; two.lineCapStyle = .round; two.lineJoinStyle = .round
        NSColor.white.setStroke(); two.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    static func image(color: NSColor, fraction: Double) -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
            draw(size: 256, color: color, fraction: fraction)
            return true
        }
    }
}
