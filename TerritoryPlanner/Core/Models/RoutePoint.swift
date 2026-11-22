import Foundation
import CoreLocation

/// A single waypoint of a route.
struct RoutePoint: Identifiable, Codable, Hashable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    /// Dwell time at this point during playback, seconds.
    var pause: TimeInterval
    var name: String?
    var elevation: Double?

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, pause: TimeInterval = 0, name: String? = nil, elevation: Double? = nil) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.pause = pause
        self.name = name
        self.elevation = elevation
    }

    var coordinate: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }
}

/// Codable wrapper, because `CLLocationCoordinate2D` is not Codable.
struct CodableCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
