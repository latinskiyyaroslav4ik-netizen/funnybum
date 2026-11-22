import Foundation
import CoreLocation

enum GPXExportFormat: String, CaseIterable, Identifiable {
    /// `<wpt>` elements with `<time>` — the format Xcode's "Simulate Location" replays.
    case xcodeWaypoints
    /// `<trk><trkseg><trkpt>` — interoperable with mapping/tracking tools.
    case track
    /// `<rte><rtept>` — a planned route without timing.
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xcodeWaypoints: "Xcode (wpt + time)"
        case .track: "Трек (trkpt)"
        case .route: "Маршрут (rtept)"
        }
    }
}

/// Serialises a route to GPX 1.1.
///
/// Xcode derives simulated speed from the time difference between consecutive waypoints,
/// so timestamps are computed from leg length / speed. A dwell at a point is encoded as a
/// second waypoint at the same coordinate with a later timestamp — the location then stays
/// still for that long during simulation. `GPXParser` decodes that back into `pause`.
enum GPXWriter {

    static func makeGPX(route: Route, speed: Double, format: GPXExportFormat, startDate: Date = Date()) -> String {
        let speed = max(speed, 0.1)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Territory Planner" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>\(escape(route.name))</name>
            <time>\(iso.string(from: startDate))</time>
          </metadata>

        """

        // Timeline: arrival time at each point, then departure after its pause.
        var time = startDate
        var timeline: [(arrive: Date, depart: Date)] = []
        timeline.reserveCapacity(route.points.count)
        for (index, point) in route.points.enumerated() {
            if index > 0 {
                let leg = GeoMath.distance(route.points[index - 1].coordinate, point.coordinate)
                time = time.addingTimeInterval(leg / speed)
            }
            let arrive = time
            time = time.addingTimeInterval(max(0, point.pause))
            timeline.append((arrive: arrive, depart: time))
        }

        switch format {
        case .xcodeWaypoints:
            for (index, point) in route.points.enumerated() {
                xml += element("wpt", point: point, index: index, time: iso.string(from: timeline[index].arrive), indent: "  ")
                if point.pause > 0 {
                    xml += element("wpt", point: point, index: index, time: iso.string(from: timeline[index].depart), indent: "  ")
                }
            }
        case .track:
            xml += "  <trk>\n    <name>\(escape(route.name))</name>\n    <trkseg>\n"
            for (index, point) in route.points.enumerated() {
                xml += element("trkpt", point: point, index: index, time: iso.string(from: timeline[index].arrive), indent: "      ")
                if point.pause > 0 {
                    xml += element("trkpt", point: point, index: index, time: iso.string(from: timeline[index].depart), indent: "      ")
                }
            }
            xml += "    </trkseg>\n  </trk>\n"
        case .route:
            xml += "  <rte>\n    <name>\(escape(route.name))</name>\n"
            for (index, point) in route.points.enumerated() {
                xml += element("rtept", point: point, index: index, time: nil, indent: "    ")
            }
            xml += "  </rte>\n"
        }

        xml += "</gpx>\n"
        return xml
    }

    private static func element(_ tag: String, point: RoutePoint, index: Int, time: String?, indent: String) -> String {
        var s = "\(indent)<\(tag) lat=\"\(format(point.latitude))\" lon=\"\(format(point.longitude))\">\n"
        if let elevation = point.elevation {
            s += "\(indent)  <ele>\(String(format: "%.1f", elevation))</ele>\n"
        }
        if let time {
            s += "\(indent)  <time>\(time)</time>\n"
        }
        s += "\(indent)  <name>\(escape(point.name ?? "P\(index + 1)"))</name>\n"
        s += "\(indent)</\(tag)>\n"
        return s
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}

/// Builds an `xcrun simctl location` command that replays the route in a booted iOS Simulator
/// (Xcode 14+). simctl interpolates between waypoints at the given speed. It has no notion of
/// dwell time, so pauses are only honoured by the GPX / Xcode path.
enum SimctlCommandBuilder {
    static func command(for route: Route, speed: Double, device: String = "booted", maxWaypoints: Int = 2_000) -> String {
        let points = route.points.count > maxWaypoints
            ? stride(from: 0, to: route.points.count, by: Int((Double(route.points.count) / Double(maxWaypoints)).rounded(.up))).map { route.points[$0] }
            : route.points
        let waypoints = points.map {
            String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude)
        }.joined(separator: " ")
        return "xcrun simctl location \(device) start --speed=\(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(speed, 0.1))) \(waypoints)"
    }

    static let clearCommand = "xcrun simctl location booted clear"
}
