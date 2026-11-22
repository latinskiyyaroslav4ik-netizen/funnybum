import SwiftUI

/// Floating tools over the map: tap-mode switcher, contextual hint and camera shortcuts.
struct MapOverlayControls: View {
    @Environment(PlannerViewModel.self) private var vm
    var leadingInset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TapModeSwitcher()
                Spacer(minLength: 0)
                CameraButtons()
            }
            HintPill(text: vm.tapMode.hint, systemImage: vm.tapMode.systemImage)
                .id(vm.tapMode)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))

            if vm.tapMode == .customPoint {
                CustomDrawingBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.leading, 16 + leadingInset)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .animation(Theme.spring, value: vm.tapMode)
    }
}

private struct TapModeSwitcher: View {
    @Environment(PlannerViewModel.self) private var vm
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MapTapMode.allCases) { mode in
                Button {
                    withAnimation(Theme.spring) { vm.tapMode = mode }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(width: 58, height: 46)
                    .foregroundStyle(vm.tapMode == mode ? Color.black : Color.white.opacity(0.85))
                    .background {
                        if vm.tapMode == mode {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.accent)
                                .matchedGeometryEffect(id: "mode", in: selection)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(vm.tapMode == mode ? .isSelected : [])
            }
        }
        .padding(4)
        .floatingGlass(cornerRadius: 16)
    }
}

private struct CameraButtons: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            button("scope", label: "Показать область") { vm.focusArea() }
                .disabled(vm.areaCenter == nil)
            Divider().frame(width: 28).overlay(Theme.hairline)
            button("arrow.up.left.and.arrow.down.right", label: "Показать маршрут") { vm.focusRoute() }
                .disabled(vm.route == nil)
            Divider().frame(width: 28).overlay(Theme.hairline)
            Menu {
                Picker("Стиль карты", selection: Binding(
                    get: { vm.preferences.mapAppearance },
                    set: { vm.preferences.mapAppearance = $0 }
                )) {
                    ForEach(MapAppearance.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Покрытие", isOn: Binding(get: { vm.preferences.showCoverage }, set: { vm.preferences.showCoverage = $0 }))
                Toggle("Точки маршрута", isOn: Binding(get: { vm.preferences.showWaypoints }, set: { vm.preferences.showWaypoints = $0 }))
                Toggle("Следовать за маркером", isOn: Binding(get: { vm.preferences.followMarker }, set: { vm.preferences.followMarker = $0 }))
            } label: {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Слои карты")
        }
        .floatingGlass(cornerRadius: 14)
    }

    private func button(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct HintPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
            Text(text)
                .foregroundStyle(.white.opacity(0.9))
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .floatingGlass(cornerRadius: 20)
    }
}

private struct CustomDrawingBar: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 12) {
            Text("\(vm.customPoints.count) опорных")
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            Divider().frame(height: 18)
            Button {
                withAnimation(Theme.spring) { vm.undoLastCustomPoint() }
            } label: {
                Label("Отменить", systemImage: "arrow.uturn.backward")
            }
            .disabled(vm.customPoints.isEmpty)
            Button(role: .destructive) {
                withAnimation(Theme.spring) { vm.clearCustomPoints() }
            } label: {
                Label("Очистить", systemImage: "trash")
            }
            .disabled(vm.customPoints.isEmpty)
        }
        .font(.footnote.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .floatingGlass(cornerRadius: 20)
    }
}
