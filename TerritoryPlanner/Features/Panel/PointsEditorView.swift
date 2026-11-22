import SwiftUI
import CoreLocation

struct PointsEditorView: View {
    @Environment(PlannerViewModel.self) private var vm
    @State private var editMode: EditMode = .inactive
    @State private var editingPoint: RoutePoint?

    var body: some View {
        if let route = vm.route, !route.points.isEmpty {
            VStack(spacing: 0) {
                toolbar(route: route)
                List {
                    ForEach(Array(route.points.enumerated()), id: \.element.id) { index, point in
                        PointRow(
                            index: index,
                            point: point,
                            legDistance: index > 0 ? GeoMath.distance(route.points[index - 1].coordinate, point.coordinate) : nil,
                            isReached: index <= vm.engine.reachedIndex && vm.activeSource == .simulation,
                            isSelected: vm.selectedPointID == point.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.focus(on: point)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { vm.deletePoint(id: point.id) } label: { Label("Удалить", systemImage: "trash") }
                            Button { editingPoint = point } label: { Label("Изменить", systemImage: "pencil") }
                                .tint(Theme.accentSecondary)
                        }
                        .swipeActions(edge: .leading) {
                            Button { vm.insertPoint(after: point.id) } label: { Label("Вставить", systemImage: "plus") }
                                .tint(Theme.accent)
                        }
                        .contextMenu {
                            Button { editingPoint = point } label: { Label("Изменить", systemImage: "pencil") }
                            Button { vm.insertPoint(after: point.id) } label: { Label("Вставить после", systemImage: "plus") }
                            Button { vm.focus(on: point) } label: { Label("Показать на карте", systemImage: "scope") }
                            if vm.activeSource == .simulation {
                                Button { vm.jump(to: point) } label: { Label("Перейти сюда (симуляция)", systemImage: "location.north.line.fill") }
                            }
                            Divider()
                            Button(role: .destructive) { vm.deletePoint(id: point.id) } label: { Label("Удалить", systemImage: "trash") }
                        }
                        .listRowBackground(vm.selectedPointID == point.id ? Theme.accent.opacity(0.12) : Color.clear)
                        .listRowSeparatorTint(Theme.hairline)
                    }
                    .onDelete { vm.deletePoints(at: $0) }
                    .onMove { vm.movePoints(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
            }
            .sheet(item: $editingPoint) { point in
                PointEditSheet(point: point) { updated in
                    vm.updatePoint(updated)
                }
                .presentationDetents([.medium])
                .presentationBackground(.regularMaterial)
                .preferredColorScheme(.dark)
            }
        } else {
            ContentUnavailableView {
                Label("Нет точек", systemImage: "mappin.slash")
            } description: {
                Text("Постройте маршрут, нарисуйте свой или импортируйте GPX.")
            } actions: {
                Button("Импорт GPX") { vm.isImporting = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxHeight: 320)
        }
    }

    private func toolbar(route: Route) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(route.points.count) точек")
                    .font(.subheadline.weight(.semibold))
                Text("\(Formatters.distance(route.totalDistance)) · пауз \(Formatters.duration(route.totalPause))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Menu {
                Button { vm.reverseRoute() } label: { Label("Развернуть порядок", systemImage: "arrow.left.arrow.right") }
                Button { vm.densifyRoute() } label: { Label("Уплотнить до шага \(Formatters.distance(vm.settings.spacing))", systemImage: "point.3.connected.trianglepath.dotted") }
                Menu {
                    ForEach([0.0, 2, 5, 10, 30, 60], id: \.self) { seconds in
                        Button(seconds == 0 ? "Без пауз" : "\(Int(seconds)) с") { vm.applyPauseToAll(seconds) }
                    }
                } label: {
                    Label("Пауза для всех точек", systemImage: "pause.circle")
                }
                Divider()
                Button { vm.isImporting = true } label: { Label("Импорт GPX", systemImage: "square.and.arrow.down") }
                Button { vm.prepareExport() } label: { Label("Экспорт GPX", systemImage: "square.and.arrow.up") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .disabled(vm.isPlaybackActive)

            Button(editMode.isEditing ? "Готово" : "Править") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct PointRow: View {
    let index: Int
    let point: RoutePoint
    let legDistance: Double?
    let isReached: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(isReached ? Color.black : Color.white)
                .frame(minWidth: 34, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isReached ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surfaceStrong))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.coordinate(point.coordinate))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    if let name = point.name { Text(name) }
                    if let legDistance { Text("+\(Formatters.distance(legDistance))") }
                    if point.pause > 0 {
                        Label("\(Int(point.pause)) с", systemImage: "pause.fill")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
            if isSelected {
                Image(systemName: "scope").foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Form for editing a single waypoint with input validation.
struct PointEditSheet: View {
    let point: RoutePoint
    let onSave: (RoutePoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var latitude: String
    @State private var longitude: String
    @State private var pause: Double
    @State private var name: String

    init(point: RoutePoint, onSave: @escaping (RoutePoint) -> Void) {
        self.point = point
        self.onSave = onSave
        _latitude = State(initialValue: String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), point.latitude))
        _longitude = State(initialValue: String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), point.longitude))
        _pause = State(initialValue: point.pause)
        _name = State(initialValue: point.name ?? "")
    }

    private var parsedLatitude: Double? {
        Double(latitude.replacingOccurrences(of: ",", with: ".")).flatMap { (-90...90).contains($0) ? $0 : nil }
    }

    private var parsedLongitude: Double? {
        Double(longitude.replacingOccurrences(of: ",", with: ".")).flatMap { (-180...180).contains($0) ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Координаты") {
                    LabeledContent("Широта") {
                        TextField("−90…90", text: $latitude)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(parsedLatitude == nil ? Theme.danger : .primary)
                    }
                    LabeledContent("Долгота") {
                        TextField("−180…180", text: $longitude)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(parsedLongitude == nil ? Theme.danger : .primary)
                    }
                }
                Section("Параметры") {
                    TextField("Название (необязательно)", text: $name)
                    Stepper(value: $pause, in: RouteSettings.Limits.pause, step: 1) {
                        LabeledContent("Пауза", value: pause == 0 ? "нет" : "\(Int(pause)) с")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Точка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let lat = parsedLatitude, let lon = parsedLongitude else { return }
                        var updated = point
                        updated.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        updated.pause = pause
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        updated.name = trimmed.isEmpty ? nil : trimmed
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(parsedLatitude == nil || parsedLongitude == nil)
                }
            }
        }
    }
}
