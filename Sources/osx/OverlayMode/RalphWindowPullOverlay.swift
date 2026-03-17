import AppKit
import Foundation

@MainActor
final class RalphWindowPullOverlay: NSWindowController {
    enum Edge {
        case left
        case right
        case top
        case bottom
    }

    static let titleBarHeight: CGFloat = 38

    private let titleField = NSTextField(labelWithString: "")

    static func make() -> RalphWindowPullOverlay {
        let frame = CGRect(x: 0, y: 0, width: 480, height: 320)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        return RalphWindowPullOverlay(window: window)
    }

    override init(window: NSWindow?) {
        super.init(window: window)

        let contentView = RalphWindowShellView(frame: window?.contentView?.bounds ?? .zero)
        contentView.autoresizingMask = [.width, .height]
        window?.contentView = contentView

        self.titleField.textColor = NSColor(white: 0.18, alpha: 1)
        self.titleField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        self.titleField.alignment = .left
        self.titleField.frame = CGRect(x: 18, y: contentView.bounds.height - 28, width: 320, height: 20)
        self.titleField.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(self.titleField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(title: String, frame: CGRect) {
        self.titleField.stringValue = title
        self.window?.setFrame(frame, display: true)
        self.window?.orderFrontRegardless()
    }

    func move(to frame: CGRect) {
        self.window?.setFrame(frame, display: true)
    }

    func hide() {
        self.window?.orderOut(nil)
    }

    static func destinationFrame(in desktop: CGRect) -> CGRect {
        let width = min(520, max(360, desktop.width * 0.34))
        let height = min(360, max(240, desktop.height * 0.36))
        return CGRect(
            x: desktop.midX - (width / 2),
            y: desktop.midY - (height / 2),
            width: width,
            height: height)
    }

    static func nearestEdge(to point: CGPoint, in desktop: CGRect) -> Edge {
        let distances: [(Edge, CGFloat)] = [
            (.left, abs(point.x - desktop.minX)),
            (.right, abs(desktop.maxX - point.x)),
            (.top, abs(desktop.maxY - point.y)),
            (.bottom, abs(point.y - desktop.minY)),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .left
    }

    static func startFrame(for destinationFrame: CGRect, edge: Edge, in desktop: CGRect) -> CGRect {
        switch edge {
        case .left:
            return destinationFrame.offsetBy(dx: desktop.minX - destinationFrame.maxX - 24, dy: 0)
        case .right:
            return destinationFrame.offsetBy(dx: desktop.maxX - destinationFrame.minX + 24, dy: 0)
        case .top:
            return destinationFrame.offsetBy(dx: 0, dy: desktop.maxY - destinationFrame.minY + 24)
        case .bottom:
            return destinationFrame.offsetBy(dx: 0, dy: desktop.minY - destinationFrame.maxY - 24)
        }
    }

    static func handlePoint(for frame: CGRect, edge: Edge) -> CGPoint {
        switch edge {
        case .left:
            return CGPoint(x: frame.minX, y: frame.midY)
        case .right:
            return CGPoint(x: frame.maxX, y: frame.midY)
        case .top:
            return CGPoint(x: frame.midX, y: frame.minY)
        case .bottom:
            return CGPoint(x: frame.midX, y: frame.maxY)
        }
    }
}

private final class RalphWindowShellView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds.insetBy(dx: 6, dy: 6)
        let shellPath = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
        shellPath.fill()

        NSColor(calibratedWhite: 0, alpha: 0.10).setStroke()
        shellPath.lineWidth = 1
        shellPath.stroke()

        let titleBarRect = CGRect(
            x: bounds.minX,
            y: bounds.maxY - RalphWindowPullOverlay.titleBarHeight,
            width: bounds.width,
            height: RalphWindowPullOverlay.titleBarHeight)
        let titleBarPath = NSBezierPath(
            roundedRect: titleBarRect,
            xRadius: 14,
            yRadius: 14)
        NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.98, alpha: 0.98).setFill()
        titleBarPath.fill()

        let buttonColors: [NSColor] = [
            NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.25, alpha: 1),
        ]
        for (index, color) in buttonColors.enumerated() {
            color.setFill()
            let circle = NSBezierPath(ovalIn: CGRect(x: bounds.minX + 16 + (CGFloat(index) * 16), y: bounds.maxY - 24, width: 10, height: 10))
            circle.fill()
        }
    }
}
