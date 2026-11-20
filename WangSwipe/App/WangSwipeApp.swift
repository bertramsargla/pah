import SwiftUI

@main
struct WangSwipeApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.light)
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
                .tabItem { Label("Wardrobe", systemImage: "hanger") }
            LikedView()
                .tabItem { Label("Closet", systemImage: "heart") }
            SettingsView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
        }
        .tint(Retro.navy)
        .toolbarBackground(Retro.lavender, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
