import XCTest
import AppKit
import VictorMacKit
@testable import WalkieTalkie

final class PointerCaptureTests: XCTestCase {
    private let session = Date(timeIntervalSince1970: 100)
    private let press = CGPoint(x: 100, y: 200)

    func testClickCapturesOnceAtTheReleasePosition() {
        var gesture = PointerCaptureGesture()
        XCTAssertEqual(gesture.handle(.down, point: press, session: session), .consume)
        let release = CGPoint(x: 102, y: 201)
        XCTAssertEqual(gesture.handle(.dragged, point: release, session: session), .consume)
        XCTAssertEqual(gesture.handle(.up, point: release, session: session), .screenshot(point: release, session: session))
        XCTAssertEqual(gesture.handle(.up, point: release, session: session), .pass)
    }

    func testDragUsesThePressedCornerAndCapturesOnlyOnRelease() {
        var gesture = PointerCaptureGesture()
        let time = Date(timeIntervalSince1970: 103)
        _ = gesture.handle(.down, point: press, session: session, now: time)
        let corner = CGPoint(x: 360, y: 420)
        XCTAssertEqual(gesture.handle(.dragged, point: corner, session: session),
                       .beginArea(anchor: press, point: corner, at: time, session: session))
        let final = CGPoint(x: 400, y: 450)
        XCTAssertEqual(gesture.handle(.dragged, point: final, session: session), .moveArea(final))
        XCTAssertEqual(gesture.handle(.up, point: final, session: session), .endArea(final))
        XCTAssertEqual(gesture.handle(.up, point: final, session: session), .pass)
    }

    func testRecordingMustBeOpenAtThePressAndStillBeTheSamePrompt() {
        var gesture = PointerCaptureGesture()
        XCTAssertEqual(gesture.handle(.down, point: press, session: nil), .pass)
        XCTAssertEqual(gesture.handle(.up, point: press, session: session), .pass)
        _ = gesture.handle(.down, point: press, session: session)
        XCTAssertEqual(gesture.handle(.up, point: press, session: nil), .consume)
        _ = gesture.handle(.down, point: press, session: session)
        XCTAssertEqual(gesture.handle(.up, point: press, session: session.addingTimeInterval(1)), .consume)
    }

    func testStoppingDuringADragFinishesItWithoutRearmingAnotherPrompt() {
        var gesture = PointerCaptureGesture()
        _ = gesture.handle(.down, point: press, session: session)
        let corner = CGPoint(x: 400, y: 500)
        _ = gesture.handle(.dragged, point: corner, session: session)
        XCTAssertEqual(gesture.handle(.dragged, point: corner, session: nil), .endArea(corner))
        XCTAssertEqual(gesture.handle(.up, point: corner, session: session.addingTimeInterval(1)), .consume)
    }

    func testModifiedAndExcludedClicksPassThroughAsCompletePairs() {
        var gesture = PointerCaptureGesture()
        XCTAssertEqual(gesture.handle(.down, point: press, session: session, canArm: false), .pass)
        XCTAssertEqual(gesture.handle(.dragged, point: press, session: session), .pass)
        XCTAssertEqual(gesture.handle(.up, point: press, session: session), .pass)
    }

    func testTapRequiresControlAndDispatchesTheCaptureOnMain() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let point = CGPoint(x: screen.frame.midX,
                            y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.midY)
        let tap = HotkeyTap()
        tap.pointerCaptureSession = session
        let delivered = expectation(description: "capture reached main thread")
        tap.onPointerScreenshot = { _, owner in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(owner, self.session)
            delivered.fulfill()
        }
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                        mouseCursorPosition: point, mouseButton: .left))
        let up = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                      mouseCursorPosition: point, mouseButton: .left))
        // Bare clicks and every other modifier combination keep normal window interaction.
        let passingFlags: [CGEventFlags] = [[], .maskCommand, .maskShift, .maskAlternate,
                                    [.maskControl, .maskCommand], [.maskControl, .maskShift],
                                    [.maskControl, .maskAlternate]]
        for flags in passingFlags {
            down.flags = flags; up.flags = flags
            XCTAssertFalse(tap.primaryCapture(.leftMouseDown, down))
            XCTAssertFalse(tap.primaryCapture(.leftMouseUp, up))
        }
        down.flags = .maskControl
        XCTAssertTrue(tap.primaryCapture(.leftMouseDown, down))
        // Releasing Control before the mouse must still swallow the owned release.
        up.flags = []
        XCTAssertTrue(tap.primaryCapture(.leftMouseUp, up))
        wait(for: [delivered], timeout: 2)
    }

    func testControlDragRemainsOwnedAfterControlIsReleased() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let start = CGPoint(x: screen.frame.midX,
            y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.midY)
        let corner = CGPoint(x: start.x + 80, y: start.y + 60)
        let tap = HotkeyTap()
        tap.pointerCaptureSession = session
        let began = expectation(description: "Control-drag enables area capture")
        let ended = expectation(description: "mouse release ends that same area")
        tap.onPointerArea = { _, point, _, owner in
            XCTAssertEqual(point, corner)
            XCTAssertEqual(owner, self.session)
            began.fulfill()
        }
        tap.onPointerAreaEnd = { point in
            XCTAssertEqual(point, corner)
            ended.fulfill()
        }
        let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: start, mouseButton: .left))
        down.flags = .maskControl
        XCTAssertTrue(tap.primaryCapture(.leftMouseDown, down))
        let drag = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
            mouseCursorPosition: corner, mouseButton: .left))
        drag.flags = []
        XCTAssertTrue(tap.primaryCapture(.leftMouseDragged, drag))
        let up = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: corner, mouseButton: .left))
        up.flags = []
        XCTAssertTrue(tap.primaryCapture(.leftMouseUp, up))
        wait(for: [began, ended], timeout: 2, enforceOrder: true)
    }

    func testSelectionOverlayDimsOutsideTheRectangle() throws {
        let size = NSSize(width: 900, height: 540)
        let selection = NSRect(x: 180, y: 150, width: 480, height: 260)
        let image = try XCTUnwrap(CropSelectionOverlay.snapshot(size: size,
            style: AppDelegate.pointerCropStyle, selection: selection,
            cursor: NSPoint(x: selection.maxX, y: selection.maxY)))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let outside = try XCTUnwrap(bitmap.colorAt(x: 40, y: 40)?.usingColorSpace(.deviceRGB))
        let inside = try XCTUnwrap(bitmap.colorAt(x: 400, y: 280)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(outside.redComponent, 0.8)
        XCTAssertEqual(outside.redComponent, outside.greenComponent, accuracy: 0.01)
        XCTAssertGreaterThan(inside.redComponent, 0.95)
        if let directory = ProcessInfo.processInfo.environment["POINTER_CAPTURE_PNG_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: url.appendingPathComponent("region-selection.png"))
        }
    }
}
