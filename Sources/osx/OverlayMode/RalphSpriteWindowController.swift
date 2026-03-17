import AppKit
import Foundation

@MainActor
final class RalphSpriteWindowController: NSWindowController {
    private static let spriteSize = CGSize(width: 128, height: 160)
    private static let interactionOffset = CGPoint(x: 64, y: 28)

    private let spriteView: RalphSpriteView
    private let animations: RalphSpriteAnimationSet

    static func make() -> RalphSpriteWindowController? {
        guard let animations = try? RalphSpriteAssetLoader.loadAnimationSet() else {
            return nil
        }
        return RalphSpriteWindowController(animations: animations)
    }

    private init(animations: RalphSpriteAnimationSet) {
        self.animations = animations
        self.spriteView = RalphSpriteView(
            frame: CGRect(origin: .zero, size: Self.spriteSize),
            animations: animations)

        let window = NSWindow(
            contentRect: CGRect(origin: Self.desktopFrame().origin, size: Self.spriteSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovable = false
        window.contentView = self.spriteView
        window.orderFrontRegardless()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func walk(to targetFrame: CGRect) {
        guard let window else { return }

        let destinationOrigin = Self.spriteOrigin(for: targetFrame)
        let currentOrigin = window.frame.origin
        let startOrigin = currentOrigin == .zero ? Self.offscreenOrigin(toward: destinationOrigin) : currentOrigin
        let direction = RalphSpriteMovementDirection.resolve(from: startOrigin, to: destinationOrigin)
        let distance = hypot(destinationOrigin.x - startOrigin.x, destinationOrigin.y - startOrigin.y)
        let profile = RalphMotionPlanner.makeProfile(distance: distance, desktopWidth: Self.desktopFrame().width)

        window.setFrameOrigin(Self.clampedOrigin(startOrigin))
        self.spriteView.playWalk(direction: direction)
        window.orderFrontRegardless()

        guard profile.totalDuration > 0 else {
            window.setFrameOrigin(Self.clampedOrigin(destinationOrigin))
            self.spriteView.showIdle(direction: direction)
            return
        }

        let startedAt = Date()
        let endDate = startedAt.addingTimeInterval(profile.totalDuration)

        while Date() < endDate {
            let elapsed = Date().timeIntervalSince(startedAt)
            let traveledDistance = RalphMotionPlanner.distanceTraveled(at: elapsed, profile: profile)
            let progress = min(1, traveledDistance / max(distance, 1))
            let currentPoint = RalphMotionPlanner.interpolate(
                from: startOrigin,
                to: destinationOrigin,
                progress: CGFloat(progress))
            window.setFrameOrigin(Self.clampedOrigin(currentPoint))
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        window.setFrameOrigin(Self.clampedOrigin(destinationOrigin))
        self.spriteView.showIdle(direction: direction)
    }

    func dwell(for duration: TimeInterval) {
        guard duration > 0 else { return }
        let endDate = Date().addingTimeInterval(duration)
        while Date() < endDate {
            RunLoop.current.run(mode: .default, before: min(endDate, Date().addingTimeInterval(0.01)))
        }
    }

    private static func spriteOrigin(for targetFrame: CGRect) -> CGPoint {
        let desktop = Self.desktopFrame()
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let localMidYFromTop = targetCenter.y - desktop.minY
        let flippedCenterY = desktop.minY + (desktop.height - localMidYFromTop)
        return CGPoint(
            x: targetCenter.x - Self.interactionOffset.x,
            y: flippedCenterY - Self.interactionOffset.y)
    }

    private static func offscreenOrigin(toward destination: CGPoint) -> CGPoint {
        let desktop = Self.desktopFrame()
        let start = CGPoint(
            x: max(desktop.minX, destination.x - 120),
            y: min(desktop.maxY - Self.spriteSize.height, destination.y + 80))
        return Self.clampedOrigin(start)
    }

    private static func clampedOrigin(_ origin: CGPoint) -> CGPoint {
        let desktop = Self.desktopFrame()
        return CGPoint(
            x: min(max(origin.x, desktop.minX), desktop.maxX - Self.spriteSize.width),
            y: min(max(origin.y, desktop.minY), desktop.maxY - Self.spriteSize.height))
    }

    private static func desktopFrame() -> CGRect {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }
    }
}

enum RalphSpriteAssetLoader {
    static func loadAnimationSet() throws -> RalphSpriteAnimationSet {
        let leftIdle = try Self.loadFrame(named: "left_profile_pose_01")
        let leftWalkFrames = try [
            "left_profile_walk_pose_01",
            "left_profile_pose_02",
            "left_profile_walk_pose_02",
            "left_profile_pose_03",
        ].map(Self.loadFrame(named:))
        let upWalkFrames = try [
            "back_pose_01",
            "back_pose_02",
            "back_pose_03",
            "back_pose_04",
        ].map(Self.loadFrame(named:))
        let downWalkFrames = try [
            "front_center_pose_01",
            "front_center_pose_02",
            "front_center_pose_03",
            "front_center_pose_04",
        ].map(Self.loadFrame(named:))

        return RalphSpriteAnimationSet(
            walkLeft: RalphSpriteAnimation(frames: leftWalkFrames, frameDuration: 0.10),
            walkRight: RalphSpriteAnimation(frames: leftWalkFrames.map(Self.mirror), frameDuration: 0.10),
            walkUp: RalphSpriteAnimation(frames: upWalkFrames, frameDuration: 0.11),
            walkDown: RalphSpriteAnimation(frames: downWalkFrames, frameDuration: 0.11),
            idleLeft: leftIdle,
            idleRight: Self.mirror(leftIdle),
            idleUp: try Self.loadFrame(named: "back_pose_01"),
            idleDown: try Self.loadFrame(named: "front_center_pose_01"))
    }

    private static func loadFrame(named name: String) throws -> RalphSpriteFrame {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            throw RalphSpriteError.missingAsset("Missing Ralph sprite resource '\(name).png'.")
        }
        guard let image = NSImage(contentsOf: url) else {
            throw RalphSpriteError.missingAsset("Failed to load Ralph sprite resource '\(name).png'.")
        }
        return RalphSpriteFrame(image: image)
    }

    private static func mirror(_ frame: RalphSpriteFrame) -> RalphSpriteFrame {
        let mirrored = NSImage(size: frame.image.size)
        mirrored.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: frame.image.size.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()
        frame.image.draw(in: CGRect(origin: .zero, size: frame.image.size))
        mirrored.unlockFocus()
        return RalphSpriteFrame(image: mirrored)
    }
}

enum RalphSpriteError: LocalizedError {
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case let .missingAsset(message):
            return message
        }
    }
}
