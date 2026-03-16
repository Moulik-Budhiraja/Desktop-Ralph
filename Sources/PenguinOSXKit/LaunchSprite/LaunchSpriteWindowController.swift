import AppKit
import Foundation

@MainActor
final class LaunchSpriteWindowController: NSWindowController {
    private static let spriteDisplaySize = CGSize(width: 128, height: 160)
    private static let contentSize = CGSize(width: 292, height: 208)

    static func make() throws -> LaunchSpriteWindowController {
        let frames = try LaunchSpriteAssetLoader.loadSpriteFrames()
        return LaunchSpriteWindowController(frames: frames)
    }

    private init(frames: [NSImage]) {
        let frame = Self.randomFrame(for: Self.contentSize)
        let contentView = LaunchSpriteView(frame: CGRect(origin: .zero, size: frame.size), frames: frames)

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
}

enum LaunchSpriteAssetLoader {
    private static let frameResourceNames = [
        "front_center_pose_01",
        "front_three_quarter_right_pose_01",
        "right_profile_walk_pose_01",
        "back_pose_01",
        "left_profile_pose_01",
        "front_three_quarter_left_pose_01",
    ]

    static func loadSpriteFrames() throws -> [NSImage] {
        let cycle = Self.frameResourceNames + Self.frameResourceNames.dropFirst().dropLast().reversed()
        let frames = try cycle.map(Self.loadFrame(named:))
        guard !frames.isEmpty else {
            throw LaunchSpriteError.missingAsset("Missing Ralph launch sprite frames.")
        }
        return frames
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
