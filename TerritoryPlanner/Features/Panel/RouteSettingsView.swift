import SwiftUI

struct RouteSettingsView: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AreaSection()
                PatternSection()
                ParametersSection()
                if vm.settings.pattern != .custom {
                    DirectionSection()
                }
                PlaybackSettingsSection()
                SummarySection()
                GPXSection()
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Area

private struct AreaSection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("Область", systemImage: "scope")
            VStack(spacing: 14) {
                coordinateRow(
                    title: "Центр",
                    icon: "scope",
                    tint: Theme.accent,
                    value: vm.areaCenter.map(Formatters.coordinate) ?? "Не выбран — коснитесь карты",
                    isSet: vm.areaCenter != nil,
                    onClear: nil
                )
                coordinateRow(
                    title: "Старт",
                    icon: "flag.fill",
                    tint: Theme.start,
                    value: vm.startPoint.map(Formatters.coordinate) ?? "Автоматически (край шаблона)",
                    isSet: vm.startPoint != nil,
                    onClear: vm.startPoint == nil ? nil : { vm.clearStartPoint() }
                )
                SettingSlider(
                    title: "Радиус области",
                    value: $vm.settings.areaRadius,
                    range: RouteSettings.Limits.areaRadius.lowerBound...5_000,
                    step: 10,
                    format: Formatters.distance
                )
                HStack(spacing: 10) {
                    Button {
                        vm.useCurrentLocationAsCenter()
                    } label: {
                        Label("Моя позиция", systemImage: "location.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        vm.tapMode = .startPoint
                    } label: {
                        Label("Задать старт", systemImage: "flag")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.start))
                }
            }
            .glassCard()
        }
    }

    private func coordinateRow(title: String, icon: String, tint: Color, value: String, isSet: Bool, onClear: (() -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSet ? Color.black : tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(isSet ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.15))))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
                Text(value)
                    .font(isSet ? .footnote.monospacedDigit() : .footnote)
                    .foregroundStyle(isSet ? .white : Theme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiaryText)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Сбросить \(title.lowercased())")
            }
        }
    }
}

// MARK: - Pattern

private struct PatternSection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("Шаблон", systemImage: "square.grid.3x3.topleft.filled")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(RoutePattern.allCases) { pattern in
                        PatternCard(pattern: pattern, isSelected: vm.settings.pattern == pattern) {
                            withAnimation(Theme.spring) {
                                vm.settings.pattern = pattern
                                if pattern == .custom { vm.tapMode = .customPoint }
                                else if vm.tapMode == .customPoint { vm.tapMode = .areaCenter }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            Text(vm.settings.pattern.summary)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut, value: vm.settings.pattern)

            if vm.settings.pattern == .custom {
                HStack(spacing: 10) {
                    Label("\(vm.customPoints.count) опорных точек", systemImage: "mappin.and.ellipse")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Отменить") { vm.undoLastCustomPoint() }
                        .disabled(vm.customPoints.isEmpty)
                    Button("Очистить", role: .destructive) { vm.clearCustomPoints() }
                        .disabled(vm.customPoints.isEmpty)
                }
                .font(.footnote.weight(.semibold))
                .glassCard(padding: 12)
            }
        }
    }
}

private struct PatternCard: View {
    let pattern: RoutePattern
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: pattern.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(pattern.title)
                    .font(.caption.weight(.semibold))
            }
            .frame(width: 78, height: 74)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Theme.hairline)
            )
            .scaleEffect(isSelected ? 1.0 : 0.96)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Parameters

private struct ParametersSection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let pattern = vm.settings.pattern
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("Параметры", systemImage: "slider.horizontal.3")
            VStack(spacing: 16) {
                SettingSlider(
                    title: pattern == .custom ? "Макс. шаг между точками" : "Расстояние между точками",
                    value: $vm.settings.spacing,
                    range: RouteSettings.Limits.spacing.lowerBound...500,
                    step: 5,
                    format: Formatters.distance
                )
                SettingSlider(
                    title: "Лимит точек",
                    value: Binding(
                        get: { Double(vm.settings.maxPoints) },
                        set: { vm.settings.maxPoints = Int($0) }
                    ),
                    range: Double(RouteSettings.Limits.maxPoints.lowerBound)...Double(RouteSettings.Limits.maxPoints.upperBound),
                    step: 10,
                    format: { "\(Int($0))" }
                )
                SettingSlider(
                    title: "Радиус покрытия",
                    value: $vm.settings.coverageRadius,
                    range: RouteSettings.Limits.coverageRadius.lowerBound...200,
                    step: 1,
                    format: Formatters.distance
                )
                if pattern != .custom {
                    ToggleRow(
                        title: "Подбирать шаг под лимит",
                        subtitle: "Иначе маршрут обрезается по лимиту",
                        isOn: $vm.settings.autoFitSpacing
                    )
                }
                if pattern == .grid || pattern == .snake {
                    ToggleRow(title: "Обрезать по кругу", subtitle: "Только точки внутри радиуса", isOn: $vm.settings.clipToCircle)
                }
                if pattern == .custom {
                    ToggleRow(title: "Уплотнять отрезки", subtitle: "Промежуточные точки с заданным шагом", isOn: $vm.settings.densifyCustom)
                    ToggleRow(title: "Обратный порядок", isOn: $vm.settings.reversed)
                }
            }
            .glassCard()
        }
    }
}

