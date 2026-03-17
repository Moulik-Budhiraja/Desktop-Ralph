import AppKit
import Foundation

@MainActor
final class RalphSpriteWindowController: NSWindowController {
    static let spriteSize = CGSize(width: 128, height: 160)
    static let interactionOffset = CGPoint(x: 64, y: 28)
    static let rightFacingPullOffset = CGPoint(x: 96, y: 82)
    static let leftFacingPullOffset = CGPoint(x: 32, y: 82)
    static let verticalPullOffset = CGPoint(x: 64, y: 82)

    private let spriteView: RalphSpriteView
    private let animations: RalphSpriteAnimationSet
    private var bubbleMessage: String
    private var windowSize: CGSize {
        RalphSpriteView.contentSize(for: self.bubbleMessage)
    }
    private var hasPositionedSprite = false
    private var currentWalkDirection: RalphSpriteMovementDirection?

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
        let initialOrigin = Self.defaultRestingOrigin(windowSize: spriteWindowSize)

        let window = NSWindow(
            contentRect: CGRect(origin: initialOrigin, size: spriteWindowSize),
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
        let startOrigin = self.hasPositionedSprite ? currentOrigin : self.offscreenOrigin(toward: destinationOrigin)
        self.animateWalk(from: startOrigin, to: destinationOrigin)
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

    func pullWindow(
        title: String,
        edge: RalphWindowPullOverlay.Edge,
        windowStartFrame: CGRect,
        windowDestinationFrame: CGRect,
        dwellTime: TimeInterval)
    {
        let shell = RalphWindowPullOverlay.make()
        let destinationHandle = RalphWindowPullOverlay.handlePoint(
            for: windowDestinationFrame,
            edge: edge)
        let stageHandle = Self.screenEdgeHandle(for: edge, alignedWith: destinationHandle)
        let currentOrigin = self.window?.frame.origin ?? .zero
        let stageOrigin = Self.origin(forWindowHandlePoint: stageHandle, edge: edge)
        let startOrigin = self.hasPositionedSprite ? currentOrigin : Self.defaultRestingOrigin(windowSize: self.windowSize)

        self.animateWalk(from: startOrigin, to: stageOrigin)
        shell.show(title: title, frame: windowStartFrame)

        let destinationOrigin = Self.origin(forWindowHandlePoint: destinationHandle, edge: edge)
        let direction = RalphSpriteMovementDirection.resolve(from: stageOrigin, to: destinationOrigin)
        self.beginWalk(at: stageOrigin, direction: direction)
        RalphMotionAnimator.animate(
            from: windowStartFrame.origin,
            to: windowDestinationFrame.origin,
            desktopWidth: Self.desktopFrame().width)
        { [weak self] shellOrigin, progress in
            guard let self else { return }
            let currentFrame = CGRect(origin: shellOrigin, size: windowDestinationFrame.size)
            let currentHandle = RalphWindowPullOverlay.handlePoint(for: currentFrame, edge: edge)
            let spriteOrigin = Self.origin(forWindowHandlePoint: currentHandle, edge: edge)
            let currentDirection = progress >= 1
                ? direction
                : RalphSpriteMovementDirection.resolve(from: stageOrigin, to: spriteOrigin)
            self.updateWalk(to: spriteOrigin, direction: currentDirection)
            shell.move(to: currentFrame)
        }

        self.endWalk(at: destinationOrigin, direction: direction)
        self.dwell(for: dwellTime)
        shell.hide()
    }

    func pullLiveWindow(
        edge: RalphWindowPullOverlay.Edge,
        windowStartFrame: CGRect,
        windowDestinationFrame: CGRect,
        dwellTime: TimeInterval,
        moveWindow: (CGRect) -> Void)
    {
        let destinationHandle = RalphWindowPullOverlay.handlePoint(
            for: windowDestinationFrame,
            edge: edge)
        let stageHandle = Self.screenEdgeHandle(for: edge, alignedWith: destinationHandle)
        let currentOrigin = self.window?.frame.origin ?? .zero
        let stageOrigin = Self.origin(forWindowHandlePoint: stageHandle, edge: edge)
        let startOrigin = self.hasPositionedSprite ? currentOrigin : Self.defaultRestingOrigin(windowSize: self.windowSize)

        self.animateWalk(from: startOrigin, to: stageOrigin)
        moveWindow(windowStartFrame)

        let destinationOrigin = Self.origin(forWindowHandlePoint: destinationHandle, edge: edge)
        let direction = RalphSpriteMovementDirection.resolve(from: stageOrigin, to: destinationOrigin)
        self.beginWalk(at: stageOrigin, direction: direction)
        RalphMotionAnimator.animate(
            from: windowStartFrame.origin,
            to: windowDestinationFrame.origin,
            desktopWidth: Self.desktopFrame().width)
        { [weak self] windowOrigin, progress in
            guard let self else { return }
            let currentFrame = CGRect(origin: windowOrigin, size: windowDestinationFrame.size)
            let currentHandle = RalphWindowPullOverlay.handlePoint(for: currentFrame, edge: edge)
            let spriteOrigin = Self.origin(forWindowHandlePoint: currentHandle, edge: edge)
            let currentDirection = progress >= 1
                ? direction
                : RalphSpriteMovementDirection.resolve(from: stageOrigin, to: spriteOrigin)
            self.updateWalk(to: spriteOrigin, direction: currentDirection)
            moveWindow(currentFrame)
        }

        self.endWalk(at: destinationOrigin, direction: direction)
        self.dwell(for: dwellTime)
    }

    static func spriteOrigin(for targetFrame: CGRect) -> CGPoint {
        let desktop = Self.desktopFrame()
        let targetCenter = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let localMidYFromTop = targetCenter.y - desktop.minY
        let flippedCenterY = desktop.minY + (desktop.height - localMidYFromTop)
        return Self.origin(forInteractionPoint: CGPoint(x: targetCenter.x, y: flippedCenterY))
    }

    static func origin(forInteractionPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - Self.interactionOffset.x,
            y: point.y - Self.interactionOffset.y)
    }

