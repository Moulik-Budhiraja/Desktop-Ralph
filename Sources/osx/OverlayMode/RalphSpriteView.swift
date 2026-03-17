import AppKit
import Foundation

@MainActor
final class RalphSpriteView: NSView {
    private static let spriteSize = CGSize(width: 128, height: 160)
    static let defaultBubbleMessage = "Ralph is here"
    private static let bubbleOrigin = CGPoint(x: spriteSize.width + 22, y: 2)
    private static let trailingPadding: CGFloat = 8
    private var bubbleMessage: String
    private let imageView: NSImageView
    private let bubbleView: RalphSpeechBubbleView
    private let animationSet: RalphSpriteAnimationSet
    private var currentAnimation: RalphSpriteAnimation?
    private var currentIdleDirection: RalphSpriteMovementDirection = .down
    private var animationCompletion: (() -> Void)?
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var idleContinuationWorkItem: DispatchWorkItem?

    static func contentSize(for message: String) -> CGSize {
        let bubbleSize = RalphSpeechBubbleView.preferredSize(for: message)
        return CGSize(
            width: bubbleOrigin.x + bubbleSize.width + trailingPadding,
            height: max(spriteSize.height, bubbleOrigin.y + bubbleSize.height))
    }

    init(frame frameRect: NSRect, animations: RalphSpriteAnimationSet, bubbleMessage: String = RalphSpriteView.defaultBubbleMessage) {
        self.animationSet = animations
        self.bubbleMessage = bubbleMessage
        self.imageView = NSImageView(frame: CGRect(origin: .zero, size: Self.spriteSize))
        self.bubbleView = RalphSpeechBubbleView(message: bubbleMessage)
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
            size: RalphSpeechBubbleView.preferredSize(for: self.bubbleMessage))
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            self.stopAnimation()
        }
    }

    func playWalk(direction: RalphSpriteMovementDirection) {
        self.currentIdleDirection = direction
        self.play(animation: self.animationSet.walkAnimation(for: direction))
    }

    func showIdle(direction: RalphSpriteMovementDirection) {
        self.currentIdleDirection = direction
        let idleAnimation = self.animationSet.idleAnimations(for: direction).randomElement()
            ?? self.animationSet.idleAnimation(for: direction)
        guard idleAnimation.frames.count > 1 else {
            self.play(animation: idleAnimation)
            self.scheduleIdleContinuation(direction: direction, after: 0.35)
            return
        }

        self.play(
            animation: RalphSpriteAnimation(
                frames: idleAnimation.frames,
                frameDuration: idleAnimation.frameDuration,
                repeats: false)
        ) { [weak self] in
            self?.showIdle(direction: direction)
        }
    }

    func playClick(direction: RalphSpriteMovementDirection) {
        self.currentIdleDirection = direction
        let clickAnimation = self.animationSet.clickAnimation(for: direction)
        self.play(animation: clickAnimation) { [weak self] in
            guard let self else { return }
            self.showIdle(direction: direction)
        }
    }

    func updateBubbleMessage(_ message: String) {
        guard self.bubbleMessage != message else { return }
        self.bubbleMessage = message
        self.bubbleView.updateMessage(message)
        self.needsLayout = true
        self.layoutSubtreeIfNeeded()
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
        self.idleContinuationWorkItem?.cancel()
        self.idleContinuationWorkItem = nil
        self.animationTimer?.invalidate()
        self.animationTimer = nil
        self.animationCompletion = nil
    }

    @objc
    private func handleAnimationTick() {
        self.advanceFrame()
    }

    private func advanceFrame() {
        guard let currentAnimation, !currentAnimation.frames.isEmpty else { return }
        let nextIndex = self.frameIndex + 1
        if nextIndex >= currentAnimation.frames.count {
            if currentAnimation.repeats {
                self.frameIndex = 0
            } else {
                let completion = self.animationCompletion
                self.stopAnimation()
                completion?()
                return
            }
        } else {
            self.frameIndex = nextIndex
        }
        self.updateFrame()
    }

    private func updateFrame() {
        guard let currentAnimation, !currentAnimation.frames.isEmpty else { return }
        self.imageView.image = currentAnimation.frames[self.frameIndex].image
    }

    private func play(animation: RalphSpriteAnimation, completion: (() -> Void)? = nil) {
        self.stopAnimation()
        self.currentAnimation = animation
        self.animationCompletion = completion
        self.frameIndex = 0
        self.updateFrame()
        self.startAnimation()

        if animation.frames.count <= 1, let completion {
            self.animationCompletion = nil
            completion()
        }
    }

    private func scheduleIdleContinuation(direction: RalphSpriteMovementDirection, after delay: TimeInterval) {
        self.idleContinuationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showIdle(direction: direction)
        }
        self.idleContinuationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
