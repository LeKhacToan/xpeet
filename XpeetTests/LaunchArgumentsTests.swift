import XCTest
@testable import Xpeet

/// The Debug launch switches for test drives (specs/speed-accuracy R14, R22, R30).
@MainActor
final class LaunchArgumentsTests: XCTestCase {
    func testReadsYesNoStringsAndNumbers() {
        XCTAssertTrue(LaunchArguments.bool("Key", in: ["Key": "YES"]))
        XCTAssertFalse(LaunchArguments.bool("Key", in: ["Key": "NO"]))
        XCTAssertTrue(LaunchArguments.bool("Key", in: ["Key": NSNumber(value: true)]))
        XCTAssertFalse(LaunchArguments.bool("Key", in: [:]))
    }

    func testMotionOffSwitch() {
        XCTAssertTrue(CoreMotionProvider.launchDefaultEnabled([:]))
        XCTAssertFalse(CoreMotionProvider.launchDefaultEnabled([CoreMotionProvider.motionOffLaunchArgumentKey: "YES"]))
    }

    func testDisabledProviderFinishesAtOnce() async {
        var batches = 0
        for await _ in CoreMotionProvider(isEnabled: false).motionUpdates() { batches += 1 }

        XCTAssertEqual(batches, 0)
    }
}
