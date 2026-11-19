import XCTest
import AppKit
@testable import Stratum

final class AppIconTests: XCTestCase {
    private func render(_ pixels: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let gc = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        StratumAppIconGenerator.draw(in: gc.cgContext, canvas: CGFloat(pixels), accentColor: StratumAppIconGenerator.brandAccent)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    func testCornersAreTransparentAndCentreIsOpaque() {
        let rep = render(256)
        XCTAssertEqual(rep.colorAt(x: 2, y: 2)?.alphaComponent ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(rep.colorAt(x: 253, y: 253)?.alphaComponent ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(rep.colorAt(x: 128, y: 128)?.alphaComponent ?? 0, 1, accuracy: 0.01)
    }

    func testSquircleFillsAboutEightyPercentOfTheCanvas() {
        // Apple's macOS template: an 824pt body on a 1024pt canvas. Check the left edge of the
        // opaque body sits near 100/1024 of the width.
        let rep = render(1024)
        var firstOpaque = -1
        for x in 0..<512 where (rep.colorAt(x: x, y: 512)?.alphaComponent ?? 0) > 0.95 { firstOpaque = x; break }
        XCTAssertTrue((90...115).contains(firstOpaque), "body starts at x=\(firstOpaque)")
    }
}
