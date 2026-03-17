import AppKit
import Foundation

enum RalphMotionAnimator {
    private static let frameStep: TimeInterval = 0.01

    @MainActor
    static func animate(
        from start: CGPoint,
        to end: CGPoint,
        desktopWidth: CGFloat,
        onStep: (CGPoint, CGFloat) -> Void)
    {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let profile = RalphMotionPlanner.makeProfile(distance: distance, desktopWidth: desktopWidth)

        guard profile.totalDuration > 0 else {
            onStep(end, 1)
            return
        }

        let startedAt = Date()
        let endDate = startedAt.addingTimeInterval(profile.totalDuration)

        while Date() < endDate {
            let elapsed = Date().timeIntervalSince(startedAt)
            let traveledDistance = RalphMotionPlanner.distanceTraveled(at: elapsed, profile: profile)
            let progress = min(1, traveledDistance / max(distance, 1))
            let point = RalphMotionPlanner.interpolate(from: start, to: end, progress: CGFloat(progress))
            onStep(point, progress)
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(Self.frameStep))
        }

        onStep(end, 1)
    }
}
