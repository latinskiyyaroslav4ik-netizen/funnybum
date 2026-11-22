import Foundation
import CoreLocation

enum GPXError: LocalizedError {
    case unreadable(String)
    case malformedXML(line: Int, column: Int, reason: String)
    case notGPX(rootElement: String)
    case noPoints
    case invalidCoordinate(index: Int, lat: String?, lon: String?)

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason):
            "Не удалось прочитать файл: \(reason)"
        case .malformedXML(let line, let column, let reason):
            "Файл повреждён (строка \(line), позиция \(column)): \(reason)"
        case .notGPX(let root):
            "Это не GPX: корневой элемент <\(root)> вместо <gpx>."
        case .noPoints:
            "В файле нет ни одной точки (wpt / rtept / trkpt)."
        case .invalidCoordinate(let index, let lat, let lon):
            "Точка №\(index + 1) имеет некорректные координаты (lat=\(lat ?? "—"), lon=\(lon ?? "—"))."
        }
    }
}

struct GPXParseResult {
    var name: String?
    var points: [RoutePoint]
    var warnings: [String]
    /// Which GPX element type the points were taken from.
    var sourceKind: String
}

/// Streaming GPX 1.0/1.1 parser and validator.
///
/// Point priority: track points, then route points, then waypoints — a typical file
/// exported from a tracker has a track; files made for Xcode location simulation
/// contain only `<wpt>`. Consecutive identical coordinates with timestamps are collapsed
/// into a single point with a dwell `pause` (that is exactly how `GPXWriter` encodes pauses).
final class GPXParser: NSObject, XMLParserDelegate {

    private struct RawPoint {
        var lat: String?
        var lon: String?
        var elevation: String?
        var time: String?
        var name: String?
    }

    private var waypoints: [RawPoint] = []
    private var routePoints: [RawPoint] = []
    private var trackPoints: [RawPoint] = []
    private var current: RawPoint?
    private var currentKind: String?
    private var textBuffer = ""
    private var rootElement: String?
    private var documentName: String?
    private var elementStack: [String] = []

    static func parse(url: URL) throws -> GPXParseResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GPXError.unreadable(error.localizedDescription)
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> GPXParseResult {
        guard !data.isEmpty else { throw GPXError.unreadable("файл пуст") }
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        if !parser.parse() {
            let error = parser.parserError as NSError?
            throw GPXError.malformedXML(
                line: parser.lineNumber,
                column: parser.columnNumber,
                reason: error?.localizedDescription ?? "неизвестная ошибка XML"
            )
        }
        return try delegate.makeResult()
    }

    // MARK: Result assembly & validation

    private func makeResult() throws -> GPXParseResult {
        guard let root = rootElement else { throw GPXError.noPoints }
        guard root.lowercased() == "gpx" else { throw GPXError.notGPX(rootElement: root) }

        let raw: [RawPoint]
        let kind: String
        if !trackPoints.isEmpty {
            raw = trackPoints; kind = "trkpt"
        } else if !routePoints.isEmpty {
            raw = routePoints; kind = "rtept"
        } else {
            raw = waypoints; kind = "wpt"
        }
        guard !raw.isEmpty else { throw GPXError.noPoints }

        var warnings: [String] = []
        let ignoredKinds = [("trkpt", trackPoints.count), ("rtept", routePoints.count), ("wpt", waypoints.count)]
            .filter { $0.0 != kind && $0.1 > 0 }
        if !ignoredKinds.isEmpty {
            let list = ignoredKinds.map { "\($0.1) \($0.0)" }.joined(separator: ", ")
            warnings.append("Использованы точки <\(kind)>; пропущено: \(list).")
        }

        var points: [RoutePoint] = []
        var lastTime: Date?
        var missingTime = 0
        for (index, item) in raw.enumerated() {
            guard
                let latString = item.lat, let lonString = item.lon,
                let lat = Double(latString.trimmingCharacters(in: .whitespaces)),
                let lon = Double(lonString.trimmingCharacters(in: .whitespaces)),
                (-90...90).contains(lat), (-180...180).contains(lon)
            else {
                throw GPXError.invalidCoordinate(index: index, lat: item.lat, lon: item.lon)
            }
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let time = item.time.flatMap(Self.parseDate)
            if item.time == nil { missingTime += 1 }
            let elevation = item.elevation.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }

            // Collapse dwell encoded as a repeated coordinate.
            if let previous = points.last,
               GeoMath.isApproximatelyEqual(previous.coordinate, coordinate),
               let t0 = lastTime, let t1 = time, t1 > t0 {
                points[points.count - 1].pause += t1.timeIntervalSince(t0)
                lastTime = t1
                continue
            }
            if let previous = points.last, GeoMath.isApproximatelyEqual(previous.coordinate, coordinate) {
                // Exact duplicate without timing information carries no meaning for a route.
                continue
            }
            if let t0 = lastTime, let t1 = time, t1 < t0 {
                warnings.append("Нарушен порядок времени у точки №\(index + 1).")
            }
            points.append(RoutePoint(coordinate: coordinate, pause: 0, name: item.name, elevation: elevation))
            lastTime = time ?? lastTime
        }

        guard !points.isEmpty else { throw GPXError.noPoints }
        if missingTime > 0 && missingTime < raw.count {
            warnings.append("У \(missingTime) из \(raw.count) точек нет <time>.")
        }
        if points.count > 20_000 {
            warnings.append("Очень длинный маршрут (\(points.count) точек) — отрисовка может быть медленной.")
        }
        // Keep warnings readable.
        if warnings.count > 8 { warnings = Array(warnings.prefix(8)) + ["…и ещё \(warnings.count - 8) предупреждений."] }

        return GPXParseResult(name: documentName, points: points, warnings: warnings, sourceKind: kind)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return isoPlain.date(from: trimmed) ?? isoFractional.date(from: trimmed)
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if rootElement == nil { rootElement = elementName }
        elementStack.append(name)
        textBuffer = ""
        switch name {
        case "wpt", "rtept", "trkpt":
            current = RawPoint(lat: attributeDict["lat"], lon: attributeDict["lon"])
            currentKind = name
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !elementStack.isEmpty { elementStack.removeLast() }
            textBuffer = ""
        }

        if current != nil {
            switch name {
            case "ele": current?.elevation = text
            case "time": current?.time = text
            case "name": current?.name = text.isEmpty ? nil : text
            case "wpt", "rtept", "trkpt":
                if let point = current, name == currentKind {
                    switch name {
                    case "wpt": waypoints.append(point)
                    case "rtept": routePoints.append(point)
                    default: trackPoints.append(point)
                    }
                }
                current = nil
                currentKind = nil
            default:
                break
            }
            return
        }

        // Document / track / route name: the first <name> outside of a point.
        if name == "name", documentName == nil, !text.isEmpty {
            documentName = text
        }
    }
}
