import AppKit

enum CrabStatusIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = rect.width / 18
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.1 * scale)
            context.setLineCap(.round)

            NSBezierPath(
                roundedRect: NSRect(x: 4.5 * scale, y: 4 * scale, width: 9 * scale, height: 6.5 * scale),
                xRadius: 3 * scale,
                yRadius: 3 * scale
            ).fill()

            func line(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) {
                context.move(to: CGPoint(x: ax * scale, y: ay * scale))
                context.addLine(to: CGPoint(x: bx * scale, y: by * scale))
                context.strokePath()
            }
            line(6.7, 10.5, 6.7, 11.8)
            line(11.3, 10.5, 11.3, 11.8)

            for x in [CGFloat(6.7), 11.3] {
                context.fillEllipse(in: CGRect(x: (x - 0.8) * scale, y: 11.7 * scale, width: 1.6 * scale, height: 1.6 * scale))
            }
            for (leftY, rightY) in [(8.5, 9.4), (7.5, 8.1), (6.6, 6.8)] {
                line(4.8, leftY, 2.2, rightY)
                line(13.2, leftY, 15.8, rightY)
            }

            context.setLineWidth(1.3 * scale)
            line(4.5, 9.2, 2.5, 12.2)
            line(13.5, 9.2, 15.5, 12.2)

            func claw(_ tip: CGPoint, _ a: CGPoint, _ b: CGPoint) {
                context.move(to: CGPoint(x: tip.x * scale, y: tip.y * scale))
                context.addLine(to: CGPoint(x: a.x * scale, y: a.y * scale))
                context.addLine(to: CGPoint(x: b.x * scale, y: b.y * scale))
                context.closePath()
                context.fillPath()
            }
            claw(CGPoint(x: 1.2, y: 12.5), CGPoint(x: 2.6, y: 14.8), CGPoint(x: 4.2, y: 12.8))
            claw(CGPoint(x: 16.8, y: 12.5), CGPoint(x: 15.4, y: 14.8), CGPoint(x: 13.8, y: 12.8))
            return true
        }
        image.isTemplate = true
        return image
    }
}
