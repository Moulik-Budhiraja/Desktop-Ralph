import AppKit
import Foundation

@MainActor
final class OverlaySceneView: NSView {
    private let indicatorView = PenguinIndicatorView(frame: CGRect(x: 0, y: 0, width: 42, height: 42))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.indicatorView.alphaValue = 0
        self.addSubview(self.indicatorView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    func moveIndicator(to targetFrame: CGRect, duration: TimeInterval) {
        let center = ActionVisualizationPlanner.clampedCenter(for: targetFrame, in: self.bounds)
        let size = CGSize(width: 42, height: 42)
        let destination = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.indicatorView.animator().alphaValue = 1
            self.indicatorView.animator().frame = destination
        }
    }

    func flashIndicator() {
        self.indicatorView.flash()
    }

    func hideIndicator() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            self.indicatorView.animator().alphaValue = 0
        }
    }
}

@MainActor
private final class PenguinIndicatorView: NSView {
    private var fillColor = NSColor(calibratedRed: 0.14, green: 0.67, blue: 0.90, alpha: 0.95)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.cornerRadius = 12
        self.layer?.borderWidth = 2
        self.layer?.borderColor = NSColor.white.withAlphaComponent(0.75).cgColor
        self.layer?.backgroundColor = self.fillColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func flash() {
        let original = self.fillColor
        self.fillColor = NSColor.systemYellow.withAlphaComponent(0.98)
        self.layer?.backgroundColor = self.fillColor.cgColor

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.fillColor = original
            self.layer?.backgroundColor = original.cgColor
        }
    }
}
