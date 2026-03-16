import Foundation

@MainActor
final class PenguinAnimator {
    private let controller: OverlayWindowController

    init(controller: OverlayWindowController) {
        self.controller = controller
    }

    func move(to frame: CGRect, leadIn: Duration) async throws {
        let seconds = leadIn.timeInterval
        self.controller.moveIndicator(to: frame, duration: seconds)
        try await Task.sleep(for: leadIn)
    }

    func flash() async {
        self.controller.flashIndicator()
        try? await Task.sleep(for: .milliseconds(90))
    }

    func idle() async {
        self.controller.hideIndicator()
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(self.components.seconds) + TimeInterval(self.components.attoseconds) / 1_000_000_000_000_000_000
    }
}
