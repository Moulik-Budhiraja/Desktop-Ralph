import XCTest
@testable import PenguinOSXKit

@MainActor
final class LaunchSpriteAssetLoaderTests: XCTestCase {
    func testLoadAnimationSetUsesBundledResources() throws {
        let animationSet = try LaunchSpriteAssetLoader.loadAnimationSet()

        XCTAssertEqual(animationSet.idleSpin.frames.count, 6)
        XCTAssertEqual(animationSet.walkLeft.frames.count, 4)
        XCTAssertEqual(animationSet.walkRight.frames.count, 4)
        XCTAssertEqual(animationSet.walkUp.frames.count, 4)
        XCTAssertEqual(animationSet.walkDown.frames.count, 4)
        XCTAssertEqual(animationSet.idleSpin.frames.first?.fileName, "front_center_pose_01.png")
        XCTAssertEqual(
            animationSet.walkRight.frames.first?.fileName,
            "left_profile_walk_pose_01.png [mirrored]")
    }
}
