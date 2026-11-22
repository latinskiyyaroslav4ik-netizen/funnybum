import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Observation
import UIKit
import os

enum MapTapMode: String, CaseIterable, Identifiable {
    case areaCenter, startPoint, customPoint, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .areaCenter: "Центр"
        case .startPoint: "Старт"
        case .customPoint: "Точки"
        case .none: "Обзор"
        }
    }

    var systemImage: String {
        switch self {
        case .areaCenter: "scope"
        case .startPoint: "flag.fill"
        case .customPoint: "mappin.and.ellipse"
        case .none: "hand.draw"
        }
    }

    var hint: String {
        switch self {
        case .areaCenter: "Коснитесь карты, чтобы задать центр области"
        case .startPoint: "Коснитесь карты, чтобы задать стартовую точку"
        case .customPoint: "Касайтесь карты, чтобы добавлять точки маршрута"
        case .none: "Карта только для просмотра"
        }
    }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case route, progress, points, logs, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .route: "Маршрут"
        case .progress: "Прогресс"
        case .points: "Точки"
        case .logs: "Журнал"
        case .settings: "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .route: "point.topleft.down.to.point.bottomright.curvepath"
        case .progress: "chart.pie.fill"
        case .points: "list.bullet"
        case .logs: "text.alignleft"
        case .settings: "gearshape.fill"
        }
    }
}

struct WaypointMarker: Identifiable {
    let id: UUID
    let index: Int
    let coordinate: CLLocationCoordinate2D
    let hasPause: Bool
    let isReached: Bool
    let isSelected: Bool
}

struct CoveragePolygon: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
}

/// Unified progress for whichever position source is active.
struct ProgressSnapshot {
    var state: PlaybackState
    var processed: Int
    var total: Int
    var routeFraction: Double
    var coverageFraction: Double
    var coveredArea: Double
    var distanceDone: Double
    var distanceTotal: Double
    var eta: TimeInterval?
    var elapsed: TimeInterval
    var speed: Double
}

@MainActor
@Observable
final class PlannerViewModel {
    // MARK: Planning state
    var settings = RouteSettings()
    var preferences = AppPreferences()
    var areaCenter: CLLocationCoordinate2D?
    var startPoint: CLLocationCoordinate2D?
    var customPoints: [RoutePoint] = []
    private(set) var route: Route?
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    private(set) var generationNotes: [String] = []
    private(set) var effectiveSpacing: Double?

    // MARK: UI state
    var tapMode: MapTapMode = .areaCenter
    var selectedTab: PanelTab = .route
    var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    var alert: AppAlert?
    var isImporting = false
    var isExporting = false
    var exportFormat: GPXExportFormat = .xcodeWaypoints
    private(set) var exportDocument: GPXFile?
    var selectedPointID: UUID?
    private(set) var hapticTick = 0
    private(set) var finishTick = 0

    // MARK: Progress state
    private(set) var logs: [LogEntry] = []
    private(set) var coverage: CoverageGrid?
    private(set) var coveredPolygons: [CoveragePolygon] = []
    private(set) var trail: [CLLocationCoordinate2D] = []

    // MARK: Engines
    let engine = RoutePlaybackEngine()
    let live = LiveRouteTracker()
    let location = LocationService()

    private let generator = RouteGenerator()
    private let store = SessionStore()
    private let logger = Logger(subsystem: "com.territoryplanner.app", category: "planner")
    @ObservationIgnored private var regenerateTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var lastPolygonRebuild = Date.distantPast

    init() {
        engine.onPosition = { [weak self] coordinate in
            self?.handlePosition(coordinate)
        }
        engine.onEvent = { [weak self] event in
            self?.handlePlaybackEvent(event)
        }
        location.onLocation = { [weak self] fix in
            self?.handleDeviceLocation(fix)
        }
        location.onError = { [weak self] message in
            self?.log("Core Location: \(message)", level: .error)
        }
        restoreSession()
    }

