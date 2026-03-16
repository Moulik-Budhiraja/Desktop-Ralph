import AppKit
import Foundation

struct LaunchSpriteAnimation {
    let frames: [NSImage]
    let frameDuration: TimeInterval
}

struct LaunchSpriteAnimationSet {
    let idleSpin: LaunchSpriteAnimation
    let walkLeft: LaunchSpriteAnimation
    let walkRight: LaunchSpriteAnimation
    let walkUp: LaunchSpriteAnimation
    let walkDown: LaunchSpriteAnimation
}
