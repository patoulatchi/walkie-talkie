import Foundation

/// Visibility of the clipboard receipt, independent of the pending bind queue.
struct HeldPromptNotice {
    static let duration: TimeInterval = 5
    private(set) var count = 0
    private(set) var deadline: TimeInterval?
    var isVisible: Bool { count > 0 && deadline != nil }

    mutating func update(count newCount: Int, now: TimeInterval) {
        let newCount = max(0, newCount)
        if newCount == 0 { deadline = nil }
        else if newCount > count { deadline = now + Self.duration }
        count = newCount
    }

    /// An older sentence leaving the queue must not renew a dismissed receipt.
    @discardableResult
    mutating func expire(now: TimeInterval) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil
        return true
    }

    mutating func dismiss() { deadline = nil }
}
