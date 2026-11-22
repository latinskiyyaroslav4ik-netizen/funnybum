import Foundation
import CoreLocation

enum RouteGenerationError: LocalizedError, Equatable {
    case missingAreaCenter
    case notEnoughCustomPoints
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingAreaCenter: "Не выбран центр области. Коснитесь карты в режиме «Центр»."
        case .notEnoughCustomPoints: "Для своего маршрута нужно минимум две точки. Поставьте их на карте в режиме «Точки»."
        case .emptyResult: "В области не поместилось ни одной точки. Уменьшите шаг или увеличьте радиус."
        }
    }
}

struct GenerationResult {
    var route: Route
    /// Spacing actually used (may be larger than requested if the point limit forced it).
    var effectiveSpacing: Double
    var notes: [String]
}

/// Pure, deterministic route generator. Patterns are built in a local metric plane centred
/// on the area centre (x = east, y = north), transformed (orientation, mirroring, rotation,
/// start alignment) and only then converted to geographic coordinates.
struct RouteGenerator {

    func generate(
        settings rawSettings: RouteSettings,
        center: CLLocationCoordinate2D?,
        start: CLLocationCoordinate2D?,
        customPoints: [RoutePoint]
    ) throws -> GenerationResult {
        let settings = rawSettings.validated()

        if settings.pattern == .custom {
            return try generateCustom(settings: settings, customPoints: customPoints)
        }

        guard let center else { throw RouteGenerationError.missingAreaCenter }
        let projection = LocalProjection(origin: center)
        let startLocal = start.map { projection.project($0) }

        var notes: [String] = []
        var spacing = settings.spacing
        var local = buildPattern(settings: settings, spacing: spacing, startLocal: startLocal)

        // Respect the point budget. Point count scales roughly with (R / s)^2 for every
        // area-filling pattern, so widening the spacing by sqrt(ratio) converges in 1–3 passes.
        if local.count > settings.maxPoints {
            if settings.autoFitSpacing {
                var iterations = 0
                while local.count > settings.maxPoints && iterations < 16 {
                    let ratio = Double(local.count) / Double(settings.maxPoints)
                    spacing *= max(ratio.squareRoot() * 1.02, 1.03)
                    local = buildPattern(settings: settings, spacing: spacing, startLocal: startLocal)
                    iterations += 1
                }
                notes.append("Шаг увеличен до \(Formatters.distance(spacing)), чтобы уложиться в лимит \(settings.maxPoints) точек.")
            }
            if local.count > settings.maxPoints {
                local = Array(local.prefix(settings.maxPoints))
                notes.append("Маршрут обрезан до \(settings.maxPoints) точек — часть области не покрыта.")
            }
        }

        guard !local.isEmpty else { throw RouteGenerationError.emptyResult }

        var points = local.map { RoutePoint(coordinate: projection.unproject($0), pause: settings.pauseAtPoint) }

        // Approach leg from an explicit start point that is not already on the pattern.
        if let start, let first = points.first, GeoMath.distance(start, first.coordinate) > spacing / 2 {
            points.insert(RoutePoint(coordinate: start, pause: 0, name: "Старт"), at: 0)
            notes.append("Добавлен подход от стартовой точки (\(Formatters.distance(GeoMath.distance(start, first.coordinate)))).")
        }

        let route = Route(
            name: "\(settings.pattern.title) · \(Formatters.distance(settings.areaRadius))",
            pattern: settings.pattern,
            source: .generated,
            points: points
        )
        return GenerationResult(route: route, effectiveSpacing: spacing, notes: notes)
    }

    // MARK: - Custom

    private func generateCustom(settings: RouteSettings, customPoints: [RoutePoint]) throws -> GenerationResult {
        guard customPoints.count >= 2 else { throw RouteGenerationError.notEnoughCustomPoints }
        var anchors = customPoints
        for index in anchors.indices where anchors[index].pause == 0 {
            anchors[index].pause = settings.pauseAtPoint
        }
        if settings.reversed { anchors.reverse() }

        var notes: [String] = []
        var points = anchors
        if settings.densifyCustom {
            points = Self.densify(anchors, maxSpacing: settings.spacing)
            if points.count > anchors.count {
                notes.append("Добавлено \(points.count - anchors.count) промежуточных точек с шагом ≤ \(Formatters.distance(settings.spacing)).")
            }
        }
        if points.count > settings.maxPoints {
            points = Array(points.prefix(settings.maxPoints))
            notes.append("Маршрут обрезан до лимита \(settings.maxPoints) точек.")
        }
        let route = Route(name: "Свой маршрут · \(anchors.count) опорных", pattern: .custom, source: .custom, points: points)
        return GenerationResult(route: route, effectiveSpacing: settings.spacing, notes: notes)
    }

    /// Inserts interpolated points so that no leg exceeds `maxSpacing` meters.
    static func densify(_ points: [RoutePoint], maxSpacing: Double) -> [RoutePoint] {
        guard points.count > 1, maxSpacing > 0 else { return points }
        var result: [RoutePoint] = [points[0]]
        for index in 1..<points.count {
            let a = points[index - 1].coordinate
            let b = points[index].coordinate
            let d = GeoMath.distance(a, b)
            if d > maxSpacing {
                let segments = Int((d / maxSpacing).rounded(.up))
                for k in 1..<segments {
                    result.append(RoutePoint(coordinate: GeoMath.interpolate(a, b, fraction: Double(k) / Double(segments))))
                }
            }
            result.append(points[index])
        }
        return result
    }

