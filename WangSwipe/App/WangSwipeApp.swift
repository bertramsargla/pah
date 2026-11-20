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
    @State private var showsLaunch = true
    @State private var tab = MainTab.wardrobe

    var body: some View {
        ZStack {
            Group {
                if appModel.userPhoto == nil {
                    OnboardingView()
                } else {
                    MainTabView(selection: $tab)
                }
            }
            .animation(.default, value: appModel.userPhoto == nil)
            // Rebuild every screen when the skin changes so they all pick up its colors.
            .id(appModel.settings.skin)

            if showsLaunch {
                HangerLaunchView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Dark skins, and the dark hanger screen, need the light status bar.
        .preferredColorScheme(showsLaunch || appModel.settings.skin.isDark ? .dark : .light)
        .task {
            // The hangers stay up a moment while the wardrobe loads behind them.
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.5)) { showsLaunch = false }
        }
    }
}

enum MainTab: Hashable {
    case wardrobe, closet, setup
}

struct MainTabView: View {
    @Binding var selection: MainTab

    var body: some View {
        TabView(selection: $selection) {
            WardrobeView()
                .tabItem { Label("Wardrobe", systemImage: "hanger") }
                .tag(MainTab.wardrobe)
            LikedView()
                .tabItem { Label("Closet", systemImage: "heart") }
                .tag(MainTab.closet)
            SettingsView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
                .tag(MainTab.setup)
        }
        .tint(Retro.tint)
    }
}
