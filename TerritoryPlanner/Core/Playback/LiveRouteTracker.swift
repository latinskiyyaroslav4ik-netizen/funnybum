import Foundation
import CoreLocation
import Observation

/// Tracks progress along a route from real Core Location fixes.
///
/// When the app runs under Xcode with an exported GPX selected in
/// Debug ▸ Simulate Location (or with `xcrun simctl location … start`), these fixes are
/// produced by Apple's own simulation tooling — this tracker is how the app verifies that
/// the system-level replay matches the plan.
@MainActor
@Observable
final class LiveRouteTracker {
    private(set) var state: PlaybackState = .idle
    private(set) var points: [RoutePoint] = []
    private(set) var reachedIndex: Int = -1
    private(set) var lastLocation: CLLocation?
    private(set) var distanceTravelled: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var observedSpeed: Double = 0

    /// A waypoint counts as reached within this distance, meters.
    var arrivalThreshold: Double = 20
    /// Fallback speed for ETA before a real speed is observed.
    var plannedSpeed: Double = 5

    @ObservationIgnored private var cumulative: [Double] = []
    @ObservationIgnored private var segmentStart: Date?

    var processedCount: Int { max(0, reachedIndex + 1) }
    var isActive: Bool { state == .running || state == .paused }

    var fraction: Double {
        guard !points.isEmpty else { return 0 }
        if state == .finished { return 1 }
        return Double(processedCount) / Double(points.count)
    }

    var remainingTime: TimeInterval {
        guard !points.isEmpty, state != .finished else { return 0 }
        let next = reachedIndex + 1
        guard points.indices.contains(next) else { return 0 }
        let toNext = lastLocation.map { GeoMath.distance($0.coordinate, points[next].coordinate) } ?? 0
        let after = (cumulative.last ?? 0) - cumulative[next]
        let pauses = points[next...].reduce(0) { $0 + $1.pause }
        let speed = observedSpeed > 0.3 ? observedSpeed : max(plannedSpeed, 0.1)
        return (toNext + after) / speed + pauses
    }

    func load(_ newPoints: [RoutePoint]) {
        points = newPoints
        cumulative = GeoMath.cumulativeDistances(newPoints.map(\.coordinate))
        reset()
    }

    func start() {
        guard !points.isEmpty else { return }
        reset()
        state = .running
        segmentStart = Date()
    }

    func pause() {
        guard state == .running else { return }
        accumulateTime()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        segmentStart = Date()
        // A gap in fixes while paused must not count as travelled distance.
        lastLocation = nil
    }

    func stop() {
        reset()
    }

    /// Feeds a fix. Returns indices of waypoints reached by this fix.
    @discardableResult
    func ingest(_ location: CLLocation) -> [Int] {
        guard state == .running, location.horizontalAccuracy >= 0 else { return [] }
        if let last = lastLocation {
            distanceTravelled += location.distance(from: last)
        }
        if location.speed >= 0 { observedSpeed = location.speed }
        lastLocation = location
        accumulateTime()
        segmentStart = Date()

        // Look ahead a few waypoints so a fix that skips one (fast replay, sparse fixes)
        // does not stall progress forever.
        var reached: [Int] = []
        let lookahead = 4
        let first = reachedIndex + 1
        let last = min(points.count, first + lookahead)
        if first < last {
            var best: Int?
            for index in first..<last where GeoMath.distance(location.coordinate, points[index].coordinate) <= arrivalThreshold {
                best = index
            }
            if let best {
                reached = Array(first...best)
                reachedIndex = best
            }
        }
        if reachedIndex == points.count - 1 {
            state = .finished
        }
        return reached
    }

    private func accumulateTime() {
        if let segmentStart {
            elapsed += Date().timeIntervalSince(segmentStart)
        }
        segmentStart = nil
    }

    private func reset() {
        state = .idle
        reachedIndex = -1
        lastLocation = nil
        distanceTravelled = 0
        elapsed = 0
        observedSpeed = 0
        segmentStart = nil
    }
}
