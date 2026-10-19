import Observation

@Observable
final class AppState {
    var selectedTab: AppTab = .home
}

enum AppTab: Hashable {
    case home
    case settings
}