// MARK: - Direction

private struct DirectionSection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let pattern = vm.settings.pattern
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("Направление", systemImage: "arrow.triangle.turn.up.right.diamond")
            VStack(alignment: .leading, spacing: 16) {
                if pattern == .spiral || pattern == .circular {
                    Picker("Вращение", selection: $vm.settings.turnDirection) {
                        ForEach(TurnDirection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if pattern == .grid || pattern == .snake {
                    Picker("Ряды", selection: $vm.settings.orientation) {
                        ForEach(SweepOrientation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if pattern != .custom {
                    ToggleRow(
                        title: pattern == .spiral ? "От края к центру" : (pattern == .circular ? "От центра наружу" : "Обратный порядок"),
                        isOn: $vm.settings.reversed
                    )
                    SettingSlider(
                        title: "Поворот шаблона",
                        value: $vm.settings.rotation,
                        range: RouteSettings.Limits.rotation,
                        step: 1,
                        format: { "\(Int($0))°" }
                    )
                }
            }
            .glassCard()
        }
    }
}

// MARK: - Playback

private struct PlaybackSettingsSection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("Воспроизведение", systemImage: "play.circle")
            VStack(spacing: 16) {
                SettingSlider(
                    title: "Скорость",
                    value: Binding(
                        get: { vm.settings.speed * 3.6 },
                        set: { vm.settings.speed = $0 / 3.6 }
                    ),
                    range: 1...200,
                    step: 1,
                    format: { "\(Int($0.rounded())) км/ч" }
                )
                SettingSlider(
                    title: "Пауза в каждой точке",
                    value: $vm.settings.pauseAtPoint,
                    range: 0...120,
                    step: 1,
                    format: { $0 == 0 ? "нет" : "\(Int($0)) с" }
                )
                HStack(spacing: 8) {
                    ForEach([("Пешком", 5.0), ("Бег", 10.0), ("Велосипед", 18.0), ("Авто", 50.0)], id: \.0) { preset in
                        Chip(title: preset.0, isSelected: abs(vm.settings.speed * 3.6 - preset.1) < 0.5) {
                            vm.settings.speed = preset.1 / 3.6
                        }
                    }
                }
            }
            .glassCard()
        }
    }
}

// MARK: - Summary

private struct SummarySection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("Итог", systemImage: "checklist")
            VStack(alignment: .leading, spacing: 12) {
                if let route = vm.route {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile(title: "Точек", value: "\(route.points.count)", systemImage: "mappin")
                        StatTile(title: "Длина", value: Formatters.distance(route.totalDistance), systemImage: "ruler")
                        StatTile(title: "Длительность", value: Formatters.duration(route.estimatedDuration(speed: vm.settings.speed)), systemImage: "clock", tint: Theme.accentSecondary)
                        StatTile(title: "Шаг", value: vm.effectiveSpacing.map(Formatters.distance) ?? "—", systemImage: "arrow.left.and.right", tint: Theme.accentSecondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: route.isManuallyEdited ? "pencil.circle.fill" : "sparkles")
                        Text("\(route.source.title)\(route.isManuallyEdited ? " · изменён вручную" : "")")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Маршрут ещё не построен. Выберите центр области на карте — предпросмотр появится автоматически.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                ForEach(vm.generationNotes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if vm.route?.isManuallyEdited == true {
                        vm.regenerateDiscardingEdits()
                    } else {
                        vm.generateRoute()
                    }
                } label: {
                    Label(vm.route?.isManuallyEdited == true ? "Перестроить (сбросить правки)" : "Построить маршрут", systemImage: "wand.and.stars")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(vm.isPlaybackActive)

                if vm.route != nil {
                    Button(role: .destructive) {
                        vm.clearRoute()
                    } label: {
                        Label("Очистить маршрут", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                }
            }
            .glassCard()
        }
    }
}

// MARK: - GPX

private struct GPXSection: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(alignment: .leading, spacing: 12) {
            PanelSectionHeader("GPX", systemImage: "doc.badge.arrow.up")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        vm.isImporting = true
                    } label: {
                        Label("Импорт", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        vm.prepareExport()
                    } label: {
                        Label("Экспорт", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                    .disabled(vm.route == nil)
                }

                Picker("Формат экспорта", selection: $vm.exportFormat) {
                    ForEach(GPXExportFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Button {
                    vm.copySimctlCommand()
                } label: {
                    Label("Скопировать команду simctl", systemImage: "terminal")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(vm.route == nil)

                Button {
                    vm.loadSampleRoute()
                } label: {
                    Label("Загрузить демо-маршрут", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("Формат «Xcode» содержит время в каждой точке: Xcode воспроизводит его с заданной скоростью и паузами через Debug ▸ Simulate Location.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }
}