    // MARK: - Derived

    var activeSource: LocationSource { preferences.locationSource }

    var playbackState: PlaybackState {
        activeSource == .simulation ? engine.state : live.state
    }

    var isPlaybackActive: Bool {
        playbackState == .running || playbackState == .paused
    }

    var markerCoordinate: CLLocationCoordinate2D? {
        switch activeSource {
        case .simulation: engine.currentCoordinate
        case .device: live.isActive ? live.lastLocation?.coordinate : nil
        }
    }

    var progress: ProgressSnapshot {
        let total = route?.points.count ?? 0
        let distanceTotal = engine.points.isEmpty ? (route?.totalDistance ?? 0) : engine.totalDistance
        switch activeSource {
        case .simulation:
            let eta: TimeInterval?
            if engine.state == .idle {
                eta = route.map { $0.estimatedDuration(speed: settings.speed) / max(preferences.timeScale, 0.01) }
            } else {
                eta = engine.remainingWallTime
            }
            return ProgressSnapshot(
                state: engine.state,
                processed: engine.processedCount,
                total: total,
                routeFraction: engine.fraction,
                coverageFraction: coverage?.fraction ?? 0,
                coveredArea: coverage?.coveredArea ?? 0,
                distanceDone: engine.distanceTravelled,
                distanceTotal: distanceTotal,
                eta: eta,
                elapsed: engine.elapsed,
                speed: settings.speed * preferences.timeScale
            )
        case .device:
            let eta: TimeInterval? = live.isActive ? live.remainingTime : route.map { $0.estimatedDuration(speed: settings.speed) }
            return ProgressSnapshot(
                state: live.state,
                processed: live.processedCount,
                total: total,
                routeFraction: live.fraction,
                coverageFraction: coverage?.fraction ?? 0,
                coveredArea: coverage?.coveredArea ?? 0,
                distanceDone: live.distanceTravelled,
                distanceTotal: route?.totalDistance ?? 0,
                eta: eta,
                elapsed: live.elapsed,
                speed: live.observedSpeed
            )
        }
    }

    /// Waypoint markers for the map; suppressed for very long routes where the polyline is enough.
    var waypointMarkers: [WaypointMarker] {
        guard preferences.showWaypoints, let route, route.points.count <= 400 else { return [] }
        return route.points.enumerated().map { index, point in
            WaypointMarker(
                id: point.id,
                index: index,
                coordinate: point.coordinate,
                hasPause: point.pause > 0,
                isReached: index <= (activeSource == .simulation ? engine.reachedIndex : live.reachedIndex),
                isSelected: point.id == selectedPointID
            )
        }
    }

    var customAnchorMarkers: [WaypointMarker] {
        customPoints.enumerated().map { index, point in
            WaypointMarker(id: point.id, index: index, coordinate: point.coordinate, hasPause: point.pause > 0, isReached: false, isSelected: false)
        }
    }

    var simctlCommand: String? {
        guard let route else { return nil }
        return SimctlCommandBuilder.command(for: route, speed: settings.speed)
    }

    // MARK: - Map interaction

