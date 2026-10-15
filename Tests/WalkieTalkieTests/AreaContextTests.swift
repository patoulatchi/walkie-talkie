import XCTest
import AppKit
@testable import WalkieTalkie

/// **The whole screen behind a ✂️ cut-out** (2026-10-15): the corners come back
/// out of the token `ShotMarker.Token.area` wrote, and the drawing greys the
/// outside, keeps the box clear and rings it red (a move's second box green).
/// `AREA_CONTEXT_PNG=<dir>` writes the two drawings for a look.
final class AreaContextTests: XCTestCase {
    func testCornersOfAnArea() {
        let token = ShotMarker.Token.area(3, CGRect(x: 900, y: 345, width: 1694, height: 229))
        let c = AreaContext.corners(in: token)
        XCTAssertEqual(c?.box, CGRect(x: 900, y: 345, width: 1694, height: 229))
        XCTAssertNil(c?.movedTo)
    }

    func testCornersOfAMove() {
        let token = ShotMarker.Token.area(1, CGRect(x: 10, y: 20, width: 30, height: 40),
                                          movedTo: CGRect(x: 100, y: 200, width: 50, height: 60))
        let c = AreaContext.corners(in: token)
        XCTAssertEqual(c?.box, CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(c?.movedTo, CGRect(x: 100, y: 200, width: 50, height: 60))
    }

    func testNotAnArea() {
        XCTAssertNil(AreaContext.corners(in: "[📸2🖱️@1204:388]"))
        XCTAssertNil(AreaContext.corners(in: "[selected: \"x\"]"))
    }

    func testTheBoxIsClearTheRestGreyTheRingRed() throws {
        let rep = try draw(box: CGRect(x: 100, y: 50, width: 100, height: 60), movedTo: nil)
        // Inside the box: the frame's own white.
        XCTAssertGreaterThan(brightness(rep, 150, 80), 0.95)
        // Outside: greyed well below it.
        XCTAssertLessThan(brightness(rep, 20, 20), 0.5)
        // On the ring (just outside the top edge): red.
        let ring = color(rep, 150, 49)
        XCTAssertGreaterThan(ring.redComponent, 0.7)
        XCTAssertLessThan(ring.greenComponent, 0.5)
    }

    func testAMoveRingsTheDestinationGreen() throws {
        let rep = try draw(box: CGRect(x: 20, y: 20, width: 60, height: 40),
                           movedTo: CGRect(x: 200, y: 130, width: 60, height: 40))
        let ring = color(rep, 230, 129)
        XCTAssertGreaterThan(ring.greenComponent, 0.6)
        XCTAssertLessThan(ring.redComponent, 0.5)
        // The destination is clear too.
        XCTAssertGreaterThan(brightness(rep, 215, 140), 0.95)
    }

    // MARK: -

    /// A white 320 × 200 frame drawn at 1:1, so a point is a pixel.
    private func draw(box: CGRect, movedTo: CGRect?) throws -> NSBitmapImageRep {
        let frame = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { r in
            NSColor.white.setFill(); r.fill(); return true
        }
        let image = AreaContext.image(frame: frame, pixels: CGSize(width: 320, height: 200),
                                      box: box, movedTo: movedTo, size: NSSize(width: 320, height: 200))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 320, height: 200))
        NSGraphicsContext.restoreGraphicsState()
        if let dir = ProcessInfo.processInfo.environment["AREA_CONTEXT_PNG"],
           let png = rep.representation(using: .png, properties: [:]) {
            let name = movedTo == nil ? "area.png" : "move.png"
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        return rep
    }

    /// `x, y` from the top-left, like the corners.
    private func color(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        (rep.colorAt(x: x, y: y) ?? .clear).usingColorSpace(.deviceRGB) ?? .clear
    }
    private func brightness(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        let c = color(rep, x, y)
        return (c.redComponent + c.greenComponent + c.blueComponent) / 3
    }
}
