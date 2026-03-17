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
    private var hasPositionedSprite = false
    private var currentWalkDirection: RalphSpriteMovementDirection?

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
        let startOrigin = self.hasPositionedSprite ? currentOrigin : Self.offscreenOrigin(toward: destinationOrigin)
        self.animateWalk(from: startOrigin, to: destinationOrigin)
    }

    func dwell(for duration: TimeInterval) {
        guard duration > 0 else { return }
        let endDate = Date().addingTimeInterval(duration)
        while Date() < endDate {
            RunLoop.current.run(mode: .default, before: min(endDate, Date().addingTimeInterval(0.01)))
        }
    }

    func pullWindow(
        title: String,
        edge: RalphWindowPullOverlay.Edge,
        windowStartFrame: CGRect,
        windowDestinationFrame: CGRect,
        dwellTime: TimeInterval)
    {
        let shell = RalphWindowPullOverlay.make()
        let stageHandle = RalphWindowPullOverlay.handlePoint(
            for: Self.visibleEdgeFrame(from: windowStartFrame, edge: edge),
            edge: edge)
        let destinationHandle = RalphWindowPullOverlay.handlePoint(
            for: windowDestinationFrame,
            edge: edge)
        let currentOrigin = self.window?.frame.origin ?? .zero
        let stageOrigin = Self.origin(forWindowHandlePoint: stageHandle, edge: edge)
        let startOrigin = self.hasPositionedSprite ? currentOrigin : Self.offscreenOrigin(toward: stageOrigin)

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
            let currentDirection: RalphSpriteMovementDirection
            if progress >= 1 {
                currentDirection = direction
            } else {
                currentDirection = RalphSpriteMovementDirection.resolve(from: stageOrigin, to: spriteOrigin)
            }
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
        let stageHandle = RalphWindowPullOverlay.handlePoint(
            for: Self.visibleEdgeFrame(from: windowStartFrame, edge: edge),
            edge: edge)
        let destinationHandle = RalphWindowPullOverlay.handlePoint(
            for: windowDestinationFrame,
            edge: edge)
        let currentOrigin = self.window?.frame.origin ?? .zero
        let stageOrigin = Self.origin(forWindowHandlePoint: stageHandle, edge: edge)
        let startOrigin = self.hasPositionedSprite ? currentOrigin : Self.offscreenOrigin(toward: stageOrigin)

        self.animateWalk(from: startOrigin, to: stageOrigin)
        moveWindow(windowStartFrame)

        let destinationOrigin = Self.origin(forWindowHandlePoint: destinationHandle, edge: edge)
        let direction = RalphSpriteMovementDirection.resolve(
            from: stageOrigin,
            to: destinationOrigin)
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
            x: point.x - offset.x,
            y: point.y - offset.y)
    }

    static func offscreenOrigin(toward destination: CGPoint) -> CGPoint {
        let desktop = Self.desktopFrame()
        let start = CGPoint(
            x: max(desktop.minX, destination.x - 120),
            y: min(desktop.maxY - Self.spriteSize.height, destination.y + 80))
        return Self.clampedOrigin(start)
    }

    static func clampedOrigin(_ origin: CGPoint) -> CGPoint {
        let desktop = Self.desktopFrame()
        return CGPoint(
            x: min(max(origin.x, desktop.minX), desktop.maxX - Self.spriteSize.width),
            y: min(max(origin.y, desktop.minY), desktop.maxY - Self.spriteSize.height))
    }

    static func desktopFrame() -> CGRect {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }
    }

    private static func visibleEdgeFrame(from frame: CGRect, edge: RalphWindowPullOverlay.Edge) -> CGRect {
        let desktop = Self.desktopFrame()
        switch edge {
        case .left:
            return CGRect(x: desktop.minX, y: frame.minY, width: frame.width, height: frame.height)
        case .right:
            return CGRect(x: desktop.maxX - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        case .top:
            return CGRect(x: frame.minX, y: desktop.maxY - frame.height, width: frame.width, height: frame.height)
        case .bottom:
            return CGRect(x: frame.minX, y: desktop.minY, width: frame.width, height: frame.height)
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
        window.setFrameOrigin(Self.clampedOrigin(origin))
        window.orderFrontRegardless()
        self.hasPositionedSprite = true
        self.currentWalkDirection = direction
        self.spriteView.playWalk(direction: direction)
    }

    private func updateWalk(to origin: CGPoint, direction: RalphSpriteMovementDirection) {
        guard let window else { return }
        window.setFrameOrigin(Self.clampedOrigin(origin))
        self.hasPositionedSprite = true
        if self.currentWalkDirection != direction {
            self.currentWalkDirection = direction
            self.spriteView.playWalk(direction: direction)
        }
    }

    private func endWalk(at origin: CGPoint, direction: RalphSpriteMovementDirection) {
        guard let window else { return }
        window.setFrameOrigin(Self.clampedOrigin(origin))
        self.hasPositionedSprite = true
        self.currentWalkDirection = nil
        self.spriteView.showIdle(direction: direction)
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
