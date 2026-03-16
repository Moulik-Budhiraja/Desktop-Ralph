import AppKit
import CoreGraphics
import Foundation

struct LaunchSpriteFrame {
    let image: NSImage
    let fileName: String
}

struct LaunchSpriteAnimation {
    let frames: [LaunchSpriteFrame]
    let frameDuration: TimeInterval
}

enum LaunchSpriteMovementDirection: Equatable {
    case left
    case right
    case up
    case down

    static func resolve(from start: CGPoint, to end: CGPoint) -> LaunchSpriteMovementDirection {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y

        if abs(deltaX) > abs(deltaY) {
            return deltaX >= 0 ? .right : .left
        }

        return deltaY >= 0 ? .up : .down
    }
}

struct LaunchSpriteAnimationSet {
    let idleSpin: LaunchSpriteAnimation
    let walkLeft: LaunchSpriteAnimation
    let walkRight: LaunchSpriteAnimation
    let walkUp: LaunchSpriteAnimation
    let walkDown: LaunchSpriteAnimation

    func animation(for direction: LaunchSpriteMovementDirection) -> LaunchSpriteAnimation {
        switch direction {
        case .left:
            self.walkLeft
        case .right:
            self.walkRight
        case .up:
            self.walkUp
        case .down:
            self.walkDown
        }
    }
}
