import Foundation

/// Everything needed to restore the planner after relaunch.
struct PlannerSession: Codable {
    var settings: RouteSettings
    var preferences: AppPreferences
    var areaCenter: CodableCoordinate?
    var startPoint: CodableCoordinate?
    var customPoints: [RoutePoint]
    var route: Route?
}

/// JSON persistence in Application Support. Writes are atomic.
struct SessionStore {
    private let fileURL: URL

    init(fileName: String = "planner-session.json") {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent(fileName)
    }

    func load() throws -> PlannerSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PlannerSession.self, from: data)
    }

    func save(_ session: PlannerSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
