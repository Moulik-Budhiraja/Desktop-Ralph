import CoreGraphics
import Darwin
import Foundation

enum RalphLaunchMode: String {
    case autonomous
    case controlled
}

struct RalphAppConfiguration {
    var launchMode: RalphLaunchMode
    var controlSocketPath: String

    static func `default`() -> RalphAppConfiguration {
        RalphAppConfiguration(
            launchMode: .autonomous,
            controlSocketPath: RalphControlClient.defaultSocketPath())
    }
}

enum RalphControlCommand {
    case say(text: String, socketPath: String)
    case clear(socketPath: String)
    case move(x: Double, y: Double, duration: Double, socketPath: String)
    case nudge(dx: Double, dy: Double, duration: Double, socketPath: String)
    case wander(steps: Int, minimumDistance: Double, pauseDuration: Double, socketPath: String)
    case state(socketPath: String)

    var socketPath: String {
        switch self {
        case let .say(_, socketPath),
            let .clear(socketPath),
            let .move(_, _, _, socketPath),
            let .nudge(_, _, _, socketPath),
            let .wander(_, _, _, socketPath),
            let .state(socketPath):
            socketPath
        }
    }
}

struct RalphControlRequest: Codable {
    enum Kind: String, Codable {
        case say
        case clear
        case move
        case nudge
        case wander
        case state
    }

    let kind: Kind
    let text: String?
    let x: Double?
    let y: Double?
    let dx: Double?
    let dy: Double?
    let duration: Double?
    let steps: Int?
    let minimumDistance: Double?
    let pauseDuration: Double?

    static func say(_ text: String) -> RalphControlRequest {
        RalphControlRequest(
            kind: .say,
            text: text,
            x: nil,
            y: nil,
            dx: nil,
            dy: nil,
            duration: nil,
            steps: nil,
            minimumDistance: nil,
            pauseDuration: nil)
    }

    static func clear() -> RalphControlRequest {
        RalphControlRequest(
            kind: .clear,
            text: nil,
            x: nil,
            y: nil,
            dx: nil,
            dy: nil,
            duration: nil,
            steps: nil,
            minimumDistance: nil,
            pauseDuration: nil)
    }

    static func move(x: Double, y: Double, duration: Double) -> RalphControlRequest {
        RalphControlRequest(
            kind: .move,
            text: nil,
            x: x,
            y: y,
            dx: nil,
            dy: nil,
            duration: duration,
            steps: nil,
            minimumDistance: nil,
            pauseDuration: nil)
    }

    static func nudge(dx: Double, dy: Double, duration: Double) -> RalphControlRequest {
        RalphControlRequest(
            kind: .nudge,
            text: nil,
            x: nil,
            y: nil,
            dx: dx,
            dy: dy,
            duration: duration,
            steps: nil,
            minimumDistance: nil,
            pauseDuration: nil)
    }

    static func wander(steps: Int, minimumDistance: Double, pauseDuration: Double) -> RalphControlRequest {
        RalphControlRequest(
            kind: .wander,
            text: nil,
            x: nil,
            y: nil,
            dx: nil,
            dy: nil,
            duration: nil,
            steps: steps,
            minimumDistance: minimumDistance,
            pauseDuration: pauseDuration)
    }

    static func state() -> RalphControlRequest {
        RalphControlRequest(
            kind: .state,
            text: nil,
            x: nil,
            y: nil,
            dx: nil,
            dy: nil,
            duration: nil,
            steps: nil,
            minimumDistance: nil,
            pauseDuration: nil)
    }
}

struct RalphControlState: Codable, Equatable {
    let x: Double
    let y: Double
    let message: String
}

struct RalphControlResponse: Codable {
    let success: Bool
    let state: RalphControlState?
    let error: String?
}

enum RalphControlError: LocalizedError {
    case socketAlreadyInUse(String)
    case socketUnavailable(String)
    case invalidResponse(String)
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case let .socketAlreadyInUse(socketPath):
            "Ralph is already running on \(socketPath)."
        case let .socketUnavailable(message):
            message
        case let .invalidResponse(message):
            "Invalid Ralph control response: \(message)"
        case let .remoteError(message):
            message
        }
    }
}

struct RalphControlClient {
    let socketPath: String

    init(socketPath: String = Self.defaultSocketPath()) {
        self.socketPath = socketPath
    }

    static func defaultSocketPath() -> String {
        "/tmp/ralph-control-\(getuid()).sock"
    }

    func perform(_ command: RalphControlCommand) throws -> RalphControlState {
        switch command {
        case let .say(text, _):
            try self.send(.say(text))
        case .clear:
            try self.send(.clear())
        case let .move(x, y, duration, _):
            try self.send(.move(x: x, y: y, duration: duration))
        case let .nudge(dx, dy, duration, _):
            try self.send(.nudge(dx: dx, dy: dy, duration: duration))
        case let .wander(steps, minimumDistance, pauseDuration, _):
            try self.send(.wander(
                steps: steps,
                minimumDistance: minimumDistance,
                pauseDuration: pauseDuration))
        case .state:
            try self.send(.state())
        }
    }

