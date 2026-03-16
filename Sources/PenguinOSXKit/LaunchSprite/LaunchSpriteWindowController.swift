import AppKit
import Foundation

@MainActor
final class LaunchSpriteWindowController: NSWindowController {
    private static let contentSize = CGSize(width: 292, height: 208)
    private let spriteView: LaunchSpriteView

    static func make() throws -> LaunchSpriteWindowController {
        let animations = try LaunchSpriteAssetLoader.loadAnimationSet()
        return LaunchSpriteWindowController(animations: animations)
    }

    private init(animations: LaunchSpriteAnimationSet) {
        let frame = Self.randomFrame(for: Self.contentSize)
        let contentView = LaunchSpriteView(frame: CGRect(origin: .zero, size: frame.size), animations: animations)
        self.spriteView = contentView

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovable = false
        window.contentView = contentView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        self.window?.orderFrontRegardless()
    }

    func setSpriteOrigin(_ origin: CGPoint) {
        guard let window else { return }
        window.setFrameOrigin(Self.clampedOrigin(origin, size: window.frame.size))
    }

    func moveSprite(to destination: CGPoint, duration: TimeInterval) async {
        guard let window else { return }
        await self.moveSprite(from: window.frame.origin, to: destination, duration: duration)
    }

    func moveSprite(from start: CGPoint, to destination: CGPoint, duration: TimeInterval) async {
        guard let window else { return }

        let startOrigin = Self.clampedOrigin(start, size: window.frame.size)
        let endOrigin = Self.clampedOrigin(destination, size: window.frame.size)
        window.setFrameOrigin(startOrigin)
        self.spriteView.playAnimation(forMovementFrom: startOrigin, to: endOrigin)
        window.orderFrontRegardless()

        guard duration > 0 else {
            window.setFrameOrigin(endOrigin)
            self.spriteView.playIdleSpin()
            return
        }

        let steps = max(Int(duration / 0.016), 1)
        let sleepNanoseconds = UInt64((duration / Double(steps)) * 1_000_000_000)

        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let eased = Self.easeInOut(progress)
            let currentOrigin = CGPoint(
                x: startOrigin.x + (endOrigin.x - startOrigin.x) * eased,
                y: startOrigin.y + (endOrigin.y - startOrigin.y) * eased)
            window.setFrameOrigin(currentOrigin)
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
        }

        window.setFrameOrigin(endOrigin)
        self.spriteView.playIdleSpin()
    }

    func currentSpriteOrigin() -> CGPoint? {
        self.window?.frame.origin
    }

    func randomSpriteOrigin(minimumTravelDistance: CGFloat = 140) -> CGPoint {
        let desktop = NSScreen.screens.map(\.visibleFrame).reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }
        let fallback = self.window?.frame.origin ?? .zero
        guard let window, !desktop.isNull else { return fallback }

        let size = window.frame.size
        let minX = desktop.minX
        let maxX = desktop.maxX - size.width
        let minY = desktop.minY
        let maxY = desktop.maxY - size.height
        guard minX <= maxX, minY <= maxY else { return fallback }

        let current = window.frame.origin
        for _ in 0..<12 {
            let candidate = CGPoint(
                x: CGFloat.random(in: minX...maxX),
                y: CGFloat.random(in: minY...maxY))
            if hypot(candidate.x - current.x, candidate.y - current.y) >= minimumTravelDistance {
                return candidate
            }
        }

        return CGPoint(
            x: CGFloat.random(in: minX...maxX),
            y: CGFloat.random(in: minY...maxY))
    }

    private static func randomFrame(for size: CGSize) -> CGRect {
        let screens = NSScreen.screens
        let screen = screens.randomElement() ?? NSScreen.main
        let availableFrame = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)

        let maxX = max(availableFrame.minX, availableFrame.maxX - size.width)
        let maxY = max(availableFrame.minY, availableFrame.maxY - size.height)

        let x = CGFloat.random(in: availableFrame.minX...maxX)
        let y = CGFloat.random(in: availableFrame.minY...maxY)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private static func clampedOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let desktop = NSScreen.screens.map(\.visibleFrame).reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }
        guard !desktop.isNull else { return origin }

        return CGPoint(
            x: min(max(origin.x, desktop.minX), desktop.maxX - size.width),
            y: min(max(origin.y, desktop.minY), desktop.maxY - size.height))
    }

    private static func easeInOut(_ progress: CGFloat) -> CGFloat {
        progress * progress * (3 - 2 * progress)
    }
}

enum LaunchSpriteAssetLoader {
    static func loadAnimationSet() throws -> LaunchSpriteAnimationSet {
        let idleFrames = try [
            "front_center_pose_01",
            "front_three_quarter_right_pose_01",
            "right_profile_walk_pose_01",
            "back_pose_01",
            "left_profile_pose_01",
            "front_three_quarter_left_pose_01",
        ].map(Self.loadFrame(named:))
        let walkLeftFrames = try [
            "left_profile_walk_pose_01",
            "left_profile_pose_02",
            "left_profile_walk_pose_02",
            "left_profile_pose_03",
        ].map(Self.loadFrame(named:))
        let walkUpFrames = try [
            "back_pose_01",
            "back_pose_02",
            "back_pose_03",
            "back_pose_04",
        ].map(Self.loadFrame(named:))
        let walkDownFrames = try [
            "front_center_pose_01",
            "front_center_pose_02",
            "front_center_pose_03",
            "front_center_pose_04",
        ].map(Self.loadFrame(named:))

        return LaunchSpriteAnimationSet(
            idleSpin: LaunchSpriteAnimation(
                frames: idleFrames,
                frameDuration: 0.18),
            walkLeft: LaunchSpriteAnimation(frames: walkLeftFrames, frameDuration: 0.10),
            walkRight: LaunchSpriteAnimation(
                frames: walkLeftFrames.map(Self.mirror),
                frameDuration: 0.10),
            walkUp: LaunchSpriteAnimation(frames: walkUpFrames, frameDuration: 0.11),
            walkDown: LaunchSpriteAnimation(frames: walkDownFrames, frameDuration: 0.11))
    }

    private static func loadFrame(named name: String) throws -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            throw LaunchSpriteError.missingAsset("Missing Ralph launch sprite resource '\(name).png'.")
        }
        guard let image = NSImage(contentsOf: url) else {
            throw LaunchSpriteError.missingAsset("Failed to load Ralph launch sprite resource '\(name).png'.")
        }
        return image
    }

    private static func mirror(_ image: NSImage) -> NSImage {
        let mirrored = NSImage(size: image.size)
        mirrored.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: image.size.width, yBy: 0)
        transform.scaleX(by: -1, yBy: 1)
        transform.concat()
        image.draw(in: CGRect(origin: .zero, size: image.size))
        mirrored.unlockFocus()
        return mirrored
    }
}

enum LaunchSpriteError: LocalizedError {
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case let .missingAsset(message):
            return message
        }
    }
}
