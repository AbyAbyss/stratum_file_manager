import XCTest
@testable import Stratum

final class RippleTests: XCTestCase {
    private let origin = CGPoint(x: 100, y: 100)

    func testNothingMovesBeforeTheWavefrontArrives() {
        // At t = 0.1s the front has only travelled 110px, so a point 600px away is untouched.
        let ripple = NightSkyView.Ripple(origin: origin, time: 0.1)
        let far = CGPoint(x: 700, y: 100)
        XCTAssertEqual(ripple.apply(to: far).point, far)
    }

    func testDisplacementIsAlongTheRadiusAndBoundedByTheAmplitude() {
        let ripple = NightSkyView.Ripple(origin: origin, time: 0.5)
        let point = CGPoint(x: 400, y: 100)           // 300px to the right of the origin
        let moved = ripple.apply(to: point)
        XCTAssertEqual(moved.point.y, 100, accuracy: 0.0001)   // purely horizontal
        XCTAssertLessThanOrEqual(abs(moved.point.x - point.x), NightSkyView.Ripple.amplitude + 0.0001)
        XCTAssertLessThanOrEqual(abs(moved.height), 1)
    }

    func testTheOriginItselfDoesNotProduceNaN() {
        let moved = NightSkyView.Ripple(origin: origin, time: 1).apply(to: origin)
        XCTAssertEqual(moved.point, origin)
        XCTAssertFalse(moved.height.isNaN)
    }
}
