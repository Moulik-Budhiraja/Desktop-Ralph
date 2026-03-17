// OSXMain.swift - Main entry point for Ralph CLI

import AppKit
import Foundation
import OSXQuery
@preconcurrency import Commander

@main
struct RalphRootCommand: ParsableCommand {
    static func main() async {
        let code = await OSXCLIEntrypoint.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(code)
    }

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        let version = MainActor.assumeIsolated { osxVersion }
        return CommandDescription(
            commandName: "ralph",
            abstract: "Ralph CLI for querying and interacting with Accessibility trees. Version \(version)",
            subcommands: [
                OSXQueryCommand.self,
                OSXActionCommand.self,
                OSXSelectorCacheDaemonCommand.self,
            ],
            usageExamples: [
                CommandUsageExample(
                    command: "ralph query --app TextEdit \"AXTextArea\"",
                    description: "Query an app with the OXQ selector language."),
                CommandUsageExample(
                    command: "ralph action 'send click to 28e6a93cf;'",
                    description: "Execute OXA actions against refs from the cache daemon."),
            ])
    }
}

@MainActor
private protocol OSXLeafCommand: ParsableCommand {
    mutating func apply(parsedValues: ParsedValues) throws
}

struct OSXQueryCommand: OSXLeafCommand {
    @Flag(name: .long, help: "Enable debug logging (normal detail level). Use --verbose for maximum detail.")
    var debug: Bool = false

    @Flag(name: .long, help: "Enable verbose debug logging for every internal step.")
    var verbose: Bool = false

    @Option(name: .long, help: "Target app (bundle id, app name, PID, or 'focused').")
    var app: String?

    @Option(name: .customLong("max-depth"), help: "Maximum traversal depth (default unlimited).")
    var maxDepth: Int?

    @Option(name: .long, help: "Maximum result rows to print (default 50, 0 = no cap).")
    var limit: Int?

    var bubbleText: String?

    @Flag(name: .customLong("no-color"), help: "Disable ANSI color output.")
    var noColor: Bool = false

    @Flag(name: .customLong("show-path"), help: "Include full generated path per selector match.")
    var showPath: Bool = false

    @Flag(name: .customLong("show-name-source"), help: "Include computed name source (for example AXTitle).")
    var showNameSource: Bool = false

    @Flag(name: .customLong("tree"), help: "Render selector matches as a compact tree.")
    var tree: Bool = false

    @Flag(name: .customLong("tree-full"), help: "Render selector matches as a full tree including inferred unmatched ancestors.")
    var treeFull: Bool = false

    @Flag(name: .customLong("cache-session"), help: "Refresh and reuse the selector cache daemon snapshot.")
    var cacheSession: Bool = false

    @Flag(name: .customLong("use-cached"), help: "Query using an existing warm selector cache daemon snapshot.")
    var useCached: Bool = false

    @Argument(help: "Selector query to run.")
    var selector: String?

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: "query",
            abstract: "Run a selector query against a target app.")
    }

    mutating func apply(parsedValues: ParsedValues) throws {
        self.debug = parsedValues.flags.contains("debug")
        self.verbose = parsedValues.flags.contains("verbose")
        self.noColor = parsedValues.flags.contains("noColor")
        self.showPath = parsedValues.flags.contains("showPath")
        self.showNameSource = parsedValues.flags.contains("showNameSource")
        self.tree = parsedValues.flags.contains("tree")
        self.treeFull = parsedValues.flags.contains("treeFull")
        self.cacheSession = parsedValues.flags.contains("cacheSession")
        self.useCached = parsedValues.flags.contains("useCached")

        self.app = parsedValues.options["app"]?.last
        self.maxDepth = try Self.decodeIntOption(parsedValues.options["maxDepth"]?.last, optionName: "--max-depth")
        self.limit = try Self.decodeIntOption(parsedValues.options["limit"]?.last, optionName: "--limit")
        self.bubbleText = QueryCommandRuntimeContext.consumeBubbleText()
        self.selector = try Self.requireSinglePositional(parsedValues.positional, name: "selector")
    }

    mutating func run() async throws {
        try await MainActor.run {
            configureLogging(debug: self.debug, verbose: self.verbose)
            logDebugVersion(command: "query")

            let request = try SelectorQueryRequestBuilder.build(
                app: self.app,
                selector: self.selector,
                bubbleText: self.bubbleText,
                maxDepth: self.maxDepth,
                limit: self.limit,
                noColor: self.noColor,
                showPath: self.showPath,
                showNameSource: self.showNameSource,
                tree: self.tree,
                treeFull: self.treeFull,
                cacheSession: self.cacheSession,
                useCached: self.useCached,
                hasStructuredInput: false,
                stdoutSupportsANSI: OutputCapabilities.stdoutSupportsANSI)

            guard let request else {
                throw ValidationError("Query requires --app and a selector argument.")
            }

            do {
                if request.cacheSessionEnabled {
                    let output = try SelectorCacheDaemonClient().execute(request: request)
                    print(output)
                } else {
                    PenguinOverlayController.shared.setBubbleMessage(request.bubbleMessage)
                    let runner = SelectorQueryRunner()
                    let report = try runner.execute(request)
                    print(SelectorQueryOutputFormatter.format(report: report))
                }
                fflush(stdout)
                axClearLogs()
            } catch let parseError as OXQParseError {
                throw ValidationError("Invalid selector query: \(parseError.description)")
            } catch let selectorError as SelectorQueryCLIError {
                throw ValidationError(selectorError.localizedDescription)
            } catch let cacheError as SelectorCacheDaemonError {
                throw ValidationError(cacheError.localizedDescription)
            }
        }
    }
}