    static func origin(forWindowHandlePoint point: CGPoint, edge: RalphWindowPullOverlay.Edge) -> CGPoint {
        let desktop = Self.desktopFrame()
        let localY = point.y - desktop.minY
        let flippedPoint = CGPoint(
            x: point.x,
            y: desktop.minY + (desktop.height - localY))
        let offset: CGPoint
        switch edge {
        case .left:
            offset = Self.rightFacingPullOffset
        case .right:
            offset = Self.leftFacingPullOffset
        case .top, .bottom:
            offset = Self.verticalPullOffset
        }

        return CGPoint(
            x: flippedPoint.x - offset.x,
            y: flippedPoint.y - offset.y)
    }

    private func offscreenOrigin(toward destination: CGPoint) -> CGPoint {
        let desktop = Self.desktopFrame()
        let start = CGPoint(
            x: max(desktop.minX, destination.x - 120),
            y: min(desktop.maxY - self.windowSize.height, destination.y + 80))
        return self.clampedOrigin(start)
    }

    private static func defaultRestingOrigin(windowSize: CGSize) -> CGPoint {
        let desktop = NSScreen.main?.visibleFrame ?? Self.desktopFrame()
        return Self.clampedOrigin(
            CGPoint(
                x: desktop.minX + 48,
                y: desktop.minY + 48),
            windowSize: windowSize)
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

    static func desktopFrame() -> CGRect {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }
    }

    private static func screenEdgeHandle(
        for edge: RalphWindowPullOverlay.Edge,
        alignedWith destinationHandle: CGPoint) -> CGPoint
    {
        let desktop = Self.desktopFrame()
        switch edge {
        case .left:
            return CGPoint(x: desktop.minX, y: destinationHandle.y)
        case .right:
            return CGPoint(x: desktop.maxX, y: destinationHandle.y)
        case .top:
            return CGPoint(x: destinationHandle.x, y: desktop.maxY)
        case .bottom:
            return CGPoint(x: destinationHandle.x, y: desktop.minY)
        }
    }

