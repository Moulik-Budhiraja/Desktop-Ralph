import AppKit
import Foundation

struct RalphMotionProfile {
    let totalDistance: CGFloat
    let maxSpeed: CGFloat
    let acceleration: CGFloat
    let accelerationTime: TimeInterval
    let cruiseTime: TimeInterval
    let decelerationTime: TimeInterval
    let accelerationDistance: CGFloat
    let cruiseDistance: CGFloat

    var totalDuration: TimeInterval {
        self.accelerationTime + self.cruiseTime + self.decelerationTime
    }
}

enum RalphMotionPlanner {
    private static let fullWidthTraversalDuration: TimeInterval = 8.0
    private static let accelerationFractionOfScreenWidth: CGFloat = 0.12

    static func makeProfile(distance: CGFloat, desktopWidth: CGFloat) -> RalphMotionProfile {
        let maxSpeed = max(1, desktopWidth / Self.fullWidthTraversalDuration)
        let accelerationDistance = max(24, desktopWidth * Self.accelerationFractionOfScreenWidth)
        let acceleration = max(1, (maxSpeed * maxSpeed) / (2 * accelerationDistance))
        let timeToMaxSpeed = maxSpeed / acceleration
        let distanceToMaxSpeed = 0.5 * acceleration * timeToMaxSpeed * timeToMaxSpeed

        if distance <= (distanceToMaxSpeed * 2) {
            let peakSpeed = sqrt(max(distance * acceleration, 0))
            let accelTime = peakSpeed / acceleration
            return RalphMotionProfile(
                totalDistance: distance,
                maxSpeed: peakSpeed,
                acceleration: acceleration,
                accelerationTime: accelTime,
                cruiseTime: 0,
                decelerationTime: accelTime,
                accelerationDistance: distance / 2,
                cruiseDistance: 0)
        }

        let cruiseDistance = distance - (distanceToMaxSpeed * 2)
        let cruiseTime = cruiseDistance / maxSpeed
        return RalphMotionProfile(
            totalDistance: distance,
            maxSpeed: maxSpeed,
            acceleration: acceleration,
            accelerationTime: timeToMaxSpeed,
            cruiseTime: cruiseTime,
            decelerationTime: timeToMaxSpeed,
            accelerationDistance: distanceToMaxSpeed,
            cruiseDistance: cruiseDistance)
    }

    static func distanceTraveled(at elapsed: TimeInterval, profile: RalphMotionProfile) -> CGFloat {
        if elapsed <= 0 {
            return 0
        }

        if elapsed < profile.accelerationTime {
            return 0.5 * profile.acceleration * elapsed * elapsed
        }

        let cruiseStart = profile.accelerationTime
        let cruiseEnd = cruiseStart + profile.cruiseTime
        if elapsed < cruiseEnd {
            let cruiseElapsed = elapsed - cruiseStart
            return profile.accelerationDistance + (profile.maxSpeed * cruiseElapsed)
        }

        let decelStartDistance = profile.accelerationDistance + profile.cruiseDistance
        let decelElapsed = min(elapsed - cruiseEnd, profile.decelerationTime)
        let decelDistance = (profile.maxSpeed * decelElapsed) - (0.5 * profile.acceleration * decelElapsed * decelElapsed)
        return min(profile.totalDistance, decelStartDistance + decelDistance)
    }

    static func interpolate(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + ((end.x - start.x) * progress),
            y: start.y + ((end.y - start.y) * progress))
    }
}
