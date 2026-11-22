import SwiftUI

struct ProgressPanelView: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        let p = vm.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        ProgressRing(fraction: p.coverageFraction, lineWidth: 14)
                        VStack(spacing: 2) {
                            Text(Formatters.percent(p.coverageFraction))
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                            Text("покрытие")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .frame(width: 136, height: 136)

                    VStack(alignment: .leading, spacing: 12) {
                        metric("Маршрут", Formatters.percent(p.routeFraction))
                        metric("Площадь", Formatters.area(p.coveredArea))
                        metric("Состояние", p.state.title)
                    }
                    Spacer(minLength: 0)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Прогресс маршрута")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(p.processed) из \(p.total)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    GradientProgressBar(fraction: p.routeFraction, height: 10)
                }
                .glassCard()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(title: "Обработано точек", value: "\(p.processed)/\(p.total)", systemImage: "mappin.circle.fill")
                    StatTile(title: "ETA", value: p.eta.map(Formatters.duration) ?? "—", systemImage: "clock.fill", tint: Theme.accentSecondary)
                    StatTile(title: "Пройдено", value: Formatters.distance(p.distanceDone), systemImage: "figure.walk", tint: Theme.success)
                    StatTile(title: "Всего", value: Formatters.distance(p.distanceTotal), systemImage: "ruler.fill")
                    StatTile(title: vm.activeSource == .simulation ? "Время (сим.)" : "Время", value: Formatters.duration(p.elapsed), systemImage: "stopwatch.fill", tint: Theme.warning)
                    StatTile(title: "Скорость", value: Formatters.speed(p.speed), systemImage: "speedometer", tint: Theme.accentSecondary)
                }

                if let eta = p.eta, p.state == .running {
                    Label("Окончание около \(Formatters.clock.string(from: Date().addingTimeInterval(eta)))", systemImage: "flag.checkered")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                }

                controls(state: p.state)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white).contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private func controls(state: PlaybackState) -> some View {
        switch state {
        case .idle, .finished:
            Button {
                vm.startPlayback()
            } label: {
                Label(state == .finished ? "Запустить заново" : "Запустить", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(vm.route == nil)
        case .running:
            HStack(spacing: 10) {
                Button { vm.pausePlayback() } label: { Label("Приостановить", systemImage: "pause.fill") }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.warning))
                Button { vm.stopPlayback() } label: { Label("Стоп", systemImage: "stop.fill") }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                    .frame(width: 110)
            }
        case .paused:
            HStack(spacing: 10) {
                Button { vm.resumePlayback() } label: { Label("Возобновить", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                Button { vm.stopPlayback() } label: { Label("Стоп", systemImage: "stop.fill") }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                    .frame(width: 110)
            }
        }
    }
}
