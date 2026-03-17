import AppKit
import Foundation

struct RalphSpriteFrame {
    let image: NSImage
}

struct RalphSpriteAnimation {
    let frames: [RalphSpriteFrame]
    let frameDuration: TimeInterval
}

enum RalphSpriteMovementDirection: Equatable {
    case left
    case right
    case up
    case down

    static func resolve(from start: CGPoint, to end: CGPoint) -> RalphSpriteMovementDirection {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y

        if abs(deltaX) > abs(deltaY) {
            return deltaX >= 0 ? .right : .left
        }

        return deltaY >= 0 ? .up : .down
    }
}

struct RalphSpriteAnimationSet {
    let walkLeft: RalphSpriteAnimation
    let walkRight: RalphSpriteAnimation
    let walkUp: RalphSpriteAnimation
    let walkDown: RalphSpriteAnimation
    let idleLeft: RalphSpriteFrame
    let idleRight: RalphSpriteFrame
    let idleUp: RalphSpriteFrame
    let idleDown: RalphSpriteFrame

    func walkAnimation(for direction: RalphSpriteMovementDirection) -> RalphSpriteAnimation {
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

    func idleFrame(for direction: RalphSpriteMovementDirection) -> RalphSpriteFrame {
        switch direction {
        case .left:
            self.idleLeft
        case .right:
            self.idleRight
        case .up:
            self.idleUp
        case .down:
            self.idleDown
        }
    }
}
