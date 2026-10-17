import Foundation
import CoreGraphics

/// Own the entire press/drag/release, so a capture never clicks or selects text
/// in the application underneath. Only a press made during this prompt can act.
struct PointerCaptureGesture {
    enum Phase { case down, dragged, up }
    enum Action: Equatable {
        case pass, consume
        case screenshot(point: CGPoint, session: Date)
        case beginArea(anchor: CGPoint, point: CGPoint, at: Date, session: Date)
        case moveArea(CGPoint)
        case endArea(CGPoint)
    }

    static let dragThreshold: CGFloat = 6
    private var anchor: CGPoint?
    private var pressedAt = Date.distantPast
    private var owner: Date?
    private var dragging = false
    private var cancelled = false

    mutating func handle(_ phase: Phase, point: CGPoint, session: Date?,
                         canArm: Bool = true, now: Date = Date()) -> Action {
        if case .down = phase {
            anchor = nil; owner = nil; dragging = false; cancelled = false
            guard let session, canArm else { return .pass }
            anchor = point; owner = session; pressedAt = now
            return .consume
        }
        guard let anchor, let owner else { return .pass }
        let wasDragging = dragging
        if session != owner { cancelled = true }
        if cancelled {
            dragging = false
            if case .up = phase { self.anchor = nil; self.owner = nil }
            return wasDragging ? .endArea(point) : .consume
        }
        switch phase {
        case .down: return .consume
        case .dragged:
            if dragging { return .moveArea(point) }
            guard hypot(point.x - anchor.x, point.y - anchor.y) >= Self.dragThreshold else { return .consume }
            dragging = true
            return .beginArea(anchor: anchor, point: point, at: pressedAt, session: owner)
        case .up:
            self.anchor = nil; self.owner = nil; dragging = false
            return wasDragging ? .endArea(point) : .screenshot(point: point, session: owner)
        }
    }
}
