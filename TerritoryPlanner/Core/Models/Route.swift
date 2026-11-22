import Foundation
import CoreLocation

enum RouteSource: String, Codable {
    case generated, custom, imported

    var title: String {
        switch self {
        case .generated: "Сгенерирован"
        case .custom: "Свой"
        case .imported: "Импорт GPX"
        }
    }
}

struct Route: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var pattern: RoutePattern
    var source: RouteSource
    var points: [RoutePoint]
    var createdAt: Date = Date()
    /// Set once the user edits the point list by hand; auto-regeneration then leaves the route alone.
    var isManuallyEdited: Bool = false

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
    var totalDistance: Double { GeoMath.pathLength(coordinates) }
    var totalPause: TimeInterval { points.reduce(0) { $0 + $1.pause } }

    func estimatedDuration(speed: Double) -> TimeInterval {
        totalDistance / max(speed, 0.1) + totalPause
    }
}
