import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(PlannerViewModel.self) private var vm
    @State private var confirmReset = false

    var body: some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Map
                VStack(alignment: .leading, spacing: 12) {
                    PanelSectionHeader("Карта", systemImage: "map")
                    VStack(alignment: .leading, spacing: 14) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(MapAppearance.allCases) { style in
                                    Chip(title: style.title, isSelected: vm.preferences.mapAppearance == style) {
                                        vm.preferences.mapAppearance = style
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        ToggleRow(title: "Показывать точки", subtitle: "Для маршрутов до 400 точек", isOn: $vm.preferences.showWaypoints)
                        ToggleRow(title: "Показывать покрытие", isOn: $vm.preferences.showCoverage)
                        ToggleRow(title: "Следовать за маркером", subtitle: "Камера ведёт текущую позицию", isOn: $vm.preferences.followMarker)
                    }
                    .glassCard()
                }

                // Position source
                VStack(alignment: .leading, spacing: 12) {
                    PanelSectionHeader("Источник позиции", systemImage: "location.viewfinder")
                    VStack(spacing: 10) {
                        ForEach(LocationSource.allCases) { source in
                            SourceCard(source: source, isSelected: vm.preferences.locationSource == source) {
                                guard vm.preferences.locationSource != source else { return }
                                vm.stopPlayback()
                                vm.preferences.locationSource = source
                                vm.log("Источник позиции: \(source.title)")
                                if source == .device { vm.location.requestAuthorization() }
                            }
                        }
                        HStack {
                            Text("Доступ к геопозиции")
                                .font(.subheadline)
                            Spacer()
                            Text(vm.location.statusTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(vm.location.isAuthorized ? Theme.success : Theme.warning)
                        }
                        if vm.location.authorizationStatus == .notDetermined {
                            Button("Запросить доступ") { vm.location.requestAuthorization() }
                                .buttonStyle(SecondaryButtonStyle(tint: Theme.accent))
                        } else if vm.location.authorizationStatus == .denied || vm.location.authorizationStatus == .restricted {
                            Button("Открыть настройки iOS") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.warning))
                        }
                    }
                    .glassCard()
                }

                // Xcode integration
                VStack(alignment: .leading, spacing: 12) {
                    PanelSectionHeader("Тестирование в Xcode", systemImage: "hammer")
                    VStack(alignment: .leading, spacing: 10) {
                        step(1, "Экспортируйте маршрут в формате «Xcode (wpt + time)» и добавьте .gpx в проект тестируемого приложения.")
                        step(2, "Запустите приложение из Xcode и выберите файл в Debug ▸ Simulate Location — Core Location начнёт выдавать точки маршрута.")
                        step(3, "Для iOS Simulator можно вместо этого выполнить команду simctl в Терминале Mac.")
                        step(4, "Переключите источник на «Core Location», чтобы это приложение сверяло реальное воспроизведение с планом.")
                        HStack(spacing: 10) {
                            Button {
                                vm.copySimctlCommand()
                            } label: {
                                Label("simctl start", systemImage: "terminal")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(vm.route == nil)
                            Button {
                                UIPasteboard.general.string = SimctlCommandBuilder.clearCommand
                                vm.log("Команда simctl clear скопирована", level: .success)
                            } label: {
                                Label("simctl clear", systemImage: "xmark.circle")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .glassCard()
                }

                // Behaviour
                VStack(alignment: .leading, spacing: 12) {
                    PanelSectionHeader("Поведение", systemImage: "gearshape.2")
                    VStack(spacing: 14) {
                        ToggleRow(title: "Автопредпросмотр", subtitle: "Перестраивать маршрут при изменении параметров", isOn: $vm.preferences.autoRegenerate)
                        ToggleRow(title: "Не гасить экран", subtitle: "Во время воспроизведения", isOn: $vm.preferences.keepScreenAwake)
                        ToggleRow(title: "Тактильный отклик", isOn: $vm.preferences.haptics)
                    }
                    .glassCard()
                }

                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("Сбросить всё", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                .confirmationDialog("Сбросить маршрут, точки и настройки?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Сбросить", role: .destructive) { vm.resetEverything() }
                }

                Text(versionString)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Territory Planner \(version) (\(build))"
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SourceCard: View {
    let source: LocationSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: source == .simulation ? "play.rectangle.on.rectangle" : "location.fill.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black : Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14))))
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(source.subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.accent : Theme.tertiaryText)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.5) : Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: isSelected)
    }
}