    private func send(_ request: RalphControlRequest) throws -> RalphControlState {
        guard PenguinSocketTransport.canConnect(socketPath: self.socketPath) else {
            throw RalphControlError.socketUnavailable("Ralph is not running on \(self.socketPath).")
        }

        let requestData = try JSONEncoder().encode(request)
        let responseData = try PenguinSocketTransport.requestResponse(
            socketPath: self.socketPath,
            requestData: requestData)

        let response: RalphControlResponse
        do {
            response = try JSONDecoder().decode(RalphControlResponse.self, from: responseData)
        } catch {
            throw RalphControlError.invalidResponse(error.localizedDescription)
        }

        if response.success, let state = response.state {
            return state
        }

        throw RalphControlError.remoteError(response.error ?? "Unknown Ralph control error.")
    }
}

enum RalphControlServer {
    static func run(
        socketPath: String,
        handler: @escaping (RalphControlRequest) -> RalphControlResponse) throws
    {
        guard !PenguinSocketTransport.canConnect(socketPath: socketPath) else {
            throw RalphControlError.socketAlreadyInUse(socketPath)
        }

        let serverFD = try PenguinSocketTransport.makeServerSocket(path: socketPath)
        defer {
            Darwin.close(serverFD)
            Darwin.unlink(socketPath)
        }

        while true {
            let clientFD = Darwin.accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                throw PenguinDaemonError.socketAcceptFailed(String(cString: strerror(errno)))
            }

            do {
                try self.handleClient(fd: clientFD, handler: handler)
            } catch {
                let response = RalphControlResponse(success: false, state: nil, error: error.localizedDescription)
                if let data = try? JSONEncoder().encode(response) {
                    try? PenguinSocketTransport.writeAll(data: data, to: clientFD)
                }
            }
            Darwin.close(clientFD)
        }
    }

    private static func handleClient(
        fd: Int32,
        handler: @escaping (RalphControlRequest) -> RalphControlResponse) throws
    {
        let requestData = try PenguinSocketTransport.readAll(from: fd)
        guard !requestData.isEmpty else {
            throw PenguinDaemonError.invalidRequest("Empty Ralph control payload.")
        }

        let request: RalphControlRequest
        do {
            request = try JSONDecoder().decode(RalphControlRequest.self, from: requestData)
        } catch {
            throw PenguinDaemonError.invalidRequest(error.localizedDescription)
        }

        let response = handler(request)
        let encoded = try JSONEncoder().encode(response)
        try PenguinSocketTransport.writeAll(data: encoded, to: fd)
    }
}

@MainActor
final class RalphControlCoordinator {
    private let controller: LaunchSpriteWindowController

    init(controller: LaunchSpriteWindowController) {
        self.controller = controller
    }

    func handle(_ request: RalphControlRequest) async -> RalphControlResponse {
        do {
            let state = try await self.execute(request)
            return RalphControlResponse(success: true, state: state, error: nil)
        } catch {
            return RalphControlResponse(success: false, state: nil, error: error.localizedDescription)
        }
    }

    private func execute(_ request: RalphControlRequest) async throws -> RalphControlState {
        switch request.kind {
        case .say:
            self.controller.setSpeechText(request.text ?? "")
        case .clear:
            self.controller.setSpeechText("")
        case .move:
            guard let x = request.x, let y = request.y else {
                throw CLIError("Ralph move requires both x and y.")
            }
            await self.controller.moveSprite(
                to: CGPoint(x: x, y: y),
                duration: max(0, request.duration ?? 0.8))
        case .nudge:
            guard let dx = request.dx, let dy = request.dy else {
                throw CLIError("Ralph nudge requires both dx and dy.")
            }
            let current = self.controller.currentSpriteOrigin() ?? .zero
            await self.controller.moveSprite(
                to: CGPoint(x: current.x + dx, y: current.y + dy),
                duration: max(0, request.duration ?? 0.8))
        case .wander:
            let steps = max(request.steps ?? 6, 1)
            let minimumDistance = max(request.minimumDistance ?? 220, 0)
            let pauseDuration = max(request.pauseDuration ?? 0.55, 0)
            await self.performWander(
                steps: steps,
                minimumDistance: minimumDistance,
                pauseDuration: pauseDuration)
        case .state:
            break
        }

        return self.currentState()
    }

    private func performWander(steps: Int, minimumDistance: Double, pauseDuration: Double) async {
        for _ in 0..<steps {
            let start = self.controller.currentSpriteOrigin()
                ?? self.controller.randomSpriteOrigin(minimumTravelDistance: 0)
            let destination = self.controller.randomSpriteOrigin(minimumTravelDistance: minimumDistance)
            let distance = hypot(destination.x - start.x, destination.y - start.y)
            let duration = max(1.1, min(4.2, TimeInterval(distance / 150)))

            await self.controller.moveSprite(from: start, to: destination, duration: duration)
            if pauseDuration > 0 {
                try? await Task.sleep(for: .seconds(pauseDuration))
            }
        }
    }

    private func currentState() -> RalphControlState {
        let origin = self.controller.currentSpriteOrigin() ?? .zero
        return RalphControlState(
            x: origin.x,
            y: origin.y,
            message: self.controller.currentSpeechText())
    }
}

enum RalphControlStateFormatter {
    static func string(for state: RalphControlState) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CLIError("Failed to encode Ralph state output.")
        }
        return string
    }
}
