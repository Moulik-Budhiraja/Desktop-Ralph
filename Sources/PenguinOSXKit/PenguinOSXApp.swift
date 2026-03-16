import AppKit
import Foundation

public struct PenguinOSXApp {
    public init() {}

    public func run(arguments: [String]) async -> Int32 {
        do {
            let command = try CLICommand.parse(arguments: arguments)
            switch command {
            case let .app(configuration):
                try await MainActor.run {
                    try PenguinAppHost.run(configuration: configuration)
                }
            case let .query(request):
                let output = try PenguinDaemonClient().execute(query: request)
                print(output)
            case let .action(program):
                let output = try PenguinDaemonClient().execute(actionProgram: program)
                print(output)
            case let .daemon(socketPath):
                try await MainActor.run {
                    try PenguinDaemonHost.run(socketPath: socketPath)
                }
            case let .ralph(command):
                let state = try RalphControlClient(socketPath: command.socketPath).perform(command)
                print(try RalphControlStateFormatter.string(for: state))
            case .help:
                print(Self.helpText)
            }
            return 0
        } catch let error as CLIError {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            FileHandle.standardError.write(Data("Run `cursor-build help` for usage.\n".utf8))
            return 1
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static let helpText = """
    cursor-build

    Commands:
      app [--controlled] [--control-socket /tmp/ralph-control.sock]
      query --app <app> [--max-depth N] [--limit N] [--cache-session] [--use-cached] <selector>
      action '<program>'
      daemon [--socket /tmp/penguin-osx.sock]
      ralph say <text> [--socket /tmp/ralph-control.sock]
      ralph clear [--socket /tmp/ralph-control.sock]
      ralph move --x <x> --y <y> [--duration seconds] [--socket /tmp/ralph-control.sock]
      ralph nudge --dx <dx> --dy <dy> [--duration seconds] [--socket /tmp/ralph-control.sock]
      ralph wander [--steps count] [--minimum-distance points] [--pause seconds] [--socket /tmp/ralph-control.sock]
      ralph state [--socket /tmp/ralph-control.sock]
      help

    Examples:
      cursor-build app --controlled
      cursor-build query --app focused --cache-session "AXWindow AXButton"
      cursor-build action 'send click to abc123def;'
      cursor-build ralph say "Ralph is plotting"
      cursor-build ralph wander --steps 6
    """
}

enum CLICommand {
    case app(RalphAppConfiguration)
    case query(PenguinQueryRequest)
    case action(String)
    case daemon(String)
    case ralph(RalphControlCommand)
    case help

    static func parse(arguments: [String]) throws -> CLICommand {
        guard let subcommand = arguments.first else {
            return .app(.default())
        }

        switch subcommand {
        case "help", "--help", "-h":
            return .help
        case "app":
            return .app(try CLIParser.parseApp(arguments: Array(arguments.dropFirst())))
        case "query":
            return .query(try CLIParser.parseQuery(arguments: Array(arguments.dropFirst())))
        case "action":
            return .action(try CLIParser.parseAction(arguments: Array(arguments.dropFirst())))
        case "daemon":
            return .daemon(try CLIParser.parseDaemon(arguments: Array(arguments.dropFirst())))
        case "ralph":
            return .ralph(try CLIParser.parseRalph(arguments: Array(arguments.dropFirst())))
        default:
            throw CLIError("Unknown command '\(subcommand)'.")
        }
    }
}

@MainActor
private enum PenguinAppHost {
    private static var launchController: LaunchSpriteWindowController?
    private static var appDelegate: AppDelegate?
    private static var keepAlivePort: Port?
    private static var controlCoordinator: RalphControlCoordinator?

    static func run(configuration: RalphAppConfiguration) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let controller = try LaunchSpriteWindowController.make()
        controller.show()
        Self.launchController = controller
        if configuration.launchMode == .autonomous {
            Task { @MainActor in
                await Self.runWanderLoop(using: controller)
            }
        } else {
            controller.setSpeechText("Ralph is listening")
        }
        try Self.startControlServer(
            socketPath: configuration.controlSocketPath,
            controller: controller)

        let delegate = AppDelegate(controller: controller)
        Self.appDelegate = delegate
        app.delegate = delegate
        let keepAlivePort = Port()
        Self.keepAlivePort = keepAlivePort
        RunLoop.main.add(keepAlivePort, forMode: .default)
        CFRunLoopRun()
    }

    private static func startControlServer(
        socketPath: String,
        controller: LaunchSpriteWindowController) throws
    {
        guard !PenguinSocketTransport.canConnect(socketPath: socketPath) else {
            throw RalphControlError.socketAlreadyInUse(socketPath)
        }

        let coordinator = RalphControlCoordinator(controller: controller)
        Self.controlCoordinator = coordinator
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try RalphControlServer.run(socketPath: socketPath) { request in
                    let box = RalphResponseBox()
                    let semaphore = DispatchSemaphore(value: 0)

                    Task { @MainActor in
                        box.value = await coordinator.handle(request)
                        semaphore.signal()
                    }

                    semaphore.wait()
                    return box.value
                        ?? RalphControlResponse(success: false, state: nil, error: "Interrupted")
                }
            } catch {
                FileHandle.standardError.write(Data("ralph control error: \(error.localizedDescription)\n".utf8))
                Task { @MainActor in
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private final class AppDelegate: NSObject, NSApplicationDelegate {
        private let controller: LaunchSpriteWindowController

        init(controller: LaunchSpriteWindowController) {
            self.controller = controller
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            false
        }
    }

    private final class RalphResponseBox: @unchecked Sendable {
        var value: RalphControlResponse?
    }

    private static func runWanderLoop(using controller: LaunchSpriteWindowController) async {
        if let screenFrame = NSScreen.main?.visibleFrame {
            let start = CGPoint(x: screenFrame.midX - 146, y: screenFrame.midY - 104)
            controller.setSpriteOrigin(start)
            try? await Task.sleep(for: .milliseconds(900))
        }

        while true {
            let start = controller.currentSpriteOrigin() ?? controller.randomSpriteOrigin(minimumTravelDistance: 0)
            let destination = controller.randomSpriteOrigin(minimumTravelDistance: 280)
            let distance = hypot(destination.x - start.x, destination.y - start.y)
            let duration = max(1.8, min(4.8, TimeInterval(distance / 150)))

            try? await Task.sleep(for: .milliseconds(Int.random(in: 900...1800)))
            await controller.moveSprite(from: start, to: destination, duration: duration)
        }
    }
}

enum CLIParser {
    static func parseApp(arguments: [String]) throws -> RalphAppConfiguration {
        var configuration = RalphAppConfiguration.default()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--controlled":
                configuration.launchMode = .controlled
            case "--control-socket":
                index += 1
                guard index < arguments.count else { throw CLIError("Missing value for --control-socket.") }
                configuration.controlSocketPath = arguments[index]
            default:
                throw CLIError("Unknown app argument '\(argument)'.")
            }
            index += 1
        }

        return configuration
    }

    static func parseQuery(arguments: [String]) throws -> PenguinQueryRequest {
        var appIdentifier: String?
        var maxDepth = 40
        var limit = 50
        var cacheSessionEnabled = false
        var useCachedSnapshot = false
        var positional: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--app":
                index += 1
                guard index < arguments.count else { throw CLIError("Missing value for --app.") }
                appIdentifier = arguments[index]
            case "--max-depth":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]) else {
                    throw CLIError("Invalid value for --max-depth.")
                }
                maxDepth = value
            case "--limit":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]) else {
                    throw CLIError("Invalid value for --limit.")
                }
                limit = value
            case "--cache-session":
                cacheSessionEnabled = true
            case "--use-cached":
                useCachedSnapshot = true
            default:
                positional.append(argument)
            }
            index += 1
        }

        guard let appIdentifier else { throw CLIError("Query requires --app.") }
        guard positional.count == 1 else { throw CLIError("Query requires exactly one selector argument.") }

        return PenguinQueryRequest(
            appIdentifier: appIdentifier,
            selector: positional[0],
            maxDepth: max(0, maxDepth),
            limit: max(0, limit),
            cacheSessionEnabled: cacheSessionEnabled,
            useCachedSnapshot: useCachedSnapshot)
    }

    static func parseAction(arguments: [String]) throws -> String {
        guard arguments.count == 1 else {
            throw CLIError("Action requires exactly one OXA program argument.")
        }
        let program = arguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !program.isEmpty else {
            throw CLIError("Action program cannot be empty.")
        }
        return program
    }

    static func parseDaemon(arguments: [String]) throws -> String {
        var socketPath = PenguinDaemonClient.defaultSocketPath()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--socket":
                index += 1
                guard index < arguments.count else { throw CLIError("Missing value for --socket.") }
                socketPath = arguments[index]
            default:
                throw CLIError("Unknown daemon argument '\(argument)'.")
            }
            index += 1
        }

        return socketPath
    }

    static func parseRalph(arguments: [String]) throws -> RalphControlCommand {
        guard let subcommand = arguments.first else {
            throw CLIError("Ralph requires a subcommand.")
        }

        let parsed = try self.parseSharedSocketOption(arguments: Array(arguments.dropFirst()))
        let socketPath = parsed.socketPath
        let payload = parsed.arguments

        switch subcommand {
        case "say":
            guard payload.count == 1 else {
                throw CLIError("Ralph say requires exactly one text argument.")
            }
            return .say(text: payload[0], socketPath: socketPath)
        case "clear":
            guard payload.isEmpty else {
                throw CLIError("Ralph clear does not accept extra arguments.")
            }
            return .clear(socketPath: socketPath)
        case "move":
            return try self.parseRalphMove(arguments: payload, socketPath: socketPath)
        case "nudge":
            return try self.parseRalphNudge(arguments: payload, socketPath: socketPath)
        case "wander":
            return try self.parseRalphWander(arguments: payload, socketPath: socketPath)
        case "state":
            guard payload.isEmpty else {
                throw CLIError("Ralph state does not accept extra arguments.")
            }
            return .state(socketPath: socketPath)
        default:
            throw CLIError("Unknown Ralph subcommand '\(subcommand)'.")
        }
    }

    private static func parseRalphMove(arguments: [String], socketPath: String) throws -> RalphControlCommand {
        var x: Double?
        var y: Double?
        var duration = 0.8
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--x":
                index += 1
                x = try self.parseDouble(arguments, index: index, option: "--x")
            case "--y":
                index += 1
                y = try self.parseDouble(arguments, index: index, option: "--y")
            case "--duration":
                index += 1
                duration = try self.parseDouble(arguments, index: index, option: "--duration")
            default:
                throw CLIError("Unknown Ralph move argument '\(argument)'.")
            }
            index += 1
        }

        guard let x, let y else {
            throw CLIError("Ralph move requires both --x and --y.")
        }

        return .move(x: x, y: y, duration: duration, socketPath: socketPath)
    }

    private static func parseRalphNudge(arguments: [String], socketPath: String) throws -> RalphControlCommand {
        var dx: Double?
        var dy: Double?
        var duration = 0.8
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--dx":
                index += 1
                dx = try self.parseDouble(arguments, index: index, option: "--dx")
            case "--dy":
                index += 1
                dy = try self.parseDouble(arguments, index: index, option: "--dy")
            case "--duration":
                index += 1
                duration = try self.parseDouble(arguments, index: index, option: "--duration")
            default:
                throw CLIError("Unknown Ralph nudge argument '\(argument)'.")
            }
            index += 1
        }

        guard let dx, let dy else {
            throw CLIError("Ralph nudge requires both --dx and --dy.")
        }

        return .nudge(dx: dx, dy: dy, duration: duration, socketPath: socketPath)
    }

    private static func parseRalphWander(arguments: [String], socketPath: String) throws -> RalphControlCommand {
        var steps = 6
        var minimumDistance = 220.0
        var pauseDuration = 0.55
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--steps":
                index += 1
                steps = try self.parseInt(arguments, index: index, option: "--steps")
            case "--minimum-distance":
                index += 1
                minimumDistance = try self.parseDouble(arguments, index: index, option: "--minimum-distance")
            case "--pause":
                index += 1
                pauseDuration = try self.parseDouble(arguments, index: index, option: "--pause")
            default:
                throw CLIError("Unknown Ralph wander argument '\(argument)'.")
            }
            index += 1
        }

        guard steps > 0 else {
            throw CLIError("Ralph wander requires --steps to be greater than 0.")
        }

        return .wander(
            steps: steps,
            minimumDistance: minimumDistance,
            pauseDuration: pauseDuration,
            socketPath: socketPath)
    }

    private static func parseSharedSocketOption(arguments: [String]) throws -> (socketPath: String, arguments: [String]) {
        var socketPath = RalphControlClient.defaultSocketPath()
        var positional: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--socket" {
                index += 1
                guard index < arguments.count else { throw CLIError("Missing value for --socket.") }
                socketPath = arguments[index]
            } else {
                positional.append(argument)
            }
            index += 1
        }

        return (socketPath, positional)
    }

    private static func parseDouble(_ arguments: [String], index: Int, option: String) throws -> Double {
        guard index < arguments.count, let value = Double(arguments[index]) else {
            throw CLIError("Invalid value for \(option).")
        }
        return value
    }

    private static func parseInt(_ arguments: [String], index: Int, option: String) throws -> Int {
        guard index < arguments.count, let value = Int(arguments[index]) else {
            throw CLIError("Invalid value for \(option).")
        }
        return value
    }
}

struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
