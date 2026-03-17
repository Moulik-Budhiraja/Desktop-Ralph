import AppKit
import Foundation

@MainActor
final class PenguinOverlayController {
    static let shared = PenguinOverlayController()

    private let spriteWindowController = RalphSpriteWindowController.make()

    func showAction(
        _ statement: OXAStatement,
        targets: [ActionTargetDescriptor],
        dwellTime: TimeInterval = 0.2)
    {
        guard let spriteWindowController else { return }

        switch statement {
        case .sendDrag:
            if let sourceFrame = targets.first?.frame {
                spriteWindowController.walk(to: sourceFrame)
                spriteWindowController.dwell(for: dwellTime / 2)
            }
            if let destinationFrame = targets.dropFirst().first?.frame {
                spriteWindowController.walk(to: destinationFrame)
                spriteWindowController.dwell(for: dwellTime / 2)
            }
        case .sendClick,
             .sendRightClick,
             .sendText,
             .sendTextAsKeys,
             .sendHotkey,
             .sendScroll,
             .sendScrollIntoView,
             .readAttribute:
            if let targetFrame = targets.first?.frame {
                spriteWindowController.walk(to: targetFrame)
                spriteWindowController.dwell(for: dwellTime)
            }
        case let .open(app):
            self.showOpenWindow(for: app, spriteWindowController: spriteWindowController, dwellTime: dwellTime)
        case .sleep, .close:
            return
        }
    }

    private func showOpenWindow(
        for app: String,
        spriteWindowController: RalphSpriteWindowController,
        dwellTime: TimeInterval)
    {
        let desktop = RalphSpriteWindowController.desktopFrame()
        let destinationFrame = RalphWindowPullOverlay.destinationFrame(in: desktop)
        let currentPoint = spriteWindowController.window?.frame.origin ?? desktop.origin
        let edge: RalphWindowPullOverlay.Edge = currentPoint.x < desktop.midX ? .left : .right
        let startFrame = RalphWindowPullOverlay.startFrame(
            for: destinationFrame,
            edge: edge,
            in: desktop)

        spriteWindowController.pullWindow(
            title: app,
            edge: edge,
            windowStartFrame: startFrame,
            windowDestinationFrame: destinationFrame,
            dwellTime: dwellTime)
    }
}

@MainActor
struct OverlayActionExecutionMiddleware: ActionExecutionMiddleware {
    let dwellTime: TimeInterval

    init(dwellTime: TimeInterval = 0.2) {
        self.dwellTime = dwellTime
    }

    func willPerform(_ context: ActionExecutionContext) throws {
        PenguinOverlayController.shared.showAction(
            context.statement,
            targets: context.targets,
            dwellTime: self.dwellTime)
    }
}
