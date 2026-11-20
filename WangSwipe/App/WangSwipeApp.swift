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
    @State private var showsLaunch = true

    var body: some View {
        ZStack {
            Group {
                if appModel.userPhoto == nil {
                    OnboardingView()
                } else {
                    MainTabView()
                }
            }
            .animation(.default, value: appModel.userPhoto == nil)

            if showsLaunch {
                HangerLaunchView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            // The hangers stay up a moment while the wardrobe loads behind them.
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.5)) { showsLaunch = false }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            WardrobeView()
                .tabItem { Label("Wardrobe", systemImage: "hanger") }
            LikedView()
                .tabItem { Label("Closet", systemImage: "heart") }
            SettingsView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
        }
        .tint(Retro.navy)
    }
}