    func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        guard GeoMath.isValid(coordinate) else { return }
        switch tapMode {
        case .areaCenter:
            areaCenter = coordinate
            log("Центр области: \(Formatters.coordinate(coordinate))")
            settingsDidChange()
        case .startPoint:
            startPoint = coordinate
            log("Стартовая точка: \(Formatters.coordinate(coordinate))")
            settingsDidChange()
        case .customPoint:
            customPoints.append(RoutePoint(coordinate: coordinate, name: "C\(customPoints.count + 1)"))
            if settings.pattern != .custom {
                settings.pattern = .custom
            }
            settingsDidChange()
        case .none:
            return
        }
        hapticTick += 1
    }

    func undoLastCustomPoint() {
        guard !customPoints.isEmpty else { return }
        customPoints.removeLast()
        settingsDidChange()
    }

    func clearCustomPoints() {
        customPoints.removeAll()
        if settings.pattern == .custom && !isPlaybackActive {
            clearRoute()
        }
        log("Свои точки очищены")
    }

    func clearStartPoint() {
        startPoint = nil
        settingsDidChange()
    }

    func useCurrentLocationAsCenter() {
        location.requestAuthorization()
        guard let fix = location.lastLocation ?? location.lastLocationFromManagerFallback else {
            location.startUpdating()
            alert = AppAlert(title: "Позиция пока неизвестна", message: "Разрешите доступ к геопозиции и повторите через пару секунд.")
            return
        }
        areaCenter = fix.coordinate
        log("Центр области по текущей позиции")
        settingsDidChange()
        focusArea()
    }

    func focusArea() {
        if let center = areaCenter {
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .region(GeoMath.region(center: center, radius: settings.areaRadius))
            }
        } else {
            focusRoute()
        }
    }

    func focusRoute() {
        guard let region = GeoMath.boundingRegion(for: routeCoordinates) else {
            if let center = areaCenter {
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(GeoMath.region(center: center, radius: settings.areaRadius))
                }
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(region)
        }
    }

    func focus(on point: RoutePoint) {
        selectedPointID = point.id
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: point.coordinate, latitudinalMeters: 300, longitudinalMeters: 300))
        }
    }

    // MARK: - Generation

    /// Called whenever settings, area or anchors change. Regenerates a preview automatically
    /// unless the route was hand-edited, imported, or is being played back.
    func settingsDidChange() {
        engine.speed = settings.speed
        live.plannedSpeed = settings.speed
        guard preferences.autoRegenerate, !isPlaybackActive else { return }
        if let route, route.isManuallyEdited { return }
        let canGenerate = settings.pattern == .custom ? customPoints.count >= 2 : areaCenter != nil
        guard canGenerate else { return }
        regenerateTask?.cancel()
        regenerateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.generateRoute(userInitiated: false)
        }
    }

    func generateRoute(userInitiated: Bool = true) {
        if isPlaybackActive {
            stopPlayback()
        }
        do {
            let result = try generator.generate(
                settings: settings,
                center: areaCenter,
                start: startPoint,
                customPoints: customPoints
            )
            setRoute(result.route)
            generationNotes = result.notes
            effectiveSpacing = result.effectiveSpacing
            if userInitiated {
                log("Маршрут «\(result.route.name)»: \(result.route.points.count) точек, \(Formatters.distance(result.route.totalDistance))", level: .success)
                for note in result.notes { log(note, level: .warning) }
                focusRoute()
                hapticTick += 1
            }
            persist()
        } catch {
            if userInitiated {
                alert = AppAlert(title: "Не удалось построить маршрут", message: error.localizedDescription)
                log(error.localizedDescription, level: .error)
            }
        }
    }

    /// Discards hand edits and rebuilds from current settings.
    func regenerateDiscardingEdits() {
        if var current = route {
            current.isManuallyEdited = false
            route = current
        }
        generateRoute(userInitiated: true)
    }

    func clearRoute() {
        stopPlayback()
        route = nil
        routeCoordinates = []
        generationNotes = []
        effectiveSpacing = nil
        engine.load([])
        resetCoverage()
        log("Маршрут очищен")
        persist()
    }

    private func setRoute(_ newRoute: Route?) {
        route = newRoute
        routeCoordinates = newRoute?.coordinates ?? []
        engine.load(newRoute?.points ?? [])
        live.load(newRoute?.points ?? [])
        resetCoverage()
        if let selected = selectedPointID, newRoute?.points.contains(where: { $0.id == selected }) != true {
            selectedPointID = nil
        }
    }

    // MARK: - Point editing

    private func editRoute(_ description: String, _ mutate: (inout Route) -> Void) {
        guard var current = route else { return }
        if isPlaybackActive {
            stopPlayback()
            log("Воспроизведение остановлено для редактирования", level: .warning)
        }
        mutate(&current)
        current.isManuallyEdited = true
        if current.source == .generated { current.source = .custom }
        setRoute(current)
        log(description)
        persist()
    }

    func deletePoints(at offsets: IndexSet) {
        editRoute("Удалено точек: \(offsets.count)") { $0.points.remove(atOffsets: offsets) }
    }

    func deletePoint(id: UUID) {
        guard let index = route?.points.firstIndex(where: { $0.id == id }) else { return }
        deletePoints(at: IndexSet(integer: index))
    }

    func movePoints(from source: IndexSet, to destination: Int) {
        editRoute("Порядок точек изменён") { $0.points.move(fromOffsets: source, toOffset: destination) }
    }

    func updatePoint(_ point: RoutePoint) {
        guard GeoMath.isValid(point.coordinate) else {
            alert = AppAlert(title: "Некорректные координаты", message: "Широта должна быть в диапазоне −90…90, долгота −180…180.")
            return
        }
        editRoute("Точка обновлена: \(Formatters.coordinate(point.coordinate))") { route in
            if let index = route.points.firstIndex(where: { $0.id == point.id }) {
                route.points[index] = point
            }
        }
    }

    func insertPoint(after id: UUID) {
        guard let points = route?.points, let index = points.firstIndex(where: { $0.id == id }) else { return }
        let a = points[index].coordinate
        let b = index + 1 < points.count
            ? points[index + 1].coordinate
            : GeoMath.destination(from: a, distance: settings.spacing, bearing: 90)
        let midpoint = RoutePoint(coordinate: GeoMath.interpolate(a, b, fraction: 0.5))
        editRoute("Вставлена точка после №\(index + 1)") { $0.points.insert(midpoint, at: index + 1) }
    }

    func reverseRoute() {
        editRoute("Маршрут развёрнут") { $0.points.reverse() }
    }

    func densifyRoute() {
        guard let before = route?.points.count else { return }
        editRoute("Маршрут уплотнён до шага \(Formatters.distance(settings.spacing))") { route in
            route.points = RouteGenerator.densify(route.points, maxSpacing: settings.spacing)
        }
        if let after = route?.points.count, after == before {
            log("Уплотнение не потребовалось: все отрезки короче шага", level: .info)
        }
    }

    func applyPauseToAll(_ seconds: Double) {
        editRoute("Пауза \(Int(seconds)) с для всех точек") { route in
            for index in route.points.indices { route.points[index].pause = seconds }
        }
    }

    // MARK: - Playback

    func startPlayback() {
        guard let route, !route.points.isEmpty else {
            alert = AppAlert(title: "Нет маршрута", message: "Сначала постройте или импортируйте маршрут.")
            return
        }
        resetCoverage()
        switch activeSource {
        case .simulation:
            engine.speed = settings.speed
            engine.timeScale = preferences.timeScale
            engine.load(route.points)
            engine.start()
        case .device:
            live.arrivalThreshold = max(10, settings.coverageRadius)
            live.plannedSpeed = settings.speed
            live.load(route.points)
            live.start()
            location.startUpdating()
            log("Отслеживание Core Location запущено (\(route.points.count) точек)", level: .success)
            if !location.isAuthorized && location.authorizationStatus != .notDetermined {
                log("Нет доступа к геопозиции — разрешите его в Настройках iOS", level: .error)
            }
        }
        updateIdleTimer()
    }

    func togglePlayPause() {
        switch playbackState {
        case .idle, .finished: startPlayback()
        case .running: pausePlayback()
        case .paused: resumePlayback()
        }
    }

    func pausePlayback() {
        switch activeSource {
        case .simulation: engine.pause()
        case .device:
            live.pause()
            location.stopUpdating()
            coverage?.breakTrail()
            log("Отслеживание на паузе (точка \(live.processedCount)/\(live.points.count))")
        }
        rebuildCoveragePolygons(force: true)
        updateIdleTimer()
    }

    func resumePlayback() {
        switch activeSource {
        case .simulation:
            engine.speed = settings.speed
            engine.timeScale = preferences.timeScale
            engine.resume()
        case .device:
            live.resume()
            location.startUpdating()
            log("Отслеживание возобновлено")
        }
        updateIdleTimer()
    }

    func stopPlayback() {
        switch activeSource {
        case .simulation:
            engine.stop()
        case .device:
            if live.isActive || live.state == .finished {
                log("Отслеживание остановлено: \(live.processedCount)/\(live.points.count) точек")
            }
            live.stop()
            location.stopUpdating()
        }
        // Stop the other source too, in case the user switched sources mid-run.
        if engine.state != .idle { engine.stop() }
        if live.state != .idle { live.stop(); location.stopUpdating() }
        rebuildCoveragePolygons(force: true)
        updateIdleTimer()
    }

    func stepForward() {
        guard activeSource == .simulation else { return }
        prepareEngineIfNeeded()
        engine.stepForward()
    }

    func stepBackward() {
        guard activeSource == .simulation else { return }
        engine.stepBackward()
    }

    func jump(to point: RoutePoint) {
        guard activeSource == .simulation, let index = route?.points.firstIndex(where: { $0.id == point.id }) else { return }
        prepareEngineIfNeeded()
        coverage?.breakTrail()
        engine.jump(to: index)
        selectedPointID = point.id
    }

    func setTimeScale(_ scale: Double) {
        preferences.timeScale = scale
        engine.timeScale = scale
        log("Скорость симуляции ×\(Self.scaleLabel(scale))")
        persist()
    }

    static func scaleLabel(_ scale: Double) -> String {
        scale == scale.rounded() ? String(Int(scale)) : String(format: "%.1f", scale)
    }

    /// Before the first step in idle state, make sure the engine has the current route and a fresh coverage grid.
    private func prepareEngineIfNeeded() {
        guard let route else { return }
        if engine.state == .idle || engine.state == .finished {
            engine.speed = settings.speed
            engine.timeScale = preferences.timeScale
            if engine.points.map(\.id) != route.points.map(\.id) {
                engine.load(route.points)
            }
            if engine.state == .finished || engine.processedCount == 0 {
                resetCoverage()
            }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = preferences.keepScreenAwake && playbackState == .running
    }

    // MARK: - Position handling

    private func handlePosition(_ coordinate: CLLocationCoordinate2D) {
        if coverage == nil { resetCoverage() }
        let changed = coverage?.mark(coordinate) ?? false
        appendTrail(coordinate)
        if changed { rebuildCoveragePolygons(force: false) }
        if preferences.followMarker && playbackState == .running {
            cameraPosition = .camera(MapCamera(centerCoordinate: coordinate, distance: max(600, settings.areaRadius * 1.6)))
        }
    }

    private func handleDeviceLocation(_ fix: CLLocation) {
        guard activeSource == .device, live.state == .running else { return }
        let reached = live.ingest(fix)
        handlePosition(fix.coordinate)
        for index in reached {
            log("Достигнута точка \(index + 1)/\(live.points.count) (Core Location)")
        }
        if live.state == .finished {
            location.stopUpdating()
            log("Маршрут пройден по данным Core Location · покрытие \(Formatters.percent(coverage?.fraction ?? 0))", level: .success)
            rebuildCoveragePolygons(force: true)
            finishTick += 1
            updateIdleTimer()
        }
    }

    private func handlePlaybackEvent(_ event: PlaybackEvent) {
        switch event {
        case .started(let count):
            log("Симуляция запущена: \(count) точек, \(Formatters.speed(settings.speed)), ×\(Self.scaleLabel(preferences.timeScale))", level: .success)
        case .paused(let index):
            log("Пауза на точке \(index + 1)/\(engine.points.count)")
        case .resumed:
            log("Продолжение воспроизведения")
        case .stopped(let processed):
            log("Остановлено: обработано \(processed)/\(engine.points.count) точек", level: .warning)
        case .finished(let distance, let elapsed):
            log("Маршрут завершён: \(Formatters.distance(distance)) за \(Formatters.duration(elapsed)) (сим.) · покрытие \(Formatters.percent(coverage?.fraction ?? 0))", level: .success)
            rebuildCoveragePolygons(force: true)
            finishTick += 1
            updateIdleTimer()
        case .reached(let index):
            // Logging every waypoint of a 5 000-point route floods the journal; log milestones.
            let count = engine.points.count
            let milestone = max(1, count / 20)
            if index == 0 || index % milestone == 0 || index == count - 1 || engine.state == .paused {
                log("Точка \(index + 1)/\(count)")
            }
        case .dwelling(let index, let seconds):
            log("Пауза \(Int(seconds)) с на точке \(index + 1)")
        case .jumped(let index):
            log("Шаг: точка \(index + 1)/\(engine.points.count)")
            hapticTick += 1
        }
    }

    private func appendTrail(_ coordinate: CLLocationCoordinate2D) {
        if let last = trail.last, GeoMath.distance(last, coordinate) < 2 { return }
        trail.append(coordinate)
        // Decimate a very long trail to keep the overlay light.
        if trail.count > 6_000 {
            trail = trail.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil }
        }
    }

    private func resetCoverage() {
        trail = []
        guard let center = areaCenter ?? route.flatMap({ GeoMath.enclosingCircle(for: $0.coordinates)?.center }) else {
            coverage = nil
            coveredPolygons = []
            return
        }
        coverage = CoverageGrid(
            center: center,
            radius: settings.areaRadius,
            footprint: settings.coverageRadius,
            clipToCircle: settings.clipToCircle
        )
        coveredPolygons = []
    }

    /// Rebuilds the merged coverage overlay at most ~4 times per second during playback.
    private func rebuildCoveragePolygons(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPolygonRebuild) > 0.25 else { return }
        lastPolygonRebuild = now
        guard let coverage else {
            coveredPolygons = []
            return
        }
        coveredPolygons = coverage.coveredPolygons().enumerated().map { CoveragePolygon(id: $0.offset, coordinates: $0.element) }
    }

    // MARK: - GPX

    func importGPX(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                alert = AppAlert(title: "Импорт не удался", message: error.localizedDescription)
            }
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let parsed = try GPXParser.parse(url: url)
                applyImported(parsed, fileName: url.deletingPathExtension().lastPathComponent)
            } catch {
                alert = AppAlert(title: "Файл GPX отклонён", message: error.localizedDescription)
                log("Импорт \(url.lastPathComponent): \(error.localizedDescription)", level: .error)
            }
        }
    }

    func loadSampleRoute() {
        let url = Bundle.main.url(forResource: "SampleRoute", withExtension: "gpx")
            ?? Bundle.main.url(forResource: "SampleRoute", withExtension: "gpx", subdirectory: "Resources")
        guard let url else {
            alert = AppAlert(title: "Демо недоступно", message: "SampleRoute.gpx не найден в бандле приложения.")
            return
        }
        do {
            applyImported(try GPXParser.parse(url: url), fileName: "Демо-маршрут")
        } catch {
            alert = AppAlert(title: "Демо не загрузилось", message: error.localizedDescription)
        }
    }

    private func applyImported(_ parsed: GPXParseResult, fileName: String) {
        stopPlayback()
        let coordinates = parsed.points.map(\.coordinate)
        if let circle = GeoMath.enclosingCircle(for: coordinates) {
            areaCenter = circle.center
            settings.areaRadius = (circle.radius + settings.coverageRadius).clamped(to: RouteSettings.Limits.areaRadius)
        }
        settings.pattern = .custom
        customPoints = parsed.points
        startPoint = nil
        var imported = Route(name: parsed.name ?? fileName, pattern: .custom, source: .imported, points: parsed.points)
        imported.isManuallyEdited = true
        setRoute(imported)
        generationNotes = parsed.warnings
        effectiveSpacing = nil
        log("Импортировано \(parsed.points.count) точек (<\(parsed.sourceKind)>) из «\(fileName)», \(Formatters.distance(imported.totalDistance))", level: .success)
        for warning in parsed.warnings { log(warning, level: .warning) }
        focusRoute()
        persist()
    }

    func prepareExport() {
        guard let route, !route.points.isEmpty else {
            alert = AppAlert(title: "Нечего экспортировать", message: "Постройте или импортируйте маршрут.")
            return
        }
        exportDocument = GPXFile(text: GPXWriter.makeGPX(route: route, speed: settings.speed, format: exportFormat))
        isExporting = true
    }

    var exportFileName: String {
        let base = (route?.name ?? "route")
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(base.isEmpty ? "route" : base)-\(Formatters.fileStamp.string(from: Date()))"
    }

    func exportFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            log("GPX сохранён: \(url.lastPathComponent) (\(exportFormat.title))", level: .success)
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                log("Экспорт не удался: \(error.localizedDescription)", level: .error)
                alert = AppAlert(title: "Экспорт не удался", message: error.localizedDescription)
            }
        }
        exportDocument = nil
    }

    func copySimctlCommand() {
        guard let command = simctlCommand else { return }
        UIPasteboard.general.string = command
        log("Команда simctl скопирована (\(route?.points.count ?? 0) точек)", level: .success)
        hapticTick += 1
    }

    // MARK: - Logging

    func log(_ message: String, level: LogEntry.Level = .info) {
        logs.append(LogEntry(date: Date(), level: level, message: message))
        if logs.count > 1_500 { logs.removeFirst(logs.count - 1_500) }
        switch level {
        case .error: logger.error("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        default: logger.info("\(message, privacy: .public)")
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    var logsAsText: String {
        logs.map(\.exportLine).joined(separator: "\n")
    }

    // MARK: - Persistence

    /// Debounced save for high-frequency changes (slider drags).
    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func persist() {
        let session = PlannerSession(
            settings: settings,
            preferences: preferences,
            areaCenter: areaCenter.map(CodableCoordinate.init),
            startPoint: startPoint.map(CodableCoordinate.init),
            customPoints: customPoints,
            route: route
        )
        do {
            try store.save(session)
        } catch {
            logger.error("Session save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func resetEverything() {
        stopPlayback()
        settings = RouteSettings()
        preferences = AppPreferences()
        areaCenter = nil
        startPoint = nil
        customPoints = []
        setRoute(nil)
        generationNotes = []
        effectiveSpacing = nil
        try? store.clear()
        log("Все настройки сброшены", level: .warning)
    }

    private func restoreSession() {
        do {
            guard let session = try store.load() else {
                log("Добро пожаловать. Выберите центр области на карте.")
                return
            }
            settings = session.settings.validated()
            preferences = session.preferences
            areaCenter = session.areaCenter?.coordinate
            startPoint = session.startPoint?.coordinate
            customPoints = session.customPoints
            setRoute(session.route)
            if let route = session.route {
                log("Восстановлен маршрут «\(route.name)» (\(route.points.count) точек)")
                if let region = GeoMath.boundingRegion(for: route.coordinates) {
                    cameraPosition = .region(region)
                }
            } else if let center = areaCenter {
                cameraPosition = .region(GeoMath.region(center: center, radius: settings.areaRadius))
            }
        } catch {
            log("Не удалось восстановить сессию: \(error.localizedDescription)", level: .warning)
        }
    }
}

private extension LocationService {
    /// Fix used when the service has not delivered one yet in this session.
    var lastLocationFromManagerFallback: CLLocation? { CLLocationManager().location }
}
