import AppKit
import Foundation

@MainActor
final class PenguinOverlayController {
    static let shared = PenguinOverlayController()

    private var bubbleMessage = RalphSpriteView.defaultBubbleMessage
    private lazy var spriteWindowController = RalphSpriteWindowController.make(bubbleMessage: self.bubbleMessage)

    func setBubbleMessage(_ message: String?) {
        let resolvedMessage = Self.normalizeBubbleMessage(message)
        guard self.bubbleMessage != resolvedMessage else { return }
        self.bubbleMessage = resolvedMessage
        self.spriteWindowController?.updateBubbleMessage(resolvedMessage)
    }

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
        case .sendClick:
            if let targetFrame = targets.first?.frame {
                spriteWindowController.click(targetFrame: targetFrame)
            }
        case .sendRightClick,
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

    private static func normalizeBubbleMessage(_ message: String?) -> String {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedMessage, !trimmedMessage.isEmpty else {
            return RalphSpriteView.defaultBubbleMessage
        }
        return trimmedMessage
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
