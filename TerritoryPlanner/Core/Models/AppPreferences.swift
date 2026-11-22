import Foundation
import MapKit
import SwiftUI

enum MapAppearance: String, CaseIterable, Codable, Identifiable {
    case standard, muted, hybrid, imagery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Стандарт"
        case .muted: "Приглушённая"
        case .hybrid: "Гибрид"
        case .imagery: "Спутник"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic)
        case .muted: .standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        }
    }
}

/// Where positions for coverage/progress come from.
enum LocationSource: String, CaseIterable, Codable, Identifiable {
    /// The in-app playback engine moves a virtual marker along the route.
    case simulation
    /// Core Location updates. Under Xcode these come from Debug ▸ Simulate Location (GPX)
    /// or `xcrun simctl location`, which is how the exported route is replayed system-wide.
    case device

    var id: String { rawValue }

    var title: String { self == .simulation ? "Встроенная симуляция" : "Core Location" }

    var subtitle: String {
        switch self {
        case .simulation: "Маркер движется по маршруту внутри приложения"
        case .device: "Позиции от системы: Xcode Simulate Location / simctl / GPS"
        }
    }
}

struct AppPreferences: Codable, Equatable {
    var mapAppearance: MapAppearance = .muted
    var showWaypoints: Bool = true
    var showCoverage: Bool = true
    var followMarker: Bool = false
    var keepScreenAwake: Bool = true
    var haptics: Bool = true
    var autoRegenerate: Bool = true
    var locationSource: LocationSource = .simulation
    /// Playback time multiplier for the built-in simulation.
    var timeScale: Double = 1

    static let timeScales: [Double] = [0.5, 1, 2, 5, 10, 25, 50]
}
