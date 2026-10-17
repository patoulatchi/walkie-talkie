import XCTest
import Darwin
@testable import WalkieTalkie

final class GhosttyBridgeTests: XCTestCase {
    private let surfaceID = "F010CD04-34B8-4A06-9837-EFD78F08583A"

    func testMetadataHandlesOldAndNewGhosttyWithoutGuessingTTY() throws {
        let old = try XCTUnwrap(GhosttyBridge.parse("\(surfaceID)\u{1f}\u{1f}/tmp/project\u{1f}a, title\nnext line\n"))
        XCTAssertNil(old.tty)
        XCTAssertEqual(old.title, "a, title\nnext line")
        XCTAssertEqual(old.directory, "/tmp/project")
        let new = try XCTUnwrap(GhosttyBridge.parse("\(surfaceID)\u{1f}/dev/ttys001\u{1f}\u{1f}"))
        XCTAssertEqual(new.tty, "/dev/ttys001")
        XCTAssertNil(new.directory)
        XCTAssertNil(GhosttyBridge.parse("missing"))
        XCTAssertNil(GhosttyBridge.parse("invalid\u{1f}\u{1f}\u{1f}"))
        XCTAssertFalse(TerminalBinding.isBindable(bundleID: "com.google.Chrome"))
        XCTAssertTrue(TerminalBinding.isBindable(bundleID: GhosttyBridge.bundleID))
    }

    func testRawTextEncodingPreservesUTF8AndLiteralEscapes() {
        XCTAssertEqual(GhosttyBridge.textAction("ă 🎤\\\n\""), "text:ă\\x20🎤\\x5c\\x0a\\x22")
    }

    func testRestoreNamesTheSurfaceRatherThanAnActiveTabOrReusedTTY() {
        XCTAssertEqual(TerminalBinding.Handle.ghostty(id: surfaceID, tty: "/dev/ttys001").restoreKey,
                       "ghostty:" + surfaceID)
        XCTAssertNil(TerminalBinding.Handle.ghostty(id: surfaceID, tty: nil).tty)
    }

    /// Opt-in: create two disposable raw-mode terminals and verify delivery stays
    /// on the first surface while the second is focused. No existing terminal
    /// receives input. Run with WT_GHOSTTY_INTEGRATION=1 swift test --filter ...
    func testLiveDeliveryRemainsOnBoundSurface() throws {
        guard ProcessInfo.processInfo.environment["WT_GHOSTTY_INTEGRATION"] == "1" else {
            throw XCTSkip("requires a running Ghostty 1.3+ and Automation access")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("walkie-ghostty-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let helper = dir.appendingPathComponent("reader.py")
        try """
        import os, sys, tty
        tty.setraw(0)
        with open(sys.argv[1] + '.ready', 'w') as f: f.write(str(os.getpid()))
        while True:
            data = os.read(0, 4096)
            if not data: break
            with open(sys.argv[1], 'ab') as f: f.write(data)
        """.write(to: helper, atomically: true, encoding: .utf8)
        var created: [String] = []
        defer {
            for n in 0..<2 {
                if let value = try? String(contentsOf: dir.appendingPathComponent("\(n).ready")),
                   let pid = Int32(value) { _ = kill(pid, SIGTERM) }
            }
            Thread.sleep(forTimeInterval: 0.1)
            for id in created {
                _ = TerminalBinding.osascriptOutcome("tell application id \"\(GhosttyBridge.bundleID)\"\nif exists terminal id \"\(id)\" then close (terminal id \"\(id)\")\nend tell")
            }
        }
        for n in 0..<2 {
            let result = TerminalBinding.osascriptOutcome("""
            tell application id "\(GhosttyBridge.bundleID)"
                set cfg to new surface configuration
                set command of cfg to "/usr/bin/python3 \(helper.path) \(dir.path)/\(n)"
                set w to new window with configuration cfg
                return id of focused terminal of selected tab of w
            end tell
            """)
            let id = try XCTUnwrap(result.output?.trimmingCharacters(in: .whitespacesAndNewlines), result.reason)
            XCTAssertNotNil(UUID(uuidString: id))
            created.append(id)
        }
        let ready = dir.appendingPathComponent("1.ready")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path))
        let surface = try XCTUnwrap(GhosttyBridge.read(id: created[0]).surface)
        XCTAssertTrue(GhosttyBridge.focus(id: created[1]))
        let binding = TerminalBinding()
        let restored = try XCTUnwrap(binding.resolve(tty: "ghostty:" + created[0]))
        XCTAssertEqual(restored.handle, .ghostty(id: surface.id, tty: surface.tty))
        let target = TerminalBinding.Target(handle: .ghostty(id: surface.id, tty: surface.tty),
            label: "test", address: "ghostty:" + surface.id, appName: "Ghostty", bundleID: GhosttyBridge.bundleID,
            sourceFrame: nil, boundAt: Date())
        let text = "literal \\n \"quotes\" $(date) `whoami`\năîșțâ 🎤"
        let result = binding.deliver(text, to: target)
        guard case .delivered = result else { return XCTFail("delivery failed: \(result)") }
        let output = dir.appendingPathComponent("0")
        let until = Date().addingTimeInterval(3)
        var received = Data()
        repeat {
            received = (try? Data(contentsOf: output)) ?? Data()
            if received.last == 13 { break }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < until
        XCTAssertEqual(String(data: received, encoding: .utf8), TerminalBinding.singleLine(text) + "\r")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1").path))
        // A guarded target cannot downgrade when Ghostty stops supplying its tty.
        if surface.tty == nil {
            let guarded = TerminalBinding.Target(handle: .ghostty(id: surface.id, tty: "/dev/ttys999"),
                label: "test", address: target.address, appName: "Ghostty", bundleID: GhosttyBridge.bundleID,
                sourceFrame: nil, boundAt: Date())
            guard case .failed = binding.deliver("must not arrive", to: guarded) else {
                return XCTFail("a guarded binding lost its shell guard")
            }
        }
        let pid = try XCTUnwrap(Int32(try String(contentsOf: dir.appendingPathComponent("0.ready"))))
        _ = kill(pid, SIGTERM)
        let exitDeadline = Date().addingTimeInterval(2)
        while kill(pid, 0) == 0, Date() < exitDeadline { Thread.sleep(forTimeInterval: 0.05) }
        _ = TerminalBinding.osascriptOutcome("tell application id \"\(GhosttyBridge.bundleID)\" to close (terminal id \"\(created[0])\")")
        let closed = created[0]
        let closeDeadline = Date().addingTimeInterval(3)
        while !GhosttyBridge.read(id: closed).missing, Date() < closeDeadline { Thread.sleep(forTimeInterval: 0.05) }
        let closedResult = binding.deliver("must not reach the other terminal", to: target)
        guard case .targetGone = closedResult else {
            return XCTFail("a closed surface was not reported gone: \(closedResult), read: \(GhosttyBridge.read(id: closed))")
        }
        XCTAssertTrue(GhosttyBridge.read(id: closed).missing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1").path))
        XCTAssertTrue(GhosttyBridge.read(id: UUID().uuidString).missing)
    }
}
