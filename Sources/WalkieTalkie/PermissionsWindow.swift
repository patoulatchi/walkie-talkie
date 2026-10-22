import AppKit
import ApplicationServices
import AVFoundation

/// The same permission checks drive the menu and the recovery window.
/// Reading a state never opens a macOS consent prompt.
enum AppPermission: Int, CaseIterable {
    case microphone, accessibility, screenRecording, automation

    enum State: Equatable {
        case allowed, needed, notRequested, restricted, perApp

        var title: String {
            switch self {
            case .allowed: return "Allowed"
            case .needed: return "Needs access"
            case .notRequested: return "Not requested yet"
            case .restricted: return "Restricted by macOS"
            case .perApp: return "Managed per app"
            }
        }
    }

    var name: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .automation: return "Automation"
        }
    }

    var purpose: String {
        switch self {
        case .microphone: return "Record your voice for dictation."
        case .accessibility: return "Use global shortcuts and insert text into other apps."
        case .screenRecording: return "Attach screenshots and read window information."
        case .automation: return "Control Terminal or Ghostty when delivering a prompt."
        }
    }

    var symbol: String {
        switch self {
        case .microphone: return "mic"
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .automation: return "terminal"
        }
    }

    var settingsURL: URL {
        let pane: String
        switch self {
        case .microphone: pane = "Privacy_Microphone"
        case .accessibility: pane = "Privacy_Accessibility"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .automation: pane = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    var state: State {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .allowed
            case .notDetermined: return .notRequested
            case .restricted: return .restricted
            case .denied: return .needed
            @unknown default: return .needed
            }
        case .accessibility: return AXIsProcessTrusted() ? .allowed : .needed
        case .screenRecording: return CGPreflightScreenCaptureAccess() ? .allowed : .needed
        // Automation is granted separately for each destination. Do not claim
        // that it is allowed based on the other three checks, or prompt to test it.
        case .automation: return .perApp
        }
    }

    static var core: [AppPermission] { allCases.filter { $0 != .automation } }
    static var missingCount: Int { core.filter { $0.state != .allowed }.count }
}

/// A nonmodal recovery window; opening it never requests a permission.
enum PermissionsWindow {
    static var onRestart: (() -> Void)?
    private static var controller: Controller?

    static func show() {
        if controller == nil { controller = Controller() }
        controller?.refresh()
        controller?.window?.center()
        controller?.window?.orderFrontRegardless()
        controller?.startWatching()
    }

    static func showIfNeeded() {
        if AppPermission.missingCount > 0 { show() }
    }

