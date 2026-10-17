import AppKit

/// Ghostty 1.3+ exposes stable surface IDs: a split remains the destination
/// even when another tab or split gains focus. Never fall back to a paste.
enum GhosttyBridge {
    static let bundleID = "com.mitchellh.ghostty"
    static let restorePrefix = "ghostty:"

    struct Surface: Equatable {
        let id: String
        let tty: String?
        let directory: String?
        let title: String?
    }

    static func parse(_ output: String) -> Surface? {
        let fields = output.trimmingCharacters(in: .newlines)
            .split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, UUID(uuidString: fields[0]) != nil else { return nil }
        // Older Ghostty dictionaries do not expose a tty. Never guess one from
        // a folder or title: multiple surfaces can run in the same repository.
        let tty = fields[1].hasPrefix("/dev/tty") ? fields[1] : nil
        return Surface(id: fields[0], tty: tty,
                       directory: fields[2].isEmpty ? nil : fields[2],
                       title: fields[3].isEmpty ? nil : fields[3])
    }

    /// nil ID means the surface focused at bind time; every later query uses ID.
    static func read(id: String? = nil) -> (surface: Surface?, missing: Bool, reason: String?) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { !$0.isTerminated }) else {
            return (nil, true, "Ghostty is not running")
        }
        guard id == nil || UUID(uuidString: id!) != nil else { return (nil, true, "invalid Ghostty surface ID") }
        let selection = id.map { "terminal id \"\($0)\"" }
            ?? "focused terminal of selected tab of front window"
        let script = """
        tell application id "\(bundleID)"
            if not (exists \(selection)) then return "missing"
            set t to \(selection)
            set device to ""
            try
                set device to «property Gtty» of t as text
            end try
            return (id of t as text) & (ASCII character 31) & device & (ASCII character 31) & (working directory of t as text) & (ASCII character 31) & (name of t as text)
        end tell
        """
        let result = TerminalBinding.osascriptOutcome(script)
        guard let out = result.output else { return (nil, false, result.reason) }
        if out.trimmingCharacters(in: .whitespacesAndNewlines) == "missing" { return (nil, true, nil) }
        guard let surface = parse(out) else { return (nil, false, "Ghostty returned no terminal surface") }
        return (surface, false, nil)
    }

    /// `text:` avoids bracketed paste wrappers. Ghostty's AppleScript action
    /// parser treats hex escapes as characters, so keep Unicode literal and
    /// hex-encode ASCII (including backslashes, quotes and newlines).
    static func textAction(_ text: String) -> String {
        "text:" + text.unicodeScalars.map {
            $0.value < 128 ? String(format: "\\x%02x", $0.value) : String($0)
        }.joined()
    }

    static func send(_ text: String, id: String) -> Bool {
        guard UUID(uuidString: id) != nil else { return false }
        let action = textAction(text).replacingOccurrences(of: "\\", with: "\\\\")
        let script = """
        tell application id "\(bundleID)"
            if not (exists terminal id "\(id)") then return "missing"
            set t to terminal id "\(id)"
            if not (perform action "\(action)" on t) then return "failed"
            send key "enter" to t
            return "ok"
        end tell
        """
        return TerminalBinding.osascriptOutcome(script).output?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }

    static func focus(id: String) -> Bool {
        guard UUID(uuidString: id) != nil else { return false }
        return TerminalBinding.osascriptOutcome("""
        tell application id "\(bundleID)"
            if not (exists terminal id "\(id)") then return "missing"
            focus (terminal id "\(id)")
            return "ok"
        end tell
        """).output?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }
}
