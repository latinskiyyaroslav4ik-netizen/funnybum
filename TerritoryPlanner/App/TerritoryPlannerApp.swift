import SwiftUI

@main
struct TerritoryPlannerApp: App {
    @State private var viewModel = PlannerViewModel()

    var body: some Scene {
        WindowGroup {
            PlannerRootView()
                .environment(viewModel)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
