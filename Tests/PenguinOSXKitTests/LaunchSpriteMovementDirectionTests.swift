import CoreGraphics
import XCTest
@testable import PenguinOSXKit

final class LaunchSpriteMovementDirectionTests: XCTestCase {
    func testResolvePrefersHorizontalAnimationForWideMovement() {
        let direction = LaunchSpriteMovementDirection.resolve(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 180, y: 120))

        XCTAssertEqual(direction, .right)
    }

    func testResolvePrefersVerticalAnimationForTallMovement() {
        let direction = LaunchSpriteMovementDirection.resolve(
            from: CGPoint(x: 100, y: 100),
            to: CGPoint(x: 80, y: 10))

        XCTAssertEqual(direction, .down)
    }

    func testResolveUsesVerticalAnimationWhenDistancesTie() {
        let direction = LaunchSpriteMovementDirection.resolve(
            from: CGPoint(x: 24, y: 24),
            to: CGPoint(x: 96, y: 96))

        XCTAssertEqual(direction, .up)
    }
}
