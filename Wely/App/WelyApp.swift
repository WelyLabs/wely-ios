import SwiftUI

@main
struct WelyApp: App {
    @UIApplicationDelegateAdaptor(WelyAppDelegate.self) private var appDelegate
    @State private var app: AppModel

    init() {
        WelyAppearance.apply()
        #if DEBUG
        // `-WelyDemo`: signed in against a pretend gateway, no backend needed.
        if ProcessInfo.processInfo.arguments.contains("-WelyDemo") {
            _app = State(initialValue: AppModel.demo())
            Self.applyLaunchRoute(to: app)
            return
        }
        #endif
        _app = State(initialValue: AppModel(session: AuthSession()))
        #if DEBUG
        Self.applyLaunchRoute(to: app)
        #endif
    }

    #if DEBUG
    /// `-WelyTab feed|messages|social|profile` and `-WelyOpen /event/<id>`: start on a given
    /// screen, to check it in the simulator without tapping through.
    private static func applyLaunchRoute(to app: AppModel) {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "WelyTab") {
        case "feed": app.selectedTab = .feed
        case "messages": app.selectedTab = .messages
        case "social": app.selectedTab = .social
        case "profile": app.selectedTab = .profile
        default: break
        }
        if let path = defaults.string(forKey: "WelyOpen"), let destination = AppDestination(webPath: path) {
            let tab = app.selectedTab
            app.open(destination)
            if case .event = destination { app.selectedTab = tab }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.session)
                .tint(Theme.primary)
                .font(.wely.body)
                .preferredColorScheme(app.theme.colorScheme)
                .onOpenURL { url in
                    // wely://event/<id>, or a shared web link to the same path.
                    if let destination = AppDestination(webPath: url.host().map { "/\($0)\(url.path())" } ?? url.path()) {
                        app.open(destination)
                    }
                }
        }
    }
}
