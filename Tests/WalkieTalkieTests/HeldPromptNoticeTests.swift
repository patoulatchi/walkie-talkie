import XCTest
@testable import WalkieTalkie

final class HeldPromptNoticeTests: XCTestCase {
    func testDisappearsAfterFiveSecondsWithoutDroppingQueueCount() {
        var notice = HeldPromptNotice()
        notice.update(count: 1, now: 10)
        XCTAssertTrue(notice.isVisible)
        XCTAssertFalse(notice.expire(now: 14.99))
        XCTAssertTrue(notice.expire(now: 15))
        XCTAssertFalse(notice.isVisible)
        XCTAssertEqual(notice.count, 1)
    }

    func testNewTranscriptGetsItsOwnFiveSeconds() {
        var notice = HeldPromptNotice()
        notice.update(count: 1, now: 10)
        notice.update(count: 2, now: 13)
        XCTAssertFalse(notice.expire(now: 15), "The first receipt's timer cannot hide the new one")
        XCTAssertTrue(notice.expire(now: 18))
    }

    func testQueueShrinkDoesNotRenewOrReviveTheNotice() {
        var notice = HeldPromptNotice()
        notice.update(count: 2, now: 10)
        notice.update(count: 1, now: 13)
        XCTAssertEqual(notice.deadline, 15)
        notice.expire(now: 15)
        notice.update(count: 0, now: 20)
        XCTAssertFalse(notice.isVisible)
        notice.update(count: 2, now: 30)
        notice.expire(now: 35)
        notice.update(count: 1, now: 40)
        XCTAssertFalse(notice.isVisible, "Older queue entries expiring must not bring it back")
    }

    func testBindingClearsItAndANewTranscriptCanShowItAgain() {
        var notice = HeldPromptNotice()
        notice.update(count: 1, now: 10)
        notice.update(count: 0, now: 11)
        XCTAssertFalse(notice.isVisible)
        notice.update(count: 1, now: 12)
        XCTAssertTrue(notice.isVisible)
        XCTAssertEqual(notice.deadline, 17)
    }
}
