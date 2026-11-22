import Foundation

enum RoutePattern: String, CaseIterable, Codable, Identifiable {
    case grid, spiral, snake, circular, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Сетка"
        case .spiral: "Спираль"
        case .snake: "Змейка"
        case .circular: "Кольца"
        case .custom: "Свой"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.3x3"
        case .spiral: "hurricane"
        case .snake: "arrow.triangle.swap"
        case .circular: "circle.circle"
        case .custom: "scribble.variable"
        }
    }

    var summary: String {
        switch self {
        case .grid: "Построчный обход решётки. Каждый ряд проходится в одном направлении."
        case .spiral: "Архимедова спираль от центра наружу с постоянным шагом витков."
        case .snake: "Бустрофедон: ряды проходятся поочерёдно туда и обратно, без холостых возвратов."
        case .circular: "Концентрические кольца с переходом между ними."
        case .custom: "Точки, которые вы ставите на карте. Отрезки можно уплотнить до заданного шага."
        }
    }
}

enum TurnDirection: String, CaseIterable, Codable, Identifiable {
    case clockwise, counterClockwise
    var id: String { rawValue }
    var title: String { self == .clockwise ? "По часовой" : "Против часовой" }
}

enum SweepOrientation: String, CaseIterable, Codable, Identifiable {
    case horizontal, vertical
    var id: String { rawValue }
    var title: String { self == .horizontal ? "Горизонтально" : "Вертикально" }
}

/// Every user-tunable parameter of route generation and playback.
struct RouteSettings: Codable, Equatable {
    var pattern: RoutePattern = .snake
    /// Radius of the planning area, meters.
    var areaRadius: Double = 400
    /// Distance between neighbouring points / rows / rings, meters.
    var spacing: Double = 40
    /// Upper bound on the number of points in a generated route.
    var maxPoints: Int = 600
    /// When the point limit is exceeded, widen the spacing instead of truncating the route.
    var autoFitSpacing: Bool = true
    /// Playback speed, meters per second.
    var speed: Double = 5
    /// Dwell time at every waypoint, seconds.
    var pauseAtPoint: Double = 0
    var turnDirection: TurnDirection = .clockwise
    var orientation: SweepOrientation = .horizontal
    var reversed: Bool = false
    /// Clockwise rotation of the whole pattern, degrees.
    var rotation: Double = 0
    /// Drop grid/snake points outside the circular area.
    var clipToCircle: Bool = true
    /// Insert intermediate points on custom routes so no leg is longer than `spacing`.
    var densifyCustom: Bool = true
    /// Radius around the moving position that counts as covered, meters.
    var coverageRadius: Double = 25

    enum Limits {
        static let areaRadius: ClosedRange<Double> = 50...10_000
        static let spacing: ClosedRange<Double> = 5...1_000
        static let maxPoints: ClosedRange<Int> = 10...5_000
        static let speed: ClosedRange<Double> = 0.3...70
        static let pause: ClosedRange<Double> = 0...600
        static let rotation: ClosedRange<Double> = 0...359
        static let coverageRadius: ClosedRange<Double> = 5...500
    }

    /// Copy with every numeric value clamped into its valid range.
    func validated() -> RouteSettings {
        var s = self
        s.areaRadius = s.areaRadius.clamped(to: Limits.areaRadius)
        s.spacing = s.spacing.clamped(to: Limits.spacing)
        s.maxPoints = min(max(s.maxPoints, Limits.maxPoints.lowerBound), Limits.maxPoints.upperBound)
        s.speed = s.speed.clamped(to: Limits.speed)
        s.pauseAtPoint = s.pauseAtPoint.clamped(to: Limits.pause)
        s.rotation = s.rotation.clamped(to: Limits.rotation)
        s.coverageRadius = s.coverageRadius.clamped(to: Limits.coverageRadius)
        return s
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
