import AppKit
import Foundation

@MainActor
final class LaunchSpriteView: NSView {
    private let imageView: NSImageView
    private let speechBubbleView = RalphSpeechBubbleView(frame: .zero)
    private let animationSet: LaunchSpriteAnimationSet
    private var currentAnimation: LaunchSpriteAnimation
    private var frameIndex = 0
    private var animationTimer: Timer?

    private let spriteSize = CGSize(width: 128, height: 160)
    private let bubbleSize = CGSize(width: 150, height: 64)
    private let spriteOrigin = CGPoint(x: 12, y: 12)
    private let bubbleOffset = CGPoint(x: 116, y: 118)

    init(frame frameRect: NSRect, animations: LaunchSpriteAnimationSet) {
        self.animationSet = animations
        self.currentAnimation = animations.idleSpin
        self.imageView = NSImageView(frame: CGRect(origin: .zero, size: self.spriteSize))
        super.init(frame: frameRect)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        self.imageView.image = self.currentAnimation.frames.first
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.animates = false
        self.imageView.wantsLayer = true
        self.addSubview(self.imageView)
        self.addSubview(self.speechBubbleView)
        self.startAnimationTimer()
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
            self.stopAnimationTimer()
        }
    }

    func playIdleSpin() {
        self.setAnimation(self.animationSet.idleSpin)
    }

    func playAnimation(forMovementFrom start: CGPoint, to end: CGPoint) {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y

        if abs(deltaX) > abs(deltaY) {
            self.setAnimation(deltaX >= 0 ? self.animationSet.walkRight : self.animationSet.walkLeft)
        } else {
            self.setAnimation(deltaY >= 0 ? self.animationSet.walkUp : self.animationSet.walkDown)
        }
    }

    private func setAnimation(_ animation: LaunchSpriteAnimation) {
        self.currentAnimation = animation
        self.frameIndex = 0
        self.imageView.image = animation.frames.first
        self.startAnimationTimer()
    }

    private func startAnimationTimer() {
        guard self.currentAnimation.frames.count > 1 else { return }
        self.stopAnimationTimer()
        self.animationTimer = Timer.scheduledTimer(
            timeInterval: self.currentAnimation.frameDuration,
            target: self,
            selector: #selector(handleAnimationTick),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(self.animationTimer!, forMode: .common)
    }

    private func stopAnimationTimer() {
        self.animationTimer?.invalidate()
        self.animationTimer = nil
    }

    @objc
    private func handleAnimationTick() {
        self.advanceFrame()
    }

    private func advanceFrame() {
        let frames = self.currentAnimation.frames
        guard !frames.isEmpty else { return }
        self.frameIndex = (self.frameIndex + 1) % frames.count
        self.imageView.image = frames[self.frameIndex]
    }
}

@MainActor
private final class RalphSpeechBubbleView: NSView {
    private let bubbleStrokeColor = NSColor.black.withAlphaComponent(0.12)
    private let bubbleFillColor = NSColor.white

    private let textField: NSTextField = {
        let field = NSTextField(labelWithString: "Ralph is here")
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
        self.layer?.backgroundColor = NSColor.clear.cgColor
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
        self.textField.frame = CGRect(
            x: 18,
            y: 18,
            width: self.bounds.width - 30,
            height: self.bounds.height - 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bubbleRect = CGRect(x: 10, y: 14, width: self.bounds.width - 14, height: self.bounds.height - 18)
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 18, yRadius: 18)

        self.bubbleFillColor.setFill()
        path.fill()

        self.bubbleStrokeColor.setStroke()
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.stroke()
    }
}