struct OSXActionCommand: OSXLeafCommand {
    @Flag(name: .long, help: "Enable debug logging (normal detail level). Use --verbose for maximum detail.")
    var debug: Bool = false

    @Flag(name: .long, help: "Enable verbose debug logging for every internal step.")
    var verbose: Bool = false

    @Argument(help: "OXA action program to execute.")
    var program: String?

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: "action",
            abstract: "Execute an OXA action program against cached refs.")
    }

    mutating func apply(parsedValues: ParsedValues) throws {
        self.debug = parsedValues.flags.contains("debug")
        self.verbose = parsedValues.flags.contains("verbose")
        self.program = try Self.requireSinglePositional(parsedValues.positional, name: "program")
    }

    mutating func run() async throws {
        try await MainActor.run {
            configureLogging(debug: self.debug, verbose: self.verbose)
            logDebugVersion(command: "action")

            guard let program = self.program?.trimmingCharacters(in: .whitespacesAndNewlines), !program.isEmpty else {
                throw ValidationError("Action requires a program argument.")
            }

            do {
                let output = try SelectorCacheDaemonClient().execute(actionsProgram: program)
                print(output)
                fflush(stdout)
                axClearLogs()
            } catch let cacheError as SelectorCacheDaemonError {
                throw ValidationError(cacheError.localizedDescription)
            }
        }
    }
}

struct OSXSelectorCacheDaemonCommand: OSXLeafCommand {
    @Option(name: .customLong("socket"), help: "Internal: selector cache daemon socket path.")
    var socketPath: String?

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: "selector-cache-daemon",
            abstract: "Internal selector cache daemon runner.")
    }

    mutating func apply(parsedValues: ParsedValues) throws {
        self.socketPath = parsedValues.options["socketPath"]?.last
        if !parsedValues.positional.isEmpty {
            throw ValidationError("selector-cache-daemon does not accept positional arguments.")
        }
    }

    mutating func run() async throws {
        try await MainActor.run {
            let resolvedSocketPath = self.socketPath ?? SelectorCacheDaemonClient.defaultSocketPath()
            try SelectorCacheDaemonServer.run(
                socketPath: resolvedSocketPath,
                actionMiddleware: OverlayActionExecutionMiddleware())
        }
    }
}

extension OSXLeafCommand {
    fileprivate static func requireSinglePositional(_ values: [String], name: String) throws -> String? {
        guard values.count <= 1 else {
            throw ValidationError("Unexpected extra arguments for \(Self.commandDescription.commandName ?? "command").")
        }
        return values.first
    }

    fileprivate static func decodeIntOption(_ value: String?, optionName: String) throws -> Int? {
        guard let value else { return nil }
        guard let parsed = Int(value) else {
            throw ValidationError("Invalid value for \(optionName): \(value)")
        }
        return parsed
    }
}

func configureLogging(debug: Bool, verbose: Bool) {
    if verbose {
        GlobalAXLogger.shared.isLoggingEnabled = true
        GlobalAXLogger.shared.detailLevel = .verbose
    } else if debug {
        GlobalAXLogger.shared.isLoggingEnabled = true
        GlobalAXLogger.shared.detailLevel = .normal
    } else {
        GlobalAXLogger.shared.isLoggingEnabled = false
        GlobalAXLogger.shared.detailLevel = .minimal
    }
}

func logDebugVersion(command: String) {
    guard GlobalAXLogger.shared.isLoggingEnabled else { return }
    let version = MainActor.assumeIsolated { osxVersion }
    fputs(
        logSegments(
            "OSXMain.run: ralph \(command) version \(version) build \(osxBuildStamp)",
            "Detail level: \(GlobalAXLogger.shared.detailLevel).") + "\n",
        stderr)
}
