import AppKit
import Foundation

@MainActor
final class OverlayWindowController: NSWindowController {
    private let sceneView: OverlaySceneView

    init() {
        let frame = OverlayWindowController.desktopFrame()
        self.sceneView = OverlaySceneView(frame: frame)

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = self.sceneView
        window.orderFrontRegardless()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func moveIndicator(to frame: CGRect, duration: TimeInterval) {
        self.window?.setFrame(Self.desktopFrame(), display: false)
        self.sceneView.moveIndicator(to: frame, duration: duration)
        self.window?.orderFrontRegardless()
    }

    func flashIndicator() {
        self.sceneView.flashIndicator()
    }

    func hideIndicator() {
        self.sceneView.hideIndicator()
    }

    private static func desktopFrame() -> CGRect {
        NSScreen.screens.map(\.frame).reduce(CGRect.null) { partial, frame in
            partial.union(frame)
        }
    }
}
