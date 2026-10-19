import Observation

@Observable
final class HomeViewModel {
    var tapCount = 0

    var message: String {
        tapCount == 0 ? "Welcome to Xpeet" : "Tapped \(tapCount) time\(tapCount == 1 ? "" : "s")"
    }

    func increment() {
        tapCount += 1
    }
}
