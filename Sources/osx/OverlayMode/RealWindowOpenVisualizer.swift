import AppKit
import Foundation
import OSXQuery

@MainActor
enum RealWindowOpenVisualizer {
    private static let appLaunchWaitTimeoutSeconds: TimeInterval = 2.0
    private static let windowCreationWaitTimeoutSeconds: TimeInterval = 1.5
    private static let pollIntervalSeconds: TimeInterval = 0.05

    static func openApplication(_ applicationIdentifier: String, dwellTime: TimeInterval = 0.2) -> Bool {
        guard let spriteWindowController = PenguinOverlayController.shared.spriteWindowController else {
            return false
        }

        guard let app = self.openApplicationInBackground(applicationIdentifier) else {
            PenguinOverlayController.shared.showSyntheticOpenWindow(for: applicationIdentifier, dwellTime: dwellTime)
            return false
        }

        guard let window = self.waitForCandidateWindow(in: app, timeout: self.windowCreationWaitTimeoutSeconds),
              let destinationFrame = window.frame(),
              self.prepareWindowForPull(window)
        else {
            PenguinOverlayController.shared.showSyntheticOpenWindow(for: applicationIdentifier, dwellTime: dwellTime)
            return false
        }

        let desktop = RalphSpriteWindowController.desktopFrame()
        let currentPoint = spriteWindowController.window?.frame.origin ?? desktop.origin
        let edge: RalphWindowPullOverlay.Edge = currentPoint.x < desktop.midX ? .left : .right
        let startFrame = RalphWindowPullOverlay.startFrame(
            for: destinationFrame,
            edge: edge,
            in: desktop)

        _ = window.setPosition(startFrame.origin)
        if let size = window.size(), size != startFrame.size {
            _ = window.setSize(startFrame.size)
        }

        _ = OXAExecutor.ensureApplicationFrontmost(
            pid: app.processIdentifier,
            targetBundleIdentifier: app.bundleIdentifier)
        _ = window.raiseWindow()

        spriteWindowController.pullLiveWindow(
            edge: edge,
            windowStartFrame: startFrame,
            windowDestinationFrame: destinationFrame,
            dwellTime: dwellTime)
        { frame in
            _ = window.setPosition(frame.origin)
            if let size = window.size(), size != frame.size {
                _ = window.setSize(frame.size)
            }
        }
        return true
    }

    private static func openApplicationInBackground(_ applicationIdentifier: String) -> NSRunningApplication? {
        if let runningApp = self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated }) {
            if !self.applicationHasAnyWindow(runningApp) {
                _ = self.reopenWithoutActivation(runningApp)
                _ = self.waitForAnyWindow(in: runningApp, timeout: Self.windowCreationWaitTimeoutSeconds)
            }
            return runningApp
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if self.looksLikeBundleIdentifier(applicationIdentifier) {
            process.arguments = ["-g", "-b", applicationIdentifier]
        } else {
            process.arguments = ["-g", "-a", applicationIdentifier]
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        guard let app = self.waitForRunningApplication(
            matching: applicationIdentifier,
            timeout: Self.appLaunchWaitTimeoutSeconds)
        else {
            return nil
        }

        _ = self.waitForAnyWindow(in: app, timeout: Self.windowCreationWaitTimeoutSeconds)
        return app
    }

    private static func waitForCandidateWindow(in app: NSRunningApplication, timeout: TimeInterval) -> Element? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let window = self.candidateWindow(in: app) {
                return window
            }
            Thread.sleep(forTimeInterval: Self.pollIntervalSeconds)
        }
        return self.candidateWindow(in: app)
    }

    private static func candidateWindow(in app: NSRunningApplication) -> Element? {
        let axApp = AXApp(app)
        let windows = axApp.windows() ?? []
        return windows.first(where: self.isPullableWindow(_:)) ?? axApp.focusedWindow()
    }

    private static func isPullableWindow(_ window: Element) -> Bool {
        guard window.isWindow else { return false }
        if window.isWindowMinimized() { return false }
        guard let frame = window.frame(), frame.width > 120, frame.height > 80 else { return false }
        return true
    }

    private static func prepareWindowForPull(_ window: Element) -> Bool {
        if window.isWindowMinimized() {
            _ = window.unminimizeWindow()
        }
        if let pid = window.pid(),
           let app = NSRunningApplication(processIdentifier: pid),
           app.isHidden
        {
            app.unhide()
        }
        return window.frame() != nil
    }

    private static func applicationHasAnyWindow(_ app: NSRunningApplication) -> Bool {
        guard let appElement = getApplicationElement(for: app.processIdentifier) else {
            return false
        }
        guard let windows = appElement.windows() else {
            return false
        }
        return !windows.isEmpty
    }

    private static func waitForAnyWindow(in app: NSRunningApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if self.applicationHasAnyWindow(app) {
                return true
            }
            Thread.sleep(forTimeInterval: Self.pollIntervalSeconds)
        }
        return self.applicationHasAnyWindow(app)
    }

    private static func waitForRunningApplication(
        matching applicationIdentifier: String,
        timeout: TimeInterval) -> NSRunningApplication?
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated }) {
                return app
            }
            Thread.sleep(forTimeInterval: Self.pollIntervalSeconds)
        }
        return self.runningApplications(matching: applicationIdentifier).first(where: { !$0.isTerminated })
    }

    private static func runningApplications(matching applicationIdentifier: String) -> [NSRunningApplication] {
        let normalizedIdentifier = applicationIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if self.looksLikeBundleIdentifier(applicationIdentifier) {
            return NSRunningApplication.runningApplications(withBundleIdentifier: applicationIdentifier)
        }

        return NSWorkspace.shared.runningApplications.filter { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return name == normalizedIdentifier
        }
    }

    private static func looksLikeBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(".") && !trimmed.contains(" ")
    }

    private static func reopenWithoutActivation(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return false
        }

        let escapedBundleIdentifier = bundleIdentifier
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(escapedBundleIdentifier)\" to reopen"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        return process.terminationStatus == 0
    }
}
