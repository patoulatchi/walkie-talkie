import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WalkieTalkie

final class FilmSheetTests: XCTestCase {
    /// A recording that followed the pointer across two displays of different
    /// shapes (2026-10-16) still makes one sheet, as tall as the tallest frame.
    func testFramesOfTwoDisplaysMakeOneSheet() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("film-sheet-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sizes = [(1920, 1080), (1920, 1080), (1728, 1117)]
        let frames = try sizes.enumerated().map { n, size -> FilmSheet.Frame in
            let url = dir.appendingPathComponent("frame-\(n + 1).jpg")
            try jpeg(width: size.0, height: size.1, to: url)
            return FilmSheet.Frame(url: url, at: Double(n) * 0.2, index: n + 1)
        }
        let sheet = try XCTUnwrap(FilmSheet.write(frames: frames, to: dir.appendingPathComponent("sheet.png")))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(sheet as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let cell = (FilmSheet.cellWidth * 1117 / 1728).rounded()
        XCTAssertEqual(image.height, Int(8 * 2 + cell + 16))
    }

    private func jpeg(width: Int, height: Int, to url: URL) throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(NSColor.gray.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
