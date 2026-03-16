import AppKit
import Foundation
import OSXQuery

@MainActor
protocol PenguinStatementExecuting: AnyObject {
    func preflight(program: OXAProgram) throws
    func execute(_ statement: OXAStatement) throws -> PenguinActionExecutor.StatementExecutionResult
    func describe(_ statement: OXAStatement) -> String
}

@MainActor
class PenguinActionExecutor: PenguinStatementExecuting {
    struct StatementExecutionResult {
        let readOutput: String?
        static let none = StatementExecutionResult(readOutput: nil)
    }

    private let refStore: SelectorActionRefStore

    init(refStore: SelectorActionRefStore) {
        self.refStore = refStore
    }

    func preflight(program: OXAProgram) throws {
        let references = program.statements.compactMap(ActionVisualizationPlanner.targetReference(of:))
        guard !references.isEmpty else { return }

        if let snapshotPID = self.refStore.snapshotAppPID, snapshotPID > 0 {
            _ = self.ensureFrontmost(pid: snapshotPID)
            Thread.sleep(forTimeInterval: 0.08)
            return
        }

        let pids = try Set(references.compactMap { try self.resolveElementReference($0).pid() })
        if pids.count > 1 {
            throw OXAActionError.runtime("Action program references multiple apps. Re-run the query and target one app.")
        }
        if let pid = pids.first {
            _ = self.ensureFrontmost(pid: pid)
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    func execute(_ statement: OXAStatement) throws -> StatementExecutionResult {
        switch statement {
        case let .sendText(text, targetRef):
            let target = try self.resolveElementReference(targetRef)
            try self.focusTargetForInput(target, targetRef: targetRef)
            guard target.setValue(text, forAttribute: AXAttributeNames.kAXValueAttribute) else {
                throw OXAActionError.runtime("Failed to set AXValue on target \(targetRef).")
            }
            return .none

        case let .sendTextAsKeys(text, targetRef):
            let target = try self.resolveElementReference(targetRef)
            try self.focusTargetForInput(target, targetRef: targetRef)
            let targetPID = self.refStore.snapshotAppPID ?? target.pid()
            guard let targetPID else {
                throw OXAActionError.runtime("Unable to determine owning app for target \(targetRef).")
            }
            try InputDriver.type(text, targetPid: targetPID)
            return .none

        case let .sendClick(targetRef):
            try self.click(reference: targetRef, button: .left)
            return .none

        case let .sendRightClick(targetRef):
            try self.click(reference: targetRef, button: .right)
            return .none

        case let .sendDrag(sourceRef, targetRef):
            let source = try self.resolveElementReference(sourceRef)
            let target = try self.resolveElementReference(targetRef)
            guard let sourceCenter = self.centerPoint(for: source, reference: sourceRef) else {
                throw OXAActionError.runtime("Unable to resolve frame for drag source \(sourceRef).")
            }
            guard let targetCenter = self.centerPoint(for: target, reference: targetRef) else {
                throw OXAActionError.runtime("Unable to resolve frame for drag target \(targetRef).")
            }
            try InputDriver.drag(from: sourceCenter, to: targetCenter, steps: 20, interStepDelay: 0.005)
            return .none

        case let .sendHotkey(chord, targetRef):
            let target = try self.resolveElementReference(targetRef)
            let targetPID = self.refStore.snapshotAppPID ?? target.pid()
            guard let targetPID else {
                throw OXAActionError.runtime("Unable to determine owning app for target \(targetRef).")
            }
            try InputDriver.hotkey(keys: chord.modifiers + [chord.baseKey], targetPid: targetPID)
            return .none

        case let .sendScroll(direction, targetRef):
            let target = try self.resolveElementReference(targetRef)
            guard let center = self.centerPoint(for: target, reference: targetRef) else {
                throw OXAActionError.runtime("Unable to resolve frame for scroll target \(targetRef).")
            }
            try self.scroll(direction: direction, at: center)
            return .none

        case let .sendScrollIntoView(targetRef):
            let target = try self.resolveElementReference(targetRef)
            try self.scrollIntoView(target, reference: targetRef)
            return .none

        case let .readAttribute(attributeName, targetRef):
            let target = try self.resolveElementReference(targetRef)
            guard let value = SelectorAttributeFormatter.attributeValue(for: target, attributeName: attributeName) else {
                throw OXAActionError.runtime("Attribute '\(attributeName)' has no readable value on \(targetRef).")
            }
            return StatementExecutionResult(readOutput: value)

        case let .sleep(milliseconds):
            guard milliseconds >= 0 else {
                throw OXAActionError.runtime("Sleep duration must be non-negative.")
            }
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
            return .none

        case let .open(app):
            try self.openApplication(app)
            return .none

        case let .close(app):
            try self.closeApplication(app)
            return .none
        }
    }

    func describe(_ statement: OXAStatement) -> String {
        switch statement {
        case let .sendText(text, targetRef):
            "send text \"\(text)\" to \(targetRef)"
        case let .sendTextAsKeys(text, targetRef):
            "send text \"\(text)\" as keys to \(targetRef)"
        case let .sendClick(targetRef):
            "send click to \(targetRef)"
        case let .sendRightClick(targetRef):
            "send right click to \(targetRef)"
        case let .sendDrag(sourceRef, targetRef):
            "send drag \(sourceRef) to \(targetRef)"
        case let .sendHotkey(chord, targetRef):
            "send hotkey \((chord.modifiers + [chord.baseKey]).joined(separator: "+")) to \(targetRef)"
        case let .sendScroll(direction, targetRef):
            "send scroll \(direction.rawValue) to \(targetRef)"
        case let .sendScrollIntoView(targetRef):
            "send scroll to \(targetRef)"
        case let .readAttribute(attributeName, targetRef):
            "read \(attributeName) from \(targetRef)"
        case let .sleep(milliseconds):
            "sleep \(milliseconds)"
        case let .open(app):
            "open \"\(app)\""
        case let .close(app):
            "close \"\(app)\""
        }
    }

    private func resolveElementReference(_ reference: String) throws -> Element {
        guard self.refStore.hasSnapshot else {
            throw OXAActionError.noSnapshot
        }
        guard let element = self.refStore.element(for: reference) else {
            throw OXAActionError.unknownElementReference(reference)
        }
        return element
    }

    private func focusTargetForInput(_ target: Element, targetRef: String) throws {
        if let pid = self.refStore.snapshotAppPID ?? target.pid() {
            _ = self.ensureFrontmost(pid: pid)
        }
        _ = target.setValue(true, forAttribute: AXAttributeNames.kAXFocusedAttribute)
        Thread.sleep(forTimeInterval: 0.05)
        guard target.isFocused() == true || target.setValue(true, forAttribute: AXAttributeNames.kAXValueAttribute) else {
            return
        }
        _ = targetRef
    }

    private func click(reference: String, button: MouseButton) throws {
        let target = try self.resolveElementReference(reference)
        guard let center = self.centerPoint(for: target, reference: reference) else {
            throw OXAActionError.runtime("Unable to resolve frame for click target \(reference).")
        }
        try InputDriver.click(at: center, button: button)
    }

    private func centerPoint(for element: Element, reference: String) -> CGPoint? {
        (self.refStore.frame(for: reference) ?? element.frame()).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    private func scroll(direction: OXAScrollDirection, at point: CGPoint) throws {
        switch direction {
        case .up:
            try InputDriver.scroll(deltaY: 120, at: point)
        case .down:
            try InputDriver.scroll(deltaY: -120, at: point)
        case .left:
            try InputDriver.scroll(deltaX: -120, deltaY: 0, at: point)
        case .right:
            try InputDriver.scroll(deltaX: 120, deltaY: 0, at: point)
        }
    }

    private func scrollIntoView(_ element: Element, reference: String) throws {
        if element.isActionSupported("AXScrollToVisible") {
            try element.performAction("AXScrollToVisible")
            return
        }
        guard let center = self.centerPoint(for: element, reference: reference) else { return }
        try InputDriver.scroll(deltaY: -120, at: center)
    }

    private func ensureFrontmost(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    private func openApplication(_ identifier: String) throws {
        let workspace = NSWorkspace.shared
        let url = workspace.urlForApplication(withBundleIdentifier: identifier).flatMap { $0 } ??
            workspace.fullPath(forApplication: identifier).map { URL(fileURLWithPath: $0) }
        guard let url else {
            throw OXAActionError.runtime("Could not resolve application '\(identifier)'.")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?
        workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            launchError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let launchError {
            throw OXAActionError.runtime("Failed to open '\(identifier)': \(launchError.localizedDescription)")
        }
    }

    private func closeApplication(_ identifier: String) throws {
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first ??
            RunningApplicationHelper.allApplications().first(where: {
                $0.localizedName?.caseInsensitiveCompare(identifier) == .orderedSame
            })
        guard let app else {
            throw OXAActionError.runtime("Application '\(identifier)' is not running.")
        }
        guard app.terminate() else {
            throw OXAActionError.runtime("Failed to terminate '\(identifier)'.")
        }
    }
}
