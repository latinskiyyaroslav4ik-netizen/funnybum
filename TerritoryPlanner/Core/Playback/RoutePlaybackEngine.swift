import Foundation
import CoreLocation
import Observation

enum PlaybackState: Equatable {
    case idle, running, paused, finished

    var title: String {
        switch self {
        case .idle: "Готов"
        case .running: "Выполняется"
        case .paused: "Пауза"
        case .finished: "Завершён"
        }
    }
}

enum PlaybackEvent {
    case started(pointCount: Int)
    case paused(atIndex: Int)
    case resumed
    case stopped(processed: Int)
    case finished(distance: Double, elapsed: TimeInterval)
    case reached(index: Int)
    case dwelling(index: Int, seconds: TimeInterval)
    case jumped(index: Int)
}

/// Moves a virtual position along a route in simulated time.
///
/// The engine is a fixed-tick integrator: every tick it advances simulated time by
/// `wallClockDelta × timeScale` and consumes that time first on the current dwell, then on
/// travel toward the next waypoint at `speed`. A single tick can cross several waypoints when
/// running fast, so arrival events are never skipped.
@MainActor
@Observable
final class RoutePlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var points: [RoutePoint] = []
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    /// Index of the last waypoint reached, -1 before start.
    private(set) var reachedIndex: Int = -1
    private(set) var distanceTravelled: Double = 0
    /// Simulated seconds since start (includes pauses at points, excludes user pause).
    private(set) var elapsed: TimeInterval = 0
    private(set) var dwellRemaining: TimeInterval = 0
    private(set) var totalDistance: Double = 0

    /// Meters per second.
    var speed: Double = 5
    /// Simulation speed multiplier.
    var timeScale: Double = 1

    @ObservationIgnored var onPosition: ((CLLocationCoordinate2D) -> Void)?
    @ObservationIgnored var onEvent: ((PlaybackEvent) -> Void)?

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var cumulative: [Double] = []
    /// suffixPause[i] = sum of pauses of points i..<count.
    @ObservationIgnored private var suffixPause: [Double] = []
    @ObservationIgnored private var nextIndex: Int = 0

    private let tick: Duration = .milliseconds(66)

    // MARK: Derived values

    var isActive: Bool { state == .running || state == .paused }
    var processedCount: Int { max(0, reachedIndex + 1) }
    private var effectiveSpeed: Double { max(speed, 0.1) }

    var fraction: Double {
        if state == .finished { return 1 }
        if totalDistance > 0 { return min(1, distanceTravelled / totalDistance) }
        return points.isEmpty ? 0 : Double(processedCount) / Double(points.count)
    }

    /// Remaining simulated seconds to the end of the route.
    var remainingSimulatedTime: TimeInterval {
        guard !points.isEmpty, state != .finished else { return 0 }
        let distanceLeft = max(0, totalDistance - distanceTravelled)
        let pausesLeft = nextIndex < suffixPause.count ? suffixPause[nextIndex] : 0
        return distanceLeft / effectiveSpeed + dwellRemaining + pausesLeft
    }

    /// Remaining wall-clock seconds at the current time scale.
    var remainingWallTime: TimeInterval { remainingSimulatedTime / max(timeScale, 0.01) }

    // MARK: Control

    func load(_ newPoints: [RoutePoint]) {
        cancelLoop()
        points = newPoints
        let coordinates = newPoints.map(\.coordinate)
        cumulative = GeoMath.cumulativeDistances(coordinates)
        totalDistance = cumulative.last ?? 0
        var sums = [Double](repeating: 0, count: newPoints.count + 1)
        for index in stride(from: newPoints.count - 1, through: 0, by: -1) {
            sums[index] = sums[index + 1] + max(0, newPoints[index].pause)
        }
        suffixPause = sums
        resetProgress()
        state = .idle
    }

    func start() {
        guard !points.isEmpty else { return }
        cancelLoop()
        resetProgress()
        state = .running
        onEvent?(.started(pointCount: points.count))
        arrive(at: 0)
        if state == .running { launchLoop() }
    }

    func pause() {
        guard state == .running else { return }
        cancelLoop()
        state = .paused
        onEvent?(.paused(atIndex: reachedIndex))
    }

    func resume() {
        guard state == .paused else { return }
        if nextIndex >= points.count && dwellRemaining <= 0 {
            finish()
            return
        }
        state = .running
        onEvent?(.resumed)
        launchLoop()
    }

    func stop() {
        let wasActive = state != .idle
        let processed = processedCount
        cancelLoop()
        resetProgress()
        state = .idle
        if wasActive { onEvent?(.stopped(processed: processed)) }
    }

    /// Step-by-step: jump to the next waypoint and hold there.
    func stepForward() {
        guard !points.isEmpty else { return }
        if state == .idle || state == .finished {
            resetProgress()
            jump(to: 0)
            return
        }
        guard nextIndex < points.count else {
            finish()
            return
        }
        jump(to: nextIndex)
    }

    /// Step-by-step: go back to the previous waypoint and hold there.
    func stepBackward() {
        guard !points.isEmpty, reachedIndex > 0 else { return }
        jump(to: reachedIndex - 1)
    }

    /// Moves the position exactly onto waypoint `index` and pauses playback there.
    func jump(to index: Int) {
        guard points.indices.contains(index) else { return }
        cancelLoop()
        let point = points[index]
        currentCoordinate = point.coordinate
        reachedIndex = index
        nextIndex = index + 1
        dwellRemaining = 0
        distanceTravelled = cumulative.indices.contains(index) ? cumulative[index] : 0
        onPosition?(point.coordinate)
        onEvent?(.jumped(index: index))
        if index == points.count - 1 {
            finish()
        } else {
            state = .paused
        }
    }

    // MARK: Integration loop

    private func launchLoop() {
        cancelLoop()
        let tick = self.tick
        loopTask = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                if Task.isCancelled { return }
                guard let self else { return }
                let now = clock.now
                let wall = (now - last) / .seconds(1)
                last = now
                self.advance(by: wall * max(self.timeScale, 0.01))
                if self.state != .running { return }
            }
        }
    }

    private func cancelLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Consumes `seconds` of simulated time.
    private func advance(by seconds: TimeInterval) {
        guard state == .running, var position = currentCoordinate else { return }
        var remaining = seconds
        elapsed += seconds
        var moved = false

        while remaining > 1e-9 && state == .running {
            if dwellRemaining > 0 {
                let used = min(dwellRemaining, remaining)
                dwellRemaining -= used
                remaining -= used
                continue
            }
            guard nextIndex < points.count else {
                finish()
                break
            }
            let target = points[nextIndex].coordinate
            let legLeft = GeoMath.distance(position, target)
            let reach = effectiveSpeed * remaining
            if reach >= legLeft {
                remaining -= legLeft / effectiveSpeed
                position = target
                currentCoordinate = position
                moved = true
                arrive(at: nextIndex)
            } else {
                position = GeoMath.interpolate(position, target, fraction: reach / max(legLeft, 1e-9))
                // Keep distance exact relative to the waypoint table to avoid drift.
                let legStart = cumulative[nextIndex - 1]
                let legLength = cumulative[nextIndex] - legStart
                distanceTravelled = legStart + max(0, legLength - (legLeft - reach))
                remaining = 0
                moved = true
            }
        }

        if moved {
            currentCoordinate = position
            onPosition?(position)
        }
        // Finished exactly on the last waypoint after its dwell.
        if state == .running && nextIndex >= points.count && dwellRemaining <= 0 {
            finish()
        }
    }

    private func arrive(at index: Int) {
        let point = points[index]
        currentCoordinate = point.coordinate
        reachedIndex = index
        nextIndex = index + 1
        distanceTravelled = cumulative.indices.contains(index) ? cumulative[index] : distanceTravelled
        dwellRemaining = max(0, point.pause)
        onPosition?(point.coordinate)
        onEvent?(.reached(index: index))
        if dwellRemaining > 0 {
            onEvent?(.dwelling(index: index, seconds: dwellRemaining))
        } else if nextIndex >= points.count {
            finish()
        }
    }

    private func finish() {
        guard state != .finished else { return }
        cancelLoop()
        dwellRemaining = 0
        distanceTravelled = totalDistance
        if let last = points.last {
            currentCoordinate = last.coordinate
            reachedIndex = points.count - 1
            nextIndex = points.count
        }
        state = .finished
        onEvent?(.finished(distance: totalDistance, elapsed: elapsed))
    }

    private func resetProgress() {
        currentCoordinate = nil
        reachedIndex = -1
        nextIndex = 0
        distanceTravelled = 0
        elapsed = 0
        dwellRemaining = 0
    }
}
