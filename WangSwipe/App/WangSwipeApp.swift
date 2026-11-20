import SwiftUI

@main
struct WangSwipeApp: App {
    /// Created once. SwiftUI can re-create this struct, and `@State var x = AppModel()`
    /// would build (and throw away) a fresh model each time, re-running its setup.
    private static let sharedModel = AppModel()
    @State private var appModel = WangSwipeApp.sharedModel

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    /// The skin whose hanger screen has finished. Until it matches the current
    /// skin, the hanger screen covers everything; that way a skin change shows
    /// the hangers in the very same frame, with no flash of the new screens first.
    @State private var revealedSkin: Skin?
    private var showsLaunch: Bool { revealedSkin != appModel.settings.skin }
    @State private var tab = MainTab.wardrobe

    var body: some View {
        // Keep the drawing skin in step with the saved one before any screen draws.
        let _ = (Skin.current = appModel.settings.skin)
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
        // Runs at launch and again whenever the skin changes, so each new skin
        // opens on its own hanger screen. The hangers stay up a moment while
        // the screens behind them load.
        .task(id: appModel.settings.skin) {
            let skin = appModel.settings.skin
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { revealedSkin = skin }
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
