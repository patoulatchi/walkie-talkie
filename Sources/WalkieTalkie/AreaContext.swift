import AppKit

/// **The whole screen behind a ✂️ cut-out, with the cut lit and the rest
/// greyed** (2026-10-15).
///
/// Victor: *"When you explain in the prompt preview the images that were
/// cropped, be sure to put after them a picture of the entire screen that was
/// captured … grayed out the rest and highlighting basically fully transparent
/// the area that was selected … bordered in a bit of red rectangle, so it's
/// clear that I'm sending also the entire screen."* The agent does get the whole
/// frame with every area; the cut-out alone hid that.
///
/// **A move draws both boxes and the arrow** (same evening: *"the two, red and
/// the green ones, from where to where with an arrow in the screen, in a
/// thumbnail"*): the source red, the destination green, a white arrow between
/// their centres — the colours the live overlay uses for the same gesture
/// (`AppDelegate.cropStyle`).
///
/// Drawn, never written to disk: it is the panel's picture of a token, and the
/// files the agent reads stay exactly what they were.
enum AreaContext {
    static let sourceColor = NSColor.systemRed
    static let destinationColor = NSColor.systemGreen
    static let arrowColor = NSColor.white

    /// The greyed part — dark enough that the lit box is where the eye lands,
    /// light enough that the screen is still recognisably his.
    private static let veil = NSColor(calibratedWhite: 0.08, alpha: 0.62)

    /// The corners in a `[📸N✂️x1,y1→x2,y2]` token, and the second box of a
    /// `… moved to x1,y1→x2,y2` — in the frame's pixels, top-left origin, as
    /// `ShotMarker.Token.area` wrote them. Nil for every other token.
    static func corners(in token: String) -> (box: CGRect, movedTo: CGRect?)? {
        let pair = #"(\d+),(\d+)→(\d+),(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: "✂️" + pair + "(?: moved to " + pair + ")?"),
              let m = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token))
        else { return nil }
        func number(_ i: Int) -> CGFloat? {
            Range(m.range(at: i), in: token).flatMap { Double(token[$0]) }.map { CGFloat($0) }
        }
        func rect(_ first: Int) -> CGRect? {
            guard let x1 = number(first), let y1 = number(first + 1),
                  let x2 = number(first + 2), let y2 = number(first + 3) else { return nil }
            return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        }
        guard let box = rect(1) else { return nil }
        return (box, rect(5))
    }

    /// The frame at `size`, greyed outside the box(es), each box ringed in its
    /// colour, and the arrow for a move. `pixels` is the size the corners are
    /// measured in — the original frame's, not the copy being drawn.
    static func image(frame: NSImage, pixels: CGSize, box: CGRect, movedTo: CGRect?, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { bounds in
            frame.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                       respectFlipped: true, hints: nil)
            let k = bounds.width / max(pixels.width, 1)
            func scaled(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)
            }
            let boxes = [scaled(box)] + (movedTo.map { [scaled($0)] } ?? [])
            // Even-odd with the boxes as holes; two that overlap would cancel
            // each other's hole, so they are unioned first.
            let veilPath = NSBezierPath(rect: bounds)
            let holes = boxes.count == 2 && boxes[0].intersects(boxes[1]) ? [boxes[0].union(boxes[1])] : boxes
            holes.forEach { veilPath.appendRect($0) }
            veilPath.windingRule = .evenOdd
            veil.setFill()
            veilPath.fill()

            let line: CGFloat = 2
            for (i, rect) in boxes.enumerated() {
                (i == 0 ? sourceColor : destinationColor).setStroke()
                let ring = NSBezierPath(rect: rect.insetBy(dx: -line / 2, dy: -line / 2))
                ring.lineWidth = line
                ring.stroke()
            }
            if boxes.count == 2 {
                arrow(from: CGPoint(x: boxes[0].midX, y: boxes[0].midY),
                      to: CGPoint(x: boxes[1].midX, y: boxes[1].midY))
            }
            return true
        }
    }

    /// A white shaft and a filled head, with a dark halo so it reads on a white
    /// page as well as a dark one.
    private static func arrow(from a: CGPoint, to b: CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 4 else { return }
        let ux = dx / length, uy = dy / length
        let head = min(10, length * 0.4)
        let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        let shaft = NSBezierPath()
        shaft.move(to: a)
        shaft.line(to: base)
        shaft.lineWidth = 2
        shaft.lineCapStyle = .round
        let tip = NSBezierPath()
        tip.move(to: b)
        tip.line(to: CGPoint(x: base.x - uy * head * 0.55, y: base.y + ux * head * 0.55))
        tip.line(to: CGPoint(x: base.x + uy * head * 0.55, y: base.y - ux * head * 0.55))
        tip.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        shadow.set()
        arrowColor.setStroke()
        arrowColor.setFill()
        shaft.stroke()
        tip.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
