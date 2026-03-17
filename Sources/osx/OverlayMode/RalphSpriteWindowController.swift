import AppKit
import Foundation

@MainActor
final class RalphSpriteWindowController: NSWindowController {
    private static let interactionOffset = CGPoint(x: 64, y: 28)

    private let spriteView: RalphSpriteView
    private let animations: RalphSpriteAnimationSet
    private var bubbleMessage: String
    private var windowSize: CGSize {
        RalphSpriteView.contentSize(for: self.bubbleMessage)
    }

    static func make(bubbleMessage: String = RalphSpriteView.defaultBubbleMessage) -> RalphSpriteWindowController? {
        guard let animations = try? RalphSpriteAssetLoader.loadAnimationSet() else {
            return nil
        }
        return RalphSpriteWindowController(animations: animations, bubbleMessage: bubbleMessage)
    }

    private init(animations: RalphSpriteAnimationSet, bubbleMessage: String) {
        self.animations = animations
        self.bubbleMessage = bubbleMessage
        let spriteWindowSize = RalphSpriteView.contentSize(for: bubbleMessage)
        self.spriteView = RalphSpriteView(
            frame: CGRect(origin: .zero, size: spriteWindowSize),
            animations: animations,
            bubbleMessage: bubbleMessage)

        let window = NSWindow(
            contentRect: CGRect(origin: Self.desktopFrame().origin, size: spriteWindowSize),
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

    func updateBubbleMessage(_ message: String) {
        guard self.bubbleMessage != message, let window else { return }
        self.bubbleMessage = message
        self.spriteView.updateBubbleMessage(message)
        let nextSize = RalphSpriteView.contentSize(for: message)
        self.spriteView.frame = CGRect(origin: .zero, size: nextSize)
        window.setContentSize(nextSize)
        window.setFrameOrigin(Self.clampedOrigin(window.frame.origin, windowSize: nextSize))
    }

    func walk(to targetFrame: CGRect) {
        guard let window else { return }

        let destinationOrigin = Self.spriteOrigin(for: targetFrame)
        let currentOrigin = window.frame.origin
        let startOrigin = currentOrigin == .zero ? self.offscreenOrigin(toward: destinationOrigin) : currentOrigin
        let direction = RalphSpriteMovementDirection.resolve(from: startOrigin, to: destinationOrigin)
        let distance = hypot(destinationOrigin.x - startOrigin.x, destinationOrigin.y - startOrigin.y)
        let profile = RalphMotionPlanner.makeProfile(distance: distance, desktopWidth: Self.desktopFrame().width)

        window.setFrameOrigin(self.clampedOrigin(startOrigin))
        self.spriteView.playWalk(direction: direction)
        window.orderFrontRegardless()

        guard profile.totalDuration > 0 else {
            window.setFrameOrigin(self.clampedOrigin(destinationOrigin))
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
            window.setFrameOrigin(self.clampedOrigin(currentPoint))
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        window.setFrameOrigin(self.clampedOrigin(destinationOrigin))
        self.spriteView.showIdle(direction: direction)
    }

    func dwell(for duration: TimeInterval) {
        guard duration > 0 else { return }
        let endDate = Date().addingTimeInterval(duration)
        while Date() < endDate {
            RunLoop.current.run(mode: .default, before: min(endDate, Date().addingTimeInterval(0.01)))
        }
    }

    func click(targetFrame: CGRect) {
        self.walk(to: targetFrame)
        self.spriteView.playClick(direction: .down)
        self.dwell(for: self.animations.clickDown.totalDuration)
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

    private func offscreenOrigin(toward destination: CGPoint) -> CGPoint {
        let desktop = Self.desktopFrame()
        let start = CGPoint(
            x: max(desktop.minX, destination.x - 120),
            y: min(desktop.maxY - self.windowSize.height, destination.y + 80))
        return self.clampedOrigin(start)
    }

    private func clampedOrigin(_ origin: CGPoint) -> CGPoint {
        Self.clampedOrigin(origin, windowSize: self.windowSize)
    }

    private static func clampedOrigin(_ origin: CGPoint, windowSize: CGSize) -> CGPoint {
        let desktop = Self.desktopFrame()
        return CGPoint(
            x: min(max(origin.x, desktop.minX), desktop.maxX - windowSize.width),
            y: min(max(origin.y, desktop.minY), desktop.maxY - windowSize.height))
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
        let leftPoseTwo = try Self.loadFrame(named: "left_profile_pose_02")
        let leftPoseThree = try Self.loadFrame(named: "left_profile_pose_03")
        let leftWalkPoseOne = try Self.loadFrame(named: "left_profile_walk_pose_01")
        let leftWalkPoseTwo = try Self.loadFrame(named: "left_profile_walk_pose_02")
        let leftWalkFrames = try Self.loadFrames(
            named: [
                "left_profile_walk_pose_01",
                "left_profile_pose_02",
                "left_profile_walk_pose_02",
                "left_profile_pose_03",
            ])
        let upWalkFrames = try Self.loadFrames(
            named: [
                "back_pose_01",
                "back_pose_02",
                "back_pose_03",
                "back_pose_04",
            ])
        let backGeminiIdle = try Self.loadFrame(named: "gemini_back_pose_02")
        let downWalkFrames = try Self.loadFrames(
            named: [
                "gemini_front_walk_pose_01",
                "gemini_front_walk_pose_02",
                "gemini_front_walk_pose_03",
                "gemini_front_walk_pose_04",
                "gemini_front_walk_pose_05",
                "gemini_front_walk_pose_06",
                "gemini_front_walk_pose_07",
                "gemini_front_walk_pose_08",
            ])
        let frontIdle = try Self.loadFrame(named: "gemini_front_idle_pose_01")
        let frontStep = try Self.loadFrame(named: "gemini_front_step_pose_01")
        let frontButtonIdleOne = try Self.loadFrame(named: "gemini_front_button_idle_pose_01")
        let frontButtonIdleTwo = try Self.loadFrame(named: "gemini_front_button_idle_pose_02")
        let frontButtonReach = try Self.loadFrame(named: "gemini_front_button_reach_pose_01")
        let frontButtonPressOne = try Self.loadFrame(named: "gemini_front_button_press_pose_01")
        let frontButtonPressTwo = try Self.loadFrame(named: "gemini_front_button_press_pose_02")
        let frontButtonClick = try Self.loadFrame(named: "gemini_front_button_click_pose_01")
        let frontCelebrateOne = try Self.loadFrame(named: "gemini_front_celebrate_pose_01")
        let frontCelebrateTwo = try Self.loadFrame(named: "gemini_front_celebrate_pose_02")
        let frontAkimboOne = try Self.loadFrame(named: "gemini_front_arms_akimbo_pose_01")
        let frontAkimboTwo = try Self.loadFrame(named: "gemini_front_arms_akimbo_pose_02")
        let frontAkimboThree = try Self.loadFrame(named: "gemini_front_arms_akimbo_pose_03")
        let leftIdleAnimations = [
            RalphSpriteAnimation(frames: [leftIdle, leftPoseTwo, leftPoseThree, leftPoseTwo], frameDuration: 0.16),
            RalphSpriteAnimation(frames: [leftIdle, leftWalkPoseOne, leftIdle, leftWalkPoseTwo], frameDuration: 0.18),
        ]
        let upIdleAnimations = [
            RalphSpriteAnimation(frames: upWalkFrames, frameDuration: 0.18),
            RalphSpriteAnimation(frames: [backGeminiIdle, upWalkFrames[1], backGeminiIdle, upWalkFrames[2]], frameDuration: 0.2),
        ]
        let downIdleAnimations = [
            RalphSpriteAnimation(frames: [frontIdle, frontStep, frontIdle], frameDuration: 0.2),
            RalphSpriteAnimation(frames: [frontButtonIdleOne, frontButtonIdleTwo, frontButtonIdleOne], frameDuration: 0.18),
            RalphSpriteAnimation(frames: [frontAkimboOne, frontAkimboTwo, frontAkimboThree, frontAkimboTwo], frameDuration: 0.18),
            RalphSpriteAnimation(frames: [frontCelebrateOne, frontCelebrateTwo], frameDuration: 0.22),
        ]
        let clickDown = RalphSpriteAnimation(
            frames: [
                frontButtonIdleOne,
                frontButtonReach,
                frontButtonPressOne,
                frontButtonPressTwo,
                frontButtonClick,
                frontButtonPressTwo,
                frontButtonIdleTwo,
                frontButtonIdleOne,
            ],
            frameDuration: 0.08,
            repeats: false)

        return RalphSpriteAnimationSet(
            walkLeft: RalphSpriteAnimation(frames: leftWalkFrames, frameDuration: 0.10),
            walkRight: RalphSpriteAnimation(frames: leftWalkFrames.map(Self.mirror), frameDuration: 0.10),
            walkUp: RalphSpriteAnimation(frames: upWalkFrames, frameDuration: 0.11),
            walkDown: RalphSpriteAnimation(frames: downWalkFrames, frameDuration: 0.09),
            idleLeftAnimations: leftIdleAnimations,
            idleRightAnimations: leftIdleAnimations.map(Self.mirror),
            idleUpAnimations: upIdleAnimations,
            idleDownAnimations: downIdleAnimations,
            clickDown: clickDown)
    }

    private static func loadFrames(named names: [String]) throws -> [RalphSpriteFrame] {
        try names.map(Self.loadFrame(named:))
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

    private static func mirror(_ animation: RalphSpriteAnimation) -> RalphSpriteAnimation {
        RalphSpriteAnimation(frames: animation.frames.map(Self.mirror), frameDuration: animation.frameDuration)
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
