import AppKit
import Foundation

@MainActor
final class RalphSpriteView: NSView {
    private static let spriteSize = CGSize(width: 128, height: 160)
    private static let bubbleMessage = "Ralph is here"
    private static let bubbleOrigin = CGPoint(x: spriteSize.width + 22, y: 2)
    private static let trailingPadding: CGFloat = 8
    static let contentSize = CGSize(
        width: bubbleOrigin.x + RalphSpeechBubbleView.preferredSize(for: bubbleMessage).width + trailingPadding,
        height: max(spriteSize.height, bubbleOrigin.y + RalphSpeechBubbleView.preferredSize(for: bubbleMessage).height))
    private let imageView: NSImageView
    private let bubbleView: RalphSpeechBubbleView
    private let animationSet: RalphSpriteAnimationSet
    private var currentAnimation: RalphSpriteAnimation?
    private var currentIdleDirection: RalphSpriteMovementDirection = .down
    private var frameIndex = 0
    private var animationTimer: Timer?

    init(frame frameRect: NSRect, animations: RalphSpriteAnimationSet) {
        self.animationSet = animations
        self.imageView = NSImageView(frame: CGRect(origin: .zero, size: Self.spriteSize))
        self.bubbleView = RalphSpeechBubbleView(message: Self.bubbleMessage)
        super.init(frame: frameRect)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.animates = false
        self.addSubview(self.imageView)
        self.addSubview(self.bubbleView)
        self.showIdle(direction: .down)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.imageView.frame = CGRect(origin: .zero, size: Self.spriteSize)
        self.bubbleView.frame = CGRect(
            origin: Self.bubbleOrigin,
            size: RalphSpeechBubbleView.preferredSize(for: Self.bubbleMessage))
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            self.stopAnimation()
        }
    }

    func playWalk(direction: RalphSpriteMovementDirection) {
        self.currentIdleDirection = direction
        self.currentAnimation = self.animationSet.walkAnimation(for: direction)
        self.frameIndex = 0
        self.updateFrame()
        self.startAnimation()
    }

    func showIdle(direction: RalphSpriteMovementDirection) {
        self.currentIdleDirection = direction
        self.currentAnimation = nil
        self.stopAnimation()
        self.imageView.image = self.animationSet.idleFrame(for: direction).image
    }

    private func startAnimation() {
        guard let currentAnimation, currentAnimation.frames.count > 1 else { return }
        self.stopAnimation()
        self.animationTimer = Timer.scheduledTimer(
            timeInterval: currentAnimation.frameDuration,
            target: self,
            selector: #selector(handleAnimationTick),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(self.animationTimer!, forMode: .common)
    }

    private func stopAnimation() {
        self.animationTimer?.invalidate()
        self.animationTimer = nil
    }

    @objc
    private func handleAnimationTick() {
        self.advanceFrame()
    }

    private func advanceFrame() {
        guard let currentAnimation, !currentAnimation.frames.isEmpty else { return }
        self.frameIndex = (self.frameIndex + 1) % currentAnimation.frames.count
        self.updateFrame()
    }

    private func updateFrame() {
        guard let currentAnimation, !currentAnimation.frames.isEmpty else { return }
        self.imageView.image = currentAnimation.frames[self.frameIndex].image
    }
}
