import SwiftUI
import SwiftData

@Observable
final class AppRouter {
    var selectedTab: Tab = .home
    /// Incremented every time dxbpark://parked fires — Home re-runs the decision pipeline.
    var parkedTrigger = 0
    /// Incremented when a notification's "+1 hour" action fires — Home opens the extend flow.
    var extendTrigger = 0

    enum Tab: Hashable { case home, spots, settings }

    func openParked() {
        selectedTab = .home
        parkedTrigger += 1
    }

    func requestExtend() {
        selectedTab = .home
        extendTrigger += 1
    }
}

@main
struct DXBParkApp: App {
    @State private var router = AppRouter()
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("automationVerified") private var automationVerified = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .preferredColorScheme(.light) // the M1 design language is warm-light
                .onOpenURL { url in
                    // dxbpark://parked — from the Shortcuts automation, widget, or Siri
                    if url.scheme == "dxbpark",
                       url.host == "parked" || url.path.contains("parked") {
                        automationVerified = true // §13: setup success detected
                        router.openParked()
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasOnboarded },
                    set: { if !$0 { hasOnboarded = true } }
                )) {
                    OnboardingView { hasOnboarded = true }
                }
                .task {
                    NotificationManager.shared.configure()
                    NotificationManager.shared.onOpenParked = { [weak router] in
                        router?.openParked()
                    }
                    NotificationManager.shared.onExtendRequested = { [weak router] in
                        router?.requestExtend()
                    }
                }
        }
        .modelContainer(for: [Session.self, Spot.self])
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "car.fill") }
                .tag(AppRouter.Tab.home)
            SpotsView()
                .tabItem { Label("My Spots", systemImage: "mappin.and.ellipse") }
                .tag(AppRouter.Tab.spots)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppRouter.Tab.settings)
        }
        .tint(Theme.coral)
        .onReceive(NotificationCenter.default.publisher(for: .parkNowIntent)) { _ in
            router.openParked()
        }
        .onReceive(NotificationCenter.default.publisher(for: .extendParkingIntent)) { _ in
            router.requestExtend()
        }
    }
}