    private func animateWalk(from startOrigin: CGPoint, to destinationOrigin: CGPoint) {
        let direction = RalphSpriteMovementDirection.resolve(from: startOrigin, to: destinationOrigin)
        self.beginWalk(at: startOrigin, direction: direction)
        RalphMotionAnimator.animate(
            from: startOrigin,
            to: destinationOrigin,
            desktopWidth: Self.desktopFrame().width)
        { [weak self] currentOrigin, progress in
            guard let self else { return }
            let currentDirection = progress >= 1
                ? direction
                : RalphSpriteMovementDirection.resolve(from: startOrigin, to: destinationOrigin)
            self.updateWalk(to: currentOrigin, direction: currentDirection)
        }
        self.endWalk(at: destinationOrigin, direction: direction)
    }

    private func beginWalk(at origin: CGPoint, direction: RalphSpriteMovementDirection) {
        guard let window else { return }
        window.setFrameOrigin(self.clampedOrigin(origin))
        window.orderFrontRegardless()
        self.hasPositionedSprite = true
        self.currentWalkDirection = direction
        self.spriteView.playWalk(direction: direction)
    }

    private func updateWalk(to origin: CGPoint, direction: RalphSpriteMovementDirection) {
        guard let window else { return }
        window.setFrameOrigin(self.clampedOrigin(origin))
        self.hasPositionedSprite = true
        if self.currentWalkDirection != direction {
            self.currentWalkDirection = direction
            self.spriteView.playWalk(direction: direction)
        }
    }

    private func endWalk(at origin: CGPoint, direction: RalphSpriteMovementDirection) {
        guard let window else { return }
        window.setFrameOrigin(self.clampedOrigin(origin))
        self.hasPositionedSprite = true
        self.currentWalkDirection = nil
        self.spriteView.showIdle(direction: direction)
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
        let frontWaveOne = try Self.loadFrame(named: "gemini_front_wave_pose_01")
        let frontWaveTwo = try Self.loadFrame(named: "gemini_front_wave_pose_02")
        let frontPoint = try Self.loadFrame(named: "gemini_front_point_pose_01")
        let frontTurnaroundLeft = try Self.loadFrame(named: "gemini_turnaround_front_left_three_quarter_pose_01")
        let frontTurnaroundRight = try Self.loadFrame(named: "gemini_turnaround_front_right_three_quarter_pose_01")
        let frontTurnaround = try Self.loadFrame(named: "gemini_turnaround_front_pose_01")
        let backTurnaround = try Self.loadFrame(named: "gemini_turnaround_back_pose_01")
        let tumbleOne = try Self.loadFrame(named: "gemini_tumble_pose_01")
        let tumbleTwo = try Self.loadFrame(named: "gemini_tumble_pose_02")
        let upsideDown = try Self.loadFrame(named: "gemini_upside_down_pose_01")
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
        let ambientIdleAnimations = [
            RalphSpriteAnimation(frames: [frontWaveOne, frontWaveTwo, frontWaveOne, frontIdle], frameDuration: 0.18, repeats: false),
            RalphSpriteAnimation(frames: [frontCelebrateOne, frontCelebrateTwo, frontCelebrateOne, frontIdle], frameDuration: 0.18, repeats: false),
            RalphSpriteAnimation(frames: [frontPoint, frontWaveOne, frontPoint, frontIdle], frameDuration: 0.16, repeats: false),
            RalphSpriteAnimation(frames: [frontTurnaround, frontTurnaroundLeft, backTurnaround, frontTurnaroundRight, frontTurnaround], frameDuration: 0.14, repeats: false),
            RalphSpriteAnimation(frames: [tumbleOne, upsideDown, tumbleTwo, frontIdle], frameDuration: 0.14, repeats: false),
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
            ambientIdleAnimations: ambientIdleAnimations,
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
