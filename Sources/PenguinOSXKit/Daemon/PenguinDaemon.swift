import AppKit
import Darwin
import Foundation

public enum PenguinDaemonHost {
    @MainActor
    public static func run(socketPath: String) throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)

        let coordinator = PenguinDaemonCoordinator()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PenguinDaemonServer.run(socketPath: socketPath) { request in
                    let box = ResponseBox()
                    let semaphore = DispatchSemaphore(value: 0)

                    Task { @MainActor in
                        box.value = await coordinator.handle(request)
                        semaphore.signal()
                    }

                    semaphore.wait()
                    return box.value ?? PenguinDaemonResponse(success: false, output: nil, error: "Interrupted")
                }
            } catch {
                FileHandle.standardError.write(Data("daemon error: \(error.localizedDescription)\n".utf8))
            }
            Task { @MainActor in
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }

        RunLoop.main.run()
    }
}

private final class ResponseBox: @unchecked Sendable {
    var value: PenguinDaemonResponse?
}

enum PenguinDaemonServer {
    private static let idleTimeoutSeconds = 600

    static func run(
        socketPath: String,
        handler: @escaping (PenguinDaemonRequest) -> PenguinDaemonResponse) throws
    {
        let serverFD = try PenguinSocketTransport.makeServerSocket(path: socketPath)
        defer {
            Darwin.close(serverFD)
            Darwin.unlink(socketPath)
        }

        while true {
            var descriptor = pollfd(fd: serverFD, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, Int32(Self.idleTimeoutSeconds * 1000))
            if ready == 0 {
                return
            }
            if ready < 0 {
                if errno == EINTR {
                    continue
                }
                throw PenguinDaemonError.socketAcceptFailed(String(cString: strerror(errno)))
            }

            let clientFD = Darwin.accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                throw PenguinDaemonError.socketAcceptFailed(String(cString: strerror(errno)))
            }

            do {
                try Self.handleClient(fd: clientFD, handler: handler)
            } catch {
                let response = PenguinDaemonResponse(success: false, output: nil, error: error.localizedDescription)
                if let data = try? JSONEncoder().encode(response) {
                    try? PenguinSocketTransport.writeAll(data: data, to: clientFD)
                }
            }
            Darwin.close(clientFD)
        }
    }

    private static func handleClient(
        fd: Int32,
        handler: @escaping (PenguinDaemonRequest) -> PenguinDaemonResponse) throws
    {
        let requestData = try PenguinSocketTransport.readAll(from: fd)
        guard !requestData.isEmpty else {
            throw PenguinDaemonError.invalidRequest("Empty payload.")
        }

        let request: PenguinDaemonRequest
        do {
            request = try JSONDecoder().decode(PenguinDaemonRequest.self, from: requestData)
        } catch {
            throw PenguinDaemonError.invalidRequest(error.localizedDescription)
        }

        let response = handler(request)
        let encoded = try JSONEncoder().encode(response)
        try PenguinSocketTransport.writeAll(data: encoded, to: fd)
    }
}

@MainActor
final class PenguinDaemonCoordinator {
    private let queryService = PenguinQueryService()
    private let visualizer = PenguinActionVisualizer()
    private lazy var orchestrator = PenguinActionOrchestrator(
        refStore: self.queryService.refStore,
        visualizer: self.visualizer,
        executor: PenguinActionExecutor(refStore: self.queryService.refStore))

    func handle(_ request: PenguinDaemonRequest) async -> PenguinDaemonResponse {
        switch request.mode {
        case .query:
            guard let query = request.query else {
                return PenguinDaemonResponse(success: false, output: nil, error: "Missing query payload.")
            }
            do {
                let output = try self.queryService.execute(query)
                return PenguinDaemonResponse(success: true, output: output, error: nil)
            } catch {
                return PenguinDaemonResponse(success: false, output: nil, error: error.localizedDescription)
            }

        case .actions:
            guard let actions = request.actions else {
                return PenguinDaemonResponse(success: false, output: nil, error: "Missing action payload.")
            }
            do {
                let output = try await self.orchestrator.execute(programSource: actions)
                return PenguinDaemonResponse(success: true, output: output, error: nil)
            } catch {
                return PenguinDaemonResponse(success: false, output: nil, error: error.localizedDescription)
            }
        }
    }
}

public struct PenguinDaemonClient {
    public init() {}

    public static func defaultSocketPath() -> String {
        "/tmp/penguin-osx-\(getuid()).sock"
    }

    func execute(query: PenguinQueryRequest) throws -> String {
        try self.send(PenguinDaemonRequest(query: query))
    }

    func execute(actionProgram: String) throws -> String {
        try self.send(PenguinDaemonRequest(actionProgram: actionProgram))
    }

    private func send(_ request: PenguinDaemonRequest) throws -> String {
        let socketPath = Self.defaultSocketPath()
        try self.ensureDaemonRunning(socketPath: socketPath)
        let data = try JSONEncoder().encode(request)
        let responseData = try PenguinSocketTransport.requestResponse(socketPath: socketPath, requestData: data)

        let response: PenguinDaemonResponse
        do {
            response = try JSONDecoder().decode(PenguinDaemonResponse.self, from: responseData)
        } catch {
            throw PenguinDaemonError.invalidResponse(error.localizedDescription)
        }

        if response.success, let output = response.output {
            return output
        }

        throw PenguinDaemonError.remoteError(response.error ?? "Unknown daemon error.")
    }

    private func ensureDaemonRunning(socketPath: String) throws {
        if PenguinSocketTransport.canConnect(socketPath: socketPath) {
            return
        }

        let process = Process()
        process.executableURL = try self.currentExecutableURL()
        process.arguments = ["daemon", "--socket", socketPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw PenguinDaemonError.daemonStartFailed(error.localizedDescription)
        }

        for _ in 0..<40 {
            if PenguinSocketTransport.canConnect(socketPath: socketPath) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw PenguinDaemonError.daemonUnavailable("Timed out waiting for daemon to start.")
    }

    private func currentExecutableURL() throws -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
        }

        let rawPath = CommandLine.arguments[0]
        let path: String
        if rawPath.hasPrefix("/") {
            path = rawPath
        } else {
            path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(rawPath)
                .path
        }
        return URL(fileURLWithPath: path)
    }
}
