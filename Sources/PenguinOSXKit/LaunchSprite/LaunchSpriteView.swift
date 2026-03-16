import AppKit
import Foundation

@MainActor
final class LaunchSpriteView: NSView {
    private let imageView: NSImageView
    private let speechBubbleView = RalphSpeechBubbleView(frame: .zero)
    private let frames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?

    private let spriteSize = CGSize(width: 128, height: 160)
    private let bubbleSize = CGSize(width: 150, height: 64)
    private let spriteOrigin = CGPoint(x: 12, y: 12)
    private let bubbleOffset = CGPoint(x: 116, y: 118)

    init(frame frameRect: NSRect, frames: [NSImage]) {
        self.frames = frames
        self.imageView = NSImageView(frame: CGRect(origin: .zero, size: self.spriteSize))
        super.init(frame: frameRect)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        self.imageView.image = frames.first
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.animates = false
        self.imageView.wantsLayer = true
        self.addSubview(self.imageView)
        self.addSubview(self.speechBubbleView)
        self.startFrameAnimation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.imageView.frame = CGRect(origin: self.spriteOrigin, size: self.spriteSize)
        self.speechBubbleView.frame = CGRect(
            origin: CGPoint(
                x: self.spriteOrigin.x + self.bubbleOffset.x,
                y: self.spriteOrigin.y + self.bubbleOffset.y),
            size: self.bubbleSize)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            self.stopFrameAnimation()
        }
    }

    private func startFrameAnimation() {
        guard self.frames.count > 1 else { return }
        self.stopFrameAnimation()
        self.animationTimer = Timer.scheduledTimer(
            timeInterval: 0.12,
            target: self,
            selector: #selector(handleAnimationTick),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(self.animationTimer!, forMode: .common)
    }

    private func stopFrameAnimation() {
        self.animationTimer?.invalidate()
        self.animationTimer = nil
    }

    @objc
    private func handleAnimationTick() {
        self.advanceFrame()
    }

    private func advanceFrame() {
        self.frameIndex = (self.frameIndex + 1) % self.frames.count
        self.imageView.image = self.frames[self.frameIndex]
    }
}

@MainActor
private final class RalphSpeechBubbleView: NSView {
    private let textField: NSTextField = {
        let field = NSTextField(labelWithString: "Ralph says hello")
        field.alignment = .center
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        field.textColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        field.backgroundColor = .clear
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 2
        return field
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.white.cgColor
        self.layer?.cornerRadius = 18
        self.layer?.borderWidth = 2
        self.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        self.layer?.shadowColor = NSColor.black.cgColor
        self.layer?.shadowOpacity = 0.16
        self.layer?.shadowRadius = 10
        self.layer?.shadowOffset = CGSize(width: 0, height: -2)
        self.addSubview(self.textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.textField.frame = self.bounds.insetBy(dx: 16, dy: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: 18, y: 12))
        tail.line(to: CGPoint(x: 32, y: 6))
        tail.line(to: CGPoint(x: 28, y: 22))
        tail.close()

        NSColor.white.setFill()
        tail.fill()

        NSColor.black.withAlphaComponent(0.12).setStroke()
        tail.lineWidth = 2
        tail.stroke()
    }
}
