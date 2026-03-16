import Foundation

public struct PenguinOSXApp {
    public init() {}

    public func run(arguments: [String]) async -> Int32 {
        do {
            let command = try CLICommand.parse(arguments: arguments)
            switch command {
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
      query --app <app> [--max-depth N] [--limit N] [--cache-session] [--use-cached] <selector>
      action '<program>'
      daemon [--socket /tmp/penguin-osx.sock]
      help

    Examples:
      cursor-build query --app focused --cache-session "AXWindow AXButton"
      cursor-build action 'send click to abc123def;'
    """
}

private enum CLICommand {
    case query(PenguinQueryRequest)
    case action(String)
    case daemon(String)
    case help

    static func parse(arguments: [String]) throws -> CLICommand {
        guard let subcommand = arguments.first else {
            return .help
        }

        switch subcommand {
        case "help", "--help", "-h":
            return .help
        case "query":
            return .query(try CLIParser.parseQuery(arguments: Array(arguments.dropFirst())))
        case "action":
            return .action(try CLIParser.parseAction(arguments: Array(arguments.dropFirst())))
        case "daemon":
            return .daemon(try CLIParser.parseDaemon(arguments: Array(arguments.dropFirst())))
        default:
            throw CLIError("Unknown command '\(subcommand)'.")
        }
    }
}

private enum CLIParser {
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
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
