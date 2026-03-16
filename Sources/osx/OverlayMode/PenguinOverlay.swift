import AppKit
import Foundation

@MainActor
final class PenguinOverlayController {
    static let shared = PenguinOverlayController()

    private let window: NSWindow
    private let overlayView: PenguinOverlayView
    private var screenFrame: CGRect

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

    func showPlaceholder(at targetFrame: CGRect, dwellTime: TimeInterval = 0.2) {
        guard !targetFrame.isNull, !targetFrame.isEmpty else { return }

        self.ensureAppReady()
        self.refreshScreenFrame()
        self.overlayView.placeholderFrame = self.placeholderFrame(for: targetFrame)
        self.window.orderFrontRegardless()
        self.window.displayIfNeeded()
        self.overlayView.displayIfNeeded()
        self.pumpRunLoop(for: dwellTime)
        self.hide()
    }

    func hide() {
        self.overlayView.placeholderFrame = nil
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
        let size = CGSize(width: 36, height: 36)
        let localMidX = targetFrame.midX - self.screenFrame.minX
        let localMidYFromTop = targetFrame.midY - self.screenFrame.minY
        let flippedMidY = self.screenFrame.height - localMidYFromTop
        let origin = CGPoint(
            x: localMidX - (size.width / 2),
            y: flippedMidY - (size.height / 2))
        return CGRect(origin: origin, size: size).integral
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
    let dwellTime: TimeInterval

    init(dwellTime: TimeInterval = 0.2) {
        self.dwellTime = dwellTime
    }

    func willPerform(_ context: ActionExecutionContext) throws {
        guard let targetFrame = self.primaryTargetFrame(for: context.statement, targets: context.targets) else {
            return
        }

        PenguinOverlayController.shared.showPlaceholder(at: targetFrame, dwellTime: self.dwellTime)
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
