import AppKit
import Foundation

struct RalphSpriteFrame {
    let image: NSImage
}

struct RalphSpriteAnimation {
    let frames: [RalphSpriteFrame]
    let frameDuration: TimeInterval
    let repeats: Bool

    init(frames: [RalphSpriteFrame], frameDuration: TimeInterval, repeats: Bool = true) {
        self.frames = frames
        self.frameDuration = frameDuration
        self.repeats = repeats
    }

    var totalDuration: TimeInterval {
        Double(self.frames.count) * self.frameDuration
    }
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
    let idleLeftAnimations: [RalphSpriteAnimation]
    let idleRightAnimations: [RalphSpriteAnimation]
    let idleUpAnimations: [RalphSpriteAnimation]
    let idleDownAnimations: [RalphSpriteAnimation]
    let ambientIdleAnimations: [RalphSpriteAnimation]
    let clickDown: RalphSpriteAnimation

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

    func idleAnimation(for direction: RalphSpriteMovementDirection) -> RalphSpriteAnimation {
        switch direction {
        case .left:
            self.idleLeftAnimations.randomElement() ?? RalphSpriteAnimation(frames: [self.walkLeft.frames[0]], frameDuration: 0.2)
        case .right:
            self.idleRightAnimations.randomElement() ?? RalphSpriteAnimation(frames: [self.walkRight.frames[0]], frameDuration: 0.2)
        case .up:
            self.idleUpAnimations.randomElement() ?? RalphSpriteAnimation(frames: [self.walkUp.frames[0]], frameDuration: 0.2)
        case .down:
            self.idleDownAnimations.randomElement() ?? RalphSpriteAnimation(frames: [self.walkDown.frames[0]], frameDuration: 0.2)
        }
    }

    func idleAnimations(for direction: RalphSpriteMovementDirection) -> [RalphSpriteAnimation] {
        let baseAnimations: [RalphSpriteAnimation] = switch direction {
        case .left:
            self.idleLeftAnimations
        case .right:
            self.idleRightAnimations
        case .up:
            self.idleUpAnimations
        case .down:
            self.idleDownAnimations
        }

        let animatedBaseAnimations = baseAnimations.filter { $0.frames.count > 1 }
        let preferredAnimations = animatedBaseAnimations + self.ambientIdleAnimations
        let animations = preferredAnimations.isEmpty ? baseAnimations : preferredAnimations
        return animations.isEmpty ? [self.idleAnimation(for: direction)] : animations
    }

    func ambientIdleAnimation() -> RalphSpriteAnimation? {
        self.ambientIdleAnimations.randomElement()
    }

    func clickAnimation(for direction: RalphSpriteMovementDirection) -> RalphSpriteAnimation {
        switch direction {
        case .down:
            self.clickDown
        case .left, .right, .up:
            self.idleAnimation(for: direction)
        }
    }
}
