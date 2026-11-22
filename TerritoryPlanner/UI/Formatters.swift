import Foundation
import CoreLocation

enum Formatters {
    static func distance(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        if meters < 1_000 { return "\(Int(meters.rounded())) м" }
        if meters < 100_000 { return String(format: "%.2f км", meters / 1_000) }
        return String(format: "%.0f км", meters / 1_000)
    }

    /// h:mm:ss or m:ss.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func speed(_ metersPerSecond: Double) -> String {
        String(format: "%.1f км/ч", metersPerSecond * 3.6)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", min(max(fraction, 0), 1) * 100)
    }

    static func coordinate(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", c.latitude, c.longitude)
    }

    static func area(_ squareMeters: Double) -> String {
        if squareMeters < 100_000 { return "\(Int(squareMeters.rounded())) м²" }
        return String(format: "%.2f км²", squareMeters / 1_000_000)
    }

    static let logTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return f
    }()
}
