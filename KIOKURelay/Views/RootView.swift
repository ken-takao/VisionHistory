import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case home
        case scan
        case search
        case system
    }

    @State private var selection: Tab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(openScanner: { selection = .scan })
                .tag(Tab.home)
                .tabItem { Label("ホーム", systemImage: "sparkles") }

            ScannerView()
                .tag(Tab.scan)
                .tabItem { Label("記憶する", systemImage: "viewfinder") }

            SearchMemoriesView()
                .tag(Tab.search)
                .tabItem { Label("探す", systemImage: "magnifyingglass") }

            SystemView()
                .tag(Tab.system)
                .tabItem { Label("接続", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .tint(AppTheme.lime)
    }
}