    // MARK: - Pattern construction (local plane)

    private func buildPattern(settings: RouteSettings, spacing: Double, startLocal: SIMD2<Double>?) -> [SIMD2<Double>] {
        let radius = settings.areaRadius
        switch settings.pattern {
        case .grid, .snake:
            var base = lattice(radius: radius, spacing: spacing, clip: settings.clipToCircle, serpentine: settings.pattern == .snake)
            if settings.orientation == .vertical {
                base = base.map { $0.rotatedClockwise(by: 90) }
            }
            if settings.reversed { base.reverse() }
            // The lattice is symmetric about both axes, so mirroring yields equally valid
            // routes. Pick the mirror whose first point is closest to the requested start.
            var candidates: [[SIMD2<Double>]] = [
                base,
                base.map { SIMD2(-$0.x, $0.y) },
                base.map { SIMD2($0.x, -$0.y) },
                base.map { SIMD2(-$0.x, -$0.y) }
            ]
            candidates = candidates.map { $0.map { $0.rotatedClockwise(by: settings.rotation) } }
            guard let startLocal else { return candidates[0] }
            return candidates.min { lhs, rhs in
                distanceToFirst(lhs, startLocal) < distanceToFirst(rhs, startLocal)
            } ?? candidates[0]

        case .spiral:
            var points = spiral(radius: radius, spacing: spacing)
            if settings.turnDirection == .clockwise { points = points.map { SIMD2($0.x, -$0.y) } }
            if settings.reversed { points.reverse() }
            points = points.map { $0.rotatedClockwise(by: settings.rotation) }
            return alignRotation(points, toward: startLocal)

        case .circular:
            var points = rings(radius: radius, spacing: spacing, outward: settings.reversed)
            if settings.turnDirection == .clockwise { points = points.map { SIMD2($0.x, -$0.y) } }
            points = points.map { $0.rotatedClockwise(by: settings.rotation) }
            return alignRotation(points, toward: startLocal)

        case .custom:
            return []
        }
    }

    private func distanceToFirst(_ points: [SIMD2<Double>], _ target: SIMD2<Double>) -> Double {
        guard let first = points.first else { return .infinity }
        return (first - target).length
    }

    /// Rows of a square lattice centred on the origin, top row first, west → east.
    private func lattice(radius: Double, spacing: Double, clip: Bool, serpentine: Bool) -> [SIMD2<Double>] {
        let n = Int((radius / spacing).rounded(.down))
        guard n >= 0 else { return [] }
        let tolerance = spacing * 1e-6
        var result: [SIMD2<Double>] = []
        var rowIndex = 0
        for j in stride(from: n, through: -n, by: -1) {
            let y = Double(j) * spacing
            var row: [SIMD2<Double>] = []
            for i in -n...n {
                let p = SIMD2(Double(i) * spacing, y)
                if !clip || p.length <= radius + tolerance { row.append(p) }
            }
            guard !row.isEmpty else { continue }
            if serpentine && rowIndex % 2 == 1 { row.reverse() }
            result.append(contentsOf: row)
            rowIndex += 1
        }
        return result
    }

    /// Archimedean spiral r = bθ with b = spacing / 2π, so neighbouring turns are exactly
    /// `spacing` apart. Points are placed at (approximately) equal arc length `spacing`,
    /// using ds = sqrt(r² + b²) dθ.
    private func spiral(radius: Double, spacing: Double) -> [SIMD2<Double>] {
        let b = spacing / (2 * .pi)
        var result: [SIMD2<Double>] = [SIMD2(0, 0)]
        var theta = 0.0
        // Hard cap protects against pathological inputs; real routes stay far below it.
        while result.count < 200_000 {
            let r = b * theta
            theta += spacing / (r * r + b * b).squareRoot()
            let newRadius = b * theta
            if newRadius > radius { break }
            result.append(SIMD2(newRadius * cos(theta), newRadius * sin(theta)))
        }
        return result
    }

    /// Concentric rings from the outer edge inward (or reversed), counter-clockwise, plus the centre.
    private func rings(radius: Double, spacing: Double, outward: Bool) -> [SIMD2<Double>] {
        var radii: [Double] = []
        var r = radius
        while r >= spacing / 2 {
            radii.append(r)
            r -= spacing
        }
        if outward { radii.reverse() }

        var result: [SIMD2<Double>] = []
        if outward { result.append(SIMD2(0, 0)) }
        for ringRadius in radii {
            let count = max(6, Int((2 * .pi * ringRadius / spacing).rounded(.up)))
            for k in 0..<count {
                let angle = 2 * .pi * Double(k) / Double(count)
                result.append(SIMD2(ringRadius * cos(angle), ringRadius * sin(angle)))
            }
        }
        if !outward { result.append(SIMD2(0, 0)) }
        return result
    }

    /// Rotates a rotationally-symmetric pattern so its first off-centre point faces the start.
    private func alignRotation(_ points: [SIMD2<Double>], toward start: SIMD2<Double>?) -> [SIMD2<Double>] {
        guard let start, start.length > 1, let anchor = points.first(where: { $0.length > 1 }) else { return points }
        // Only align when the route actually begins on the outer part (not at the centre).
        guard let first = points.first, first.length > 1 else { return points }
        let delta = anchor.angle - start.angle
        let c = cos(-delta), s = sin(-delta)
        return points.map { SIMD2($0.x * c - $0.y * s, $0.x * s + $0.y * c) }
    }
}
