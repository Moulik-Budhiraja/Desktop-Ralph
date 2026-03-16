import AppKit
import Foundation

struct ActionVisualizationRequest {
    let statement: OXAStatement
    let targetFrame: CGRect?
    let sourceFrame: CGRect?
    let leadInDuration: Duration
}

protocol ActionVisualizer: AnyObject {
    @MainActor
    func visualize(_ request: ActionVisualizationRequest) async throws

    @MainActor
    func flashAction() async

    @MainActor
    func idle() async
}

enum ActionVisualizationPlanner {
    static func isVisualized(_ statement: OXAStatement) -> Bool {
        switch statement {
        case .sendText, .sendTextAsKeys, .sendClick, .sendRightClick, .sendDrag, .sendHotkey, .sendScroll,
             .sendScrollIntoView:
            true
        case .readAttribute, .sleep, .open, .close:
            false
        }
    }

    static func leadInDuration(
        current: OXAStatement,
        next: OXAStatement?) -> Duration
    {
        if let next, targetReference(of: current) == targetReference(of: next) {
            return .milliseconds(120)
        }
        return .milliseconds(180)
    }

    static func targetReference(of statement: OXAStatement) -> String? {
        switch statement {
        case let .sendText(_, targetRef),
             let .sendTextAsKeys(_, targetRef),
             let .sendClick(targetRef),
             let .sendRightClick(targetRef),
             let .sendHotkey(_, targetRef),
             let .sendScroll(_, targetRef),
             let .sendScrollIntoView(targetRef),
             let .readAttribute(_, targetRef):
            targetRef
        case let .sendDrag(_, targetRef):
            targetRef
        case .sleep, .open, .close:
            nil
        }
    }

    static func sourceReference(of statement: OXAStatement) -> String? {
        if case let .sendDrag(sourceRef, _) = statement {
            return sourceRef
        }
        return nil
    }

    static func clampedCenter(for frame: CGRect, in bounds: CGRect) -> CGPoint {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return CGPoint(
            x: min(max(center.x, bounds.minX), bounds.maxX),
            y: min(max(center.y, bounds.minY), bounds.maxY))
    }

    static func screen(containing frame: CGRect?) -> NSScreen? {
        guard let frame else { return NSScreen.main }
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) ?? NSScreen.main
    }
}

@MainActor
final class PenguinActionVisualizer: ActionVisualizer {
    private let controller = OverlayWindowController()
    private lazy var animator = PenguinAnimator(controller: self.controller)

    func visualize(_ request: ActionVisualizationRequest) async throws {
        switch request.statement {
        case .sendDrag:
            if let sourceFrame = request.sourceFrame {
                try await self.animator.move(to: sourceFrame, leadIn: request.leadInDuration / 2)
            }
            if let targetFrame = request.targetFrame {
                try await self.animator.move(to: targetFrame, leadIn: request.leadInDuration / 2)
            }
        default:
            if let targetFrame = request.targetFrame {
                try await self.animator.move(to: targetFrame, leadIn: request.leadInDuration)
            }
        }
    }

    func flashAction() async {
        await self.animator.flash()
    }

    func idle() async {
        await self.animator.idle()
    }
}
