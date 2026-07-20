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

/// Registers the notification delegate before the first runloop tick — a tap on a
/// notification can cold-launch the app, and the delegate must exist by then or
/// the tap's response is dropped (SwiftUI's .task runs far too late for this).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationManager.shared.configure()
        return true
    }
}

@main
struct DXBParkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("automationVerified") private var automationVerified = false

    /// Built by hand so a store that fails to open recovers instead of
    /// fatalError-ing at launch (`.modelContainer(for:)` crashes on failure —
    /// on a device that means a permanent crash loop until reinstall).
    private let container: ModelContainer = {
        let schema = Schema([Session.self, Spot.self])
        if let container = try? ModelContainer(for: schema) { return container }
        // Store incompatible or corrupt: drop it and start fresh — losing local
        // history beats an unlaunchable app.
        let support = URL.applicationSupportDirectory
        for name in ["default.store", "default.store-wal", "default.store-shm"] {
            try? FileManager.default.removeItem(at: support.appending(path: name))
        }
        if let container = try? ModelContainer(for: schema) { return container }
        return try! ModelContainer(for: schema,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .preferredColorScheme(.light) // the M1 design language is warm-light
                .onOpenURL { url in
                    guard url.scheme == "dxbpark" else { return }
                    if url.host == "parked" || url.path.contains("parked") {
                        // From the Shortcuts automation, widget, or Siri
                        automationVerified = true // §13: setup success detected
                        router.openParked()
                    } else if url.host == "extend" || url.path.contains("extend") {
                        // Widget countdown tap — straight into the +1 hour flow
                        router.requestExtend()
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasOnboarded },
                    set: { if !$0 { hasOnboarded = true } }
                )) {
                    OnboardingView { hasOnboarded = true }
                }
                .task {
                    NotificationManager.shared.onOpenParked = { [weak router] in
                        router?.openParked()
                    }
                    NotificationManager.shared.onExtendRequested = { [weak router] in
                        router?.requestExtend()
                    }
                }
        }
        .modelContainer(container)
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
