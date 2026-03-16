import AppKit
import Foundation

@MainActor
final class PenguinOverlayController {
    static let shared = PenguinOverlayController()

    private static let placeholderSize = CGSize(width: 36, height: 36)

    private let window: NSWindow
    private let overlayView: PenguinOverlayView
    private var screenFrame: CGRect
    private var lastPlaceholderFrame: CGRect?

    private init() {
        self.screenFrame = Self.combinedScreenFrame()
        self.overlayView = PenguinOverlayView(frame: CGRect(origin: .zero, size: self.screenFrame.size))
        self.window = NSWindow(
            contentRect: self.screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)

        self.window.isOpaque = false
        self.window.backgroundColor = .clear
        self.window.hasShadow = false
        self.window.ignoresMouseEvents = true
        self.window.level = .screenSaver
        self.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.window.setFrame(self.screenFrame, display: false)
        self.window.contentView = self.overlayView
    }

    func showPlaceholder(
        at targetFrame: CGRect,
        animationDuration: TimeInterval = 0.18,
        dwellTime: TimeInterval = 0.2)
    {
        guard !targetFrame.isNull, !targetFrame.isEmpty else { return }

        self.ensureAppReady()
        self.refreshScreenFrame()
        let destinationFrame = self.placeholderFrame(for: targetFrame)
        let startingFrame = self.lastPlaceholderFrame ?? self.offscreenStartFrame(for: destinationFrame)

        self.overlayView.placeholderFrame = startingFrame
        self.window.orderFrontRegardless()
        self.window.displayIfNeeded()
        self.overlayView.displayIfNeeded()
        self.animatePlaceholder(from: startingFrame, to: destinationFrame, duration: animationDuration)
        self.pumpRunLoop(for: dwellTime)
        self.lastPlaceholderFrame = destinationFrame
        self.hide()
    }

    func hide() {
        if let currentFrame = self.overlayView.placeholderFrame {
            self.lastPlaceholderFrame = currentFrame
        }
        self.window.orderOut(nil)
    }

    private func ensureAppReady() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
    }

    private func refreshScreenFrame() {
        let newFrame = Self.combinedScreenFrame()
        guard newFrame != self.screenFrame else { return }

        self.screenFrame = newFrame
        self.window.setFrame(newFrame, display: false)
        self.overlayView.frame = CGRect(origin: .zero, size: newFrame.size)
        self.overlayView.needsDisplay = true
    }

    private func placeholderFrame(for targetFrame: CGRect) -> CGRect {
        let localMidX = targetFrame.midX - self.screenFrame.minX
        let localMidYFromTop = targetFrame.midY - self.screenFrame.minY
        let flippedMidY = self.screenFrame.height - localMidYFromTop
        let origin = CGPoint(
            x: localMidX - (Self.placeholderSize.width / 2),
            y: flippedMidY - (Self.placeholderSize.height / 2))
        return CGRect(origin: origin, size: Self.placeholderSize).integral
    }

    private func offscreenStartFrame(for destinationFrame: CGRect) -> CGRect {
        let startX = max(0, min(self.screenFrame.width - destinationFrame.width, destinationFrame.minX - 120))
        let startY = min(self.screenFrame.height - destinationFrame.height, destinationFrame.maxY + 80)
        return CGRect(
            origin: CGPoint(x: startX, y: max(0, startY)),
            size: destinationFrame.size).integral
    }

    private func animatePlaceholder(from startFrame: CGRect, to endFrame: CGRect, duration: TimeInterval) {
        guard duration > 0 else {
            self.overlayView.placeholderFrame = endFrame
            self.overlayView.displayIfNeeded()
            return
        }

        let startedAt = Date()
        let endDate = startedAt.addingTimeInterval(duration)

        while Date() < endDate {
            let elapsed = Date().timeIntervalSince(startedAt)
            let progress = min(1, elapsed / duration)
            let eased = self.easeInOutCubic(progress)
            self.overlayView.placeholderFrame = self.interpolate(from: startFrame, to: endFrame, progress: eased)
            self.window.displayIfNeeded()
            self.overlayView.displayIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        self.overlayView.placeholderFrame = endFrame
        self.window.displayIfNeeded()
        self.overlayView.displayIfNeeded()
    }

    private func interpolate(from startFrame: CGRect, to endFrame: CGRect, progress: CGFloat) -> CGRect {
        let origin = CGPoint(
            x: startFrame.origin.x + ((endFrame.origin.x - startFrame.origin.x) * progress),
            y: startFrame.origin.y + ((endFrame.origin.y - startFrame.origin.y) * progress))
        let size = CGSize(
            width: startFrame.size.width + ((endFrame.size.width - startFrame.size.width) * progress),
            height: startFrame.size.height + ((endFrame.size.height - startFrame.size.height) * progress))
        return CGRect(origin: origin, size: size).integral
    }

    private func easeInOutCubic(_ progress: Double) -> CGFloat {
        if progress < 0.5 {
            return CGFloat(4 * progress * progress * progress)
        }

        let adjusted = (-2 * progress) + 2
        return CGFloat(1 - ((adjusted * adjusted * adjusted) / 2))
    }

    private func pumpRunLoop(for dwellTime: TimeInterval) {
        let endDate = Date().addingTimeInterval(dwellTime)
        while Date() < endDate {
            RunLoop.current.run(mode: .default, before: min(endDate, Date().addingTimeInterval(0.01)))
        }
    }

    private static func combinedScreenFrame() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }
    }
}

@MainActor
private final class PenguinOverlayView: NSView {
    var placeholderFrame: CGRect? {
        didSet {
            self.needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let placeholderFrame else { return }

        NSColor.systemTeal.withAlphaComponent(0.18).setFill()
        placeholderFrame.fill()

        let insetFrame = placeholderFrame.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: insetFrame, xRadius: 8, yRadius: 8)
        NSColor.systemYellow.withAlphaComponent(0.95).setFill()
        path.fill()

        NSColor.black.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

@MainActor
struct OverlayActionExecutionMiddleware: ActionExecutionMiddleware {
    let animationDuration: TimeInterval
    let dwellTime: TimeInterval

    init(animationDuration: TimeInterval = 0.18, dwellTime: TimeInterval = 0.2) {
        self.animationDuration = animationDuration
        self.dwellTime = dwellTime
    }

    func willPerform(_ context: ActionExecutionContext) throws {
        guard let targetFrame = self.primaryTargetFrame(for: context.statement, targets: context.targets) else {
            return
        }

        PenguinOverlayController.shared.showPlaceholder(
            at: targetFrame,
            animationDuration: self.animationDuration,
            dwellTime: self.dwellTime)
    }

    private func primaryTargetFrame(
        for statement: OXAStatement,
        targets: [ActionTargetDescriptor]) -> CGRect?
    {
        switch statement {
        case .sendClick,
             .sendRightClick,
             .sendText,
             .sendTextAsKeys,
             .sendHotkey,
             .sendScroll,
             .sendScrollIntoView,
             .readAttribute:
            return targets.first?.frame
        case .sendDrag:
            return targets.first?.frame
        case .sleep, .open, .close:
            return nil
        }
    }
}
