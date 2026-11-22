import SwiftUI

/// Map-first layout: full-screen map, floating tools on top and a control panel that is a
/// persistent bottom sheet on iPhone and a floating sidebar on iPad / large widths.
struct PlannerRootView: View {
    @Environment(PlannerViewModel.self) private var vm
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var detent: PresentationDetent = PlannerRootView.collapsedDetent

    static let collapsedDetent: PresentationDetent = .height(178)

    private var usesSidebar: Bool { sizeClass == .regular }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlannerMapView()
                .ignoresSafeArea()

            MapOverlayControls(leadingInset: usesSidebar ? 424 : 0)
        }
        .overlay(alignment: .topLeading) {
            if usesSidebar {
                ControlPanel()
                    .frame(width: 400)
                    .frame(maxHeight: .infinity)
                    .floatingGlass(cornerRadius: 28)
                    .padding(.leading, 16)
                    .padding(.vertical, 16)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .sheet(isPresented: Binding(get: { !usesSidebar }, set: { _ in })) {
            ControlPanel()
                .environment(vm)
                .presentationDetents([Self.collapsedDetent, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(30)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .preferredColorScheme(.dark)
        }
        .animation(Theme.spring, value: usesSidebar)
        .onChange(of: vm.settings) {
            vm.settingsDidChange()
            vm.schedulePersist()
        }
        .onChange(of: vm.preferences) {
            vm.schedulePersist()
        }
        .onChange(of: vm.selectedTab) {
            // Opening a content tab from the collapsed sheet should reveal it.
            if detent == Self.collapsedDetent { detent = .medium }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { vm.persist() }
        }
        .sensoryFeedback(.selection, trigger: vm.hapticTick) { _, _ in vm.preferences.haptics }
        .sensoryFeedback(.success, trigger: vm.finishTick) { _, _ in vm.preferences.haptics }
    }
}