    /// Runs before normal application startup: no microphone, event tap,
    /// singleton replacement or consent prompt is involved in visual QA.
    static func shoot(to path: String, ready: Bool, dark: Bool) {
        let states = Dictionary(uniqueKeysWithValues: AppPermission.allCases.map {
            ($0, $0 == .automation ? AppPermission.State.perApp : ready ? .allowed : .needed)
        })
        let c = Controller(preview: states)
        c.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let view = c.window?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private final class Controller: NSWindowController, NSWindowDelegate {
        private var statusLabels: [AppPermission: NSTextField] = [:]
        private var actionButtons: [AppPermission: NSButton] = [:]
        private var watcher: Timer?
        private let summary = NSTextField(labelWithString: "")
        private let feedback = NSTextField(wrappingLabelWithString: "")
        private let preview: [AppPermission: AppPermission.State]?
        private var previousStates: [AppPermission: AppPermission.State] = [:]
        private static let allowedColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.50, green: 0.85, blue: 0.55, alpha: 1)
                : NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.20, alpha: 1)
        }

        init(preview: [AppPermission: AppPermission.State]? = nil) {
            self.preview = preview
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 650),
                                styleMask: [.titled, .closable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Walkie Talkie Permissions"
            // System Settings must be able to cover this window when a link
            // opens it; a floating recovery panel would hide its controls.
            panel.level = .normal
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.sharingType = .none
            super.init(window: panel)
            panel.delegate = self
            build()
            refresh()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private final class Body: NSView {
            override var isFlipped: Bool { true }
            override var wantsUpdateLayer: Bool { true }
            override func updateLayer() { layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        }

        private func label(_ text: String, at frame: NSRect, size: CGFloat = 13,
                           weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = frame
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            field.isSelectable = false
            window?.contentView?.addSubview(field)
            return field
        }

        private func button(_ title: String, at frame: NSRect, action: Selector) -> NSButton {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = frame
            window?.contentView?.addSubview(button)
            return button
        }

        private func divider(y: CGFloat) {
            let line = NSBox(frame: NSRect(x: 24, y: y, width: 592, height: 1))
            line.boxType = .separator
            window?.contentView?.addSubview(line)
        }

        private func build() {
            let body = Body(frame: NSRect(x: 0, y: 0, width: 640, height: 650))
            body.wantsLayer = true
            window?.contentView = body
            _ = label("Permissions", at: NSRect(x: 24, y: 22, width: 592, height: 28), size: 23, weight: .semibold)
            _ = label("Restore access after an update, or review what Walkie Talkie can use.",
                      at: NSRect(x: 24, y: 60, width: 592, height: 38), secondary: true)
            summary.frame = NSRect(x: 24, y: 104, width: 592, height: 20)
            summary.font = .systemFont(ofSize: 13, weight: .medium)
            body.addSubview(summary)
            divider(y: 136)

            for (index, permission) in AppPermission.allCases.enumerated() {
                let top = CGFloat(152 + index * 87)
                let image = NSImageView(frame: NSRect(x: 25, y: top + 1, width: 24, height: 24))
                image.image = NSImage(systemSymbolName: permission.symbol, accessibilityDescription: permission.name)
                image.contentTintColor = .secondaryLabelColor
                body.addSubview(image)
                _ = label(permission.name, at: NSRect(x: 64, y: top, width: 300, height: 21),
                          size: 15, weight: .semibold)
                _ = label(permission.purpose, at: NSRect(x: 64, y: top + 29, width: 356, height: 36),
                          size: 12, secondary: true)
                let status = label("", at: NSRect(x: 396, y: top + 2, width: 220, height: 20), size: 12)
                status.alignment = .right
                statusLabels[permission] = status
                let action = button("Open Settings…", at: NSRect(x: 448, y: top + 29, width: 170, height: 28),
                                    action: #selector(openPermission(_:)))
                action.tag = permission.rawValue
                action.setAccessibilityLabel("Open \(permission.name) settings")
                actionButtons[permission] = action
                if index < AppPermission.allCases.count - 1 { divider(y: top + 75) }
            }
            divider(y: 501)
            _ = label("Already enabled, but still not working?", at: NSRect(x: 24, y: 519, width: 592, height: 20),
                      size: 13, weight: .semibold)
            _ = label("In Accessibility or Screen Recording, remove the old entry with −, then use + to add this app again. In Automation, enable your terminal under Walkie Talkie.",
                      at: NSRect(x: 24, y: 545, width: 592, height: 44), size: 12, secondary: true)
            _ = button("Show App in Finder", at: NSRect(x: 20, y: 600, width: 174, height: 30), action: #selector(revealApp))
            let restart = button("Restart Walkie Talkie", at: NSRect(x: 429, y: 600, width: 190, height: 30),
                                 action: #selector(restartApp))
            restart.toolTip = "Finishes the current dictation and waits for pending delivery before restarting."
            feedback.frame = NSRect(x: 208, y: 601, width: 209, height: 34)
            feedback.font = .systemFont(ofSize: 11)
            feedback.textColor = .secondaryLabelColor
            body.addSubview(feedback)
        }

        func refresh() {
            let states = preview ?? Dictionary(uniqueKeysWithValues: AppPermission.allCases.map { ($0, $0.state) })
            guard states != previousStates else { return }
            previousStates = states
            let count = AppPermission.core.filter { states[$0] == .allowed }.count
            summary.stringValue = count == AppPermission.core.count
                ? "All core permissions are allowed."
                : "\(count) of \(AppPermission.core.count) core permissions allowed"
            for permission in AppPermission.allCases {
                guard let state = states[permission] else { continue }
                statusLabels[permission]?.stringValue = state == .allowed ? "✓ \(state.title)" : state.title
                statusLabels[permission]?.textColor = state == .allowed ? Self.allowedColor : .secondaryLabelColor
                actionButtons[permission]?.title = state == .notRequested ? "Allow Microphone…" : "Open Settings…"
                actionButtons[permission]?.setAccessibilityLabel(state == .notRequested
                    ? "Allow Microphone" : "Open \(permission.name) settings")
            }
        }

        func startWatching() {
            watcher?.invalidate()
            watcher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        }

        func windowWillClose(_ notification: Notification) {
            watcher?.invalidate()
            watcher = nil
        }

        @objc private func openPermission(_ sender: NSButton) {
            guard let permission = AppPermission(rawValue: sender.tag) else { return }
            if permission == .microphone, permission.state == .notRequested {
                // Consent is requested only after this explicit button click.
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    DispatchQueue.main.async { self?.refresh() }
                }
                return
            }
            if !NSWorkspace.shared.open(permission.settingsURL) {
                feedback.stringValue = "Open Privacy & Security in System Settings."
            }
        }

        @objc private func revealApp() {
            let bundle = Bundle.main.bundleURL
            let app = bundle.pathExtension == "app" ? bundle : URL(fileURLWithPath: "/Applications/Walkie Talkie.app")
            NSWorkspace.shared.activateFileViewerSelecting([app])
        }

        @objc private func restartApp() {
            guard let restart = PermissionsWindow.onRestart else { return }
            close()
            restart()
        }
    }
}
