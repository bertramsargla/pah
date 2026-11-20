import SwiftUI

@main
struct WangSwipeApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.userPhoto == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .animation(.default, value: appModel.userPhoto == nil)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DeckView()
                .tabItem { Label("Discover", systemImage: "rectangle.stack") }
            LikedView()
                .tabItem { Label("Liked", systemImage: "heart") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
