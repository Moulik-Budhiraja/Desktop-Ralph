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
        case .sleep, .open, .close:
            return
        }
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
