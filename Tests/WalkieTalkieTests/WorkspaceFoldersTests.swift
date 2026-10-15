import XCTest
@testable import WalkieTalkie

/// The spawn menu's *Workspace ›* submenu, the pure half (2026-10-15): the
/// pinned left out, the rest bucketed by their newest file into the last day,
/// week and month, each bucket by name.
final class WorkspaceFoldersTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func folder(_ name: String, daysAgo: Double) -> WorkspaceFolders.Folder {
        WorkspaceFolders.Folder(name: name, path: "/w/\(name)", modified: now.addingTimeInterval(-daysAgo * 86400))
    }

    private func names(_ folders: [WorkspaceFolders.Folder], pinned: Set<String> = [])
        -> [(WorkspaceFolders.Section, [String])] {
        WorkspaceFolders.sections(folders, excluding: pinned, now: now).map { ($0.section, $0.folders.map(\.name)) }
    }

    func testBucketsByAgeAndSortsEachByName() {
        let got = names([folder("zeta", daysAgo: 0.1), folder("alpha", daysAgo: 0.9),
                         folder("mid", daysAgo: 3), folder("old", daysAgo: 20), folder("ancient", daysAgo: 40)])
        XCTAssertEqual(got.map(\.0), [.day, .week, .month])
        XCTAssertEqual(got.map(\.1), [["alpha", "zeta"], ["mid"], ["old"]])
    }

    func testPinnedAreLeftOut() {
        let got = names([folder("a", daysAgo: 0.1), folder("b", daysAgo: 0.1)], pinned: ["/w/a"])
        XCTAssertEqual(got.map(\.1), [["b"]])
    }

    func testEmptySectionsAreDropped() {
        let got = names([folder("x", daysAgo: 10)])
        XCTAssertEqual(got.map(\.0), [.month])
        XCTAssertTrue(names([]).isEmpty)
    }

    func testNamesSortTheWayFinderDoes() {
        let got = names([folder("kata-10", daysAgo: 1.5), folder("kata-2", daysAgo: 2), folder("Beta", daysAgo: 2)])
        XCTAssertEqual(got.first?.1, ["Beta", "kata-2", "kata-10"])
    }
}
