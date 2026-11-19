import XCTest
@testable import Stratum

final class TreemapLayoutTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    func testAreasAreProportionalToWeights() {
        let weights: [Double] = [60, 25, 10, 5]
        let rects = TreemapLayout.rects(for: weights, in: bounds)
        let totalArea = bounds.width * bounds.height
        for (w, r) in zip(weights, rects) {
            XCTAssertEqual(r.width * r.height, totalArea * CGFloat(w / 100), accuracy: 1.0)
        }
    }

    func testTilesFillBoundsWithoutOverlap() {
        let rects = TreemapLayout.rects(for: [50, 30, 20, 10, 5, 5, 1], in: bounds)
        let covered = rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        XCTAssertEqual(covered, bounds.width * bounds.height, accuracy: 2.0)
        for r in rects { XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(r)) }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].insetBy(dx: 0.5, dy: 0.5).intersection(rects[j].insetBy(dx: 0.5, dy: 0.5))
                XCTAssertTrue(overlap.isNull || overlap.isEmpty, "tiles \(i) and \(j) overlap")
            }
        }
    }

    func testDegenerateInputs() {
        XCTAssertTrue(TreemapLayout.rects(for: [], in: bounds).isEmpty)
        XCTAssertEqual(TreemapLayout.rects(for: [0, 0], in: bounds), [.zero, .zero])
        XCTAssertEqual(TreemapLayout.rects(for: [1], in: .zero), [.zero])
        XCTAssertEqual(TreemapLayout.rects(for: [1], in: bounds), [bounds])
    }

    func testNonPositiveWeightsGetZeroRect() {
        let rects = TreemapLayout.rects(for: [10, 5, 0], in: bounds)
        XCTAssertEqual(rects[2], .zero)
        XCTAssertGreaterThan(rects[0].width * rects[0].height, 0)
    }
}
