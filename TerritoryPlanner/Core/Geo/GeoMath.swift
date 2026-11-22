import Foundation
import CoreLocation
import MapKit

/// Geodesic helpers. All distances are in meters, bearings in degrees clockwise from true north.
enum GeoMath {
    /// Mean Earth radius (IUGG), meters.
    static let earthRadius: Double = 6_371_008.8

    @inline(__always) static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    @inline(__always) static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Great-circle distance using the haversine formula.
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLat = radians(b.latitude - a.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let value = degrees(atan2(y, x))
        return (value + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Point reached by travelling `distance` meters from `origin` along `bearing`.
    static func destination(from origin: CLLocationCoordinate2D, distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let angular = distance / earthRadius
        let theta = radians(bearing)
        let lat1 = radians(origin.latitude)
        let lon1 = radians(origin.longitude)
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: degrees(lat2), longitude: normalizeLongitude(degrees(lon2)))
    }

    /// Wraps longitude into [-180, 180).
    static func normalizeLongitude(_ longitude: Double) -> Double {
        var value = (longitude + 180).truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value - 180
    }

    /// Linear interpolation between two nearby coordinates. Handles the antimeridian.
    /// For segments of a few kilometres the error versus a true geodesic is negligible.
    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, fraction t: Double) -> CLLocationCoordinate2D {
        var dLon = b.longitude - a.longitude
        if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: normalizeLongitude(a.longitude + dLon * t)
        )
    }

    static func pathLength(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<coordinates.count {
            total += distance(coordinates[index - 1], coordinates[index])
        }
        return total
    }

    /// `result[i]` is the path length from the first coordinate to coordinate `i`.
    static func cumulativeDistances(_ coordinates: [CLLocationCoordinate2D]) -> [Double] {
        guard !coordinates.isEmpty else { return [] }
        var result = [0.0]
        result.reserveCapacity(coordinates.count)
        var index = 1
        while index < coordinates.count {
            result.append(result[index - 1] + distance(coordinates[index - 1], coordinates[index]))
            index += 1
        }
        return result
    }

    static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite && CLLocationCoordinate2DIsValid(coordinate)
    }

    static func isApproximatelyEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, tolerance: Double = 0.5) -> Bool {
        distance(a, b) <= tolerance
    }

    /// Center of the bounding box and the radius of a circle that contains every coordinate.
    static func enclosingCircle(for coordinates: [CLLocationCoordinate2D]) -> (center: CLLocationCoordinate2D, radius: Double)? {
        guard let region = boundingRegion(for: coordinates, paddingFactor: 1) else { return nil }
        let center = region.center
        let radius = coordinates.map { distance(center, $0) }.max() ?? 0
        return (center, radius)
    }

    /// Region that fits all coordinates with some padding. Returns nil for an empty input.
    static func boundingRegion(for coordinates: [CLLocationCoordinate2D], paddingFactor: Double = 1.35, minimumSpan: Double = 0.003) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: min(170, max(minimumSpan, (maxLat - minLat) * paddingFactor)),
            longitudeDelta: min(350, max(minimumSpan, (maxLon - minLon) * paddingFactor))
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Region that shows a circle of `radius` meters around `center`.
    static func region(center: CLLocationCoordinate2D, radius: Double, paddingFactor: Double = 2.6) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, latitudinalMeters: radius * paddingFactor, longitudinalMeters: radius * paddingFactor)
    }
}

/// Equirectangular projection around an origin: (x = east, y = north) in meters.
/// Accurate to well under 1% for areas of a few tens of kilometres, which covers every
/// area this app works with. Generators work in this plane and convert back to coordinates.
struct LocalProjection {
    let origin: CLLocationCoordinate2D
    private let metersPerDegreeLatitude: Double
    private let metersPerDegreeLongitude: Double

    init(origin: CLLocationCoordinate2D) {
        self.origin = origin
        metersPerDegreeLatitude = GeoMath.radians(1) * GeoMath.earthRadius
        metersPerDegreeLongitude = GeoMath.radians(1) * GeoMath.earthRadius * max(cos(GeoMath.radians(origin.latitude)), 1e-6)
    }

    func project(_ coordinate: CLLocationCoordinate2D) -> SIMD2<Double> {
        var dLon = coordinate.longitude - origin.longitude
        if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
        return SIMD2(dLon * metersPerDegreeLongitude, (coordinate.latitude - origin.latitude) * metersPerDegreeLatitude)
    }

    func unproject(_ point: SIMD2<Double>) -> CLLocationCoordinate2D {
        let latitude = min(89.999, max(-89.999, origin.latitude + point.y / metersPerDegreeLatitude))
        let longitude = GeoMath.normalizeLongitude(origin.longitude + point.x / metersPerDegreeLongitude)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }

    /// Rotates clockwise by `degrees` (compass convention: x = east, y = north).
    func rotatedClockwise(by degrees: Double) -> SIMD2<Double> {
        let a = GeoMath.radians(degrees)
        let c = cos(a), s = sin(a)
        return SIMD2(x * c + y * s, -x * s + y * c)
    }

    var angle: Double { atan2(y, x) }
}
