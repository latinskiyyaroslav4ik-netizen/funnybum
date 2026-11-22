import SwiftUI
import UniformTypeIdentifiers

/// The panel hosted either in the bottom sheet or in the sidebar.
struct ControlPanel: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            PlaybackBar()
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            PanelTabBar(selection: $vm.selectedTab)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            Divider().overlay(Theme.hairline)

            Group {
                switch vm.selectedTab {
                case .route: RouteSettingsView()
                case .progress: ProgressPanelView()
                case .points: PointsEditorView()
                case .logs: LogsView()
                case .settings: AppSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
            .id(vm.selectedTab)
        }
        .animation(.easeInOut(duration: 0.2), value: vm.selectedTab)
        .fileImporter(isPresented: $vm.isImporting, allowedContentTypes: [.gpx, .xml]) { result in
            vm.importGPX(from: result)
        }
        .fileExporter(
            isPresented: $vm.isExporting,
            document: vm.exportDocument,
            contentType: .gpx,
            defaultFilename: vm.exportFileName
        ) { result in
            vm.exportFinished(result)
        }
        .alert(
            vm.alert?.title ?? "",
            isPresented: Binding(get: { vm.alert != nil }, set: { if !$0 { vm.alert = nil } }),
            presenting: vm.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

private struct PanelTabBar: View {
    @Binding var selection: PanelTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selection == tab ? Theme.accent : Theme.secondaryText)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.accent.opacity(0.14))
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .animation(Theme.spring, value: selection)
    }
}

/// Always-visible transport controls and headline progress.
struct PlaybackBar: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        let p = vm.progress
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(state: p.state)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.route?.name ?? "Маршрут не построен")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(p.state.title) · \(vm.activeSource.title)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Text(Formatters.percent(p.routeFraction))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
            }

            GradientProgressBar(fraction: p.routeFraction)

            HStack {
                Label("\(p.processed)/\(p.total)", systemImage: "mappin.circle")
                Spacer()
                Label("Покрытие \(Formatters.percent(p.coverageFraction))", systemImage: "square.dashed.inset.filled")
                Spacer()
                Label(p.eta.map(Formatters.duration) ?? "—", systemImage: "clock")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .labelStyle(CompactLabelStyle())

            TransportControls()
        }
    }
}

struct TransportControls: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        let state = vm.playbackState
        let hasRoute = !(vm.route?.points.isEmpty ?? true)
        let canStep = vm.activeSource == .simulation && hasRoute
        HStack(spacing: 14) {
            Button { vm.stepBackward() } label: { Image(systemName: "backward.end.fill") }
                .buttonStyle(CircleIconButtonStyle(diameter: 40))
                .disabled(!canStep || vm.engine.reachedIndex <= 0)
                .accessibilityLabel("Предыдущая точка")

            Button { vm.stopPlayback() } label: { Image(systemName: "stop.fill") }
                .buttonStyle(CircleIconButtonStyle(diameter: 40))
                .disabled(state == .idle)
                .accessibilityLabel("Стоп")

            Button { vm.togglePlayPause() } label: {
                Image(systemName: state == .running ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(CircleIconButtonStyle(diameter: 56, prominent: true))
            .disabled(!hasRoute)
            .accessibilityLabel(state == .running ? "Пауза" : (state == .paused ? "Продолжить" : "Старт"))

            Button { vm.stepForward() } label: { Image(systemName: "forward.end.fill") }
                .buttonStyle(CircleIconButtonStyle(diameter: 40))
                .disabled(!canStep || state == .finished)
                .accessibilityLabel("Следующая точка")

            Menu {
                ForEach(AppPreferences.timeScales, id: \.self) { scale in
                    Button {
                        vm.setTimeScale(scale)
                    } label: {
                        if scale == vm.preferences.timeScale {
                            Label("×\(PlannerViewModel.scaleLabel(scale))", systemImage: "checkmark")
                        } else {
                            Text("×\(PlannerViewModel.scaleLabel(scale))")
                        }
                    }
                }
            } label: {
                Text("×\(PlannerViewModel.scaleLabel(vm.preferences.timeScale))")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.surfaceStrong))
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .disabled(vm.activeSource != .simulation)
            .accessibilityLabel("Ускорение симуляции")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatusDot: View {
    let state: PlaybackState

    private var color: Color {
        switch state {
        case .idle: Theme.tertiaryText
        case .running: Theme.success
        case .paused: Theme.warning
        case .finished: Theme.accent
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .shadow(color: color.opacity(0.8), radius: state == .running ? 6 : 0)
            .animation(.easeInOut(duration: 0.3), value: state)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
