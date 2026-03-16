import AppKit
import Foundation

@MainActor
final class LaunchSpriteView: NSView {
    private let imageView: NSImageView
    private let frames: [NSImage]
    private var frameIndex = 0
    private var animationTimer: Timer?

    init(frame frameRect: NSRect, frames: [NSImage]) {
        self.frames = frames
        self.imageView = NSImageView(frame: frameRect)
        super.init(frame: frameRect)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        self.imageView.image = frames.first
        self.imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView.animates = false
        self.imageView.wantsLayer = true
        self.addSubview(self.imageView)
        self.startFrameAnimation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.imageView.frame = self.bounds
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
