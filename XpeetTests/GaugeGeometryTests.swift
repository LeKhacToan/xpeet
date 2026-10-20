import XCTest
@testable import Xpeet

final class GaugeGeometryTests: XCTestCase {
    // MARK: - R3 needle

    func testNeedleAngleZero() {
        XCTAssertEqual(GaugeGeometry.needleAngle(fraction: 0), -135)
    }

    func testNeedleAngleHalf() {
        XCTAssertEqual(GaugeGeometry.needleAngle(fraction: 0.5), 0)
    }

    func testNeedleAngleFull() {
        XCTAssertEqual(GaugeGeometry.needleAngle(fraction: 1), 135)
    }

    func testNeedleAngleAboveMaxIsClamped() {
        XCTAssertEqual(GaugeGeometry.needleAngle(fraction: 1.4), 135)
        XCTAssertEqual(GaugeGeometry.needleAngle(fraction: -0.2), -135)
    }

    /// Without a live reading `gaugeFraction` is 0, so the needle rests at the start.
    @MainActor
    func testNeedleAngleWithoutReadingIsZero() {
        let viewModel = SpeedometerViewModel(
            provider: FakeSpeedProvider(),
            defaults: UserDefaults(suiteName: "GaugeGeometryTests-\(UUID().uuidString)") ?? .standard,
            locale: Locale(identifier: "fr_FR"),
            setIdleTimerDisabled: { _ in }
        )
        XCTAssertEqual(GaugeGeometry.needleAngle(fraction: viewModel.gaugeFraction), -135)
    }

    // MARK: - R3 ticks

    func testKmhTicks() {
        let ticks = GaugeGeometry.ticks(for: .kmh)
        XCTAssertEqual(ticks.map(\.value), Array(stride(from: 0, through: 200, by: 10)))
        XCTAssertEqual(ticks.compactMap(\.label), ["0", "20", "40", "60", "80", "100", "120", "140", "160", "180", "200"])
        XCTAssertFalse(ticks.first { $0.value == 10 }?.isMajor ?? true)
    }

    func testMphTicksEndAt130() {
        let ticks = GaugeGeometry.ticks(for: .mph)
        XCTAssertEqual(ticks.map(\.value), Array(stride(from: 0, through: 130, by: 10)))
        XCTAssertEqual(ticks.compactMap(\.label), ["0", "20", "40", "60", "80", "100", "120", "130"])
        XCTAssertEqual(GaugeGeometry.angle(for: 130, maximum: 130), 135)
    }

    // MARK: - R4 segments

    func testLitSegmentsZero() {
        XCTAssertEqual(GaugeGeometry.litSegments(fraction: 0), 0)
    }

    func testLitSegmentsHalf() {
        XCTAssertEqual(GaugeGeometry.litSegments(fraction: 0.5), 10)
    }

    func testLitSegmentsNearFull() {
        XCTAssertEqual(GaugeGeometry.litSegments(fraction: 0.97), 19)
    }

    func testLitSegmentsFull() {
        XCTAssertEqual(GaugeGeometry.litSegments(fraction: 1), 20)
        XCTAssertEqual(GaugeGeometry.litSegments(fraction: 3), 20)
    }

    @MainActor
    func testLitSegmentsNoReading() {
        let viewModel = SpeedometerViewModel(
            provider: FakeSpeedProvider(),
            defaults: UserDefaults(suiteName: "GaugeGeometryTests-\(UUID().uuidString)") ?? .standard,
            locale: Locale(identifier: "fr_FR"),
            setIdleTimerDisabled: { _ in }
        )
        XCTAssertNil(viewModel.displayedSpeed)
        XCTAssertEqual(GaugeGeometry.litSegments(fraction: viewModel.gaugeFraction), 0)
    }
}
