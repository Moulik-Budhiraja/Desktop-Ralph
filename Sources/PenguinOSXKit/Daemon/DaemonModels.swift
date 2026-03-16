import Foundation

enum PenguinDaemonMode: String, Codable {
    case query
    case actions
}

struct PenguinQueryRequest: Codable, Sendable, Equatable {
    let appIdentifier: String
    let selector: String
    let maxDepth: Int
    let limit: Int
    let cacheSessionEnabled: Bool
    let useCachedSnapshot: Bool
}

struct PenguinDaemonRequest: Codable, Sendable {
    let mode: PenguinDaemonMode
    let query: PenguinQueryRequest?
    let actions: String?

    init(query: PenguinQueryRequest) {
        self.mode = .query
        self.query = query
        self.actions = nil
    }

    init(actionProgram: String) {
        self.mode = .actions
        self.query = nil
        self.actions = actionProgram
    }
}

struct PenguinDaemonResponse: Codable, Sendable {
    let success: Bool
    let output: String?
    let error: String?
}

enum PenguinDaemonError: LocalizedError {
    case socketPathTooLong(String)
    case socketCreateFailed(String)
    case socketBindFailed(String)
    case socketListenFailed(String)
    case socketAcceptFailed(String)
    case socketConnectFailed(String)
    case socketReadFailed(String)
    case socketWriteFailed(String)
    case daemonStartFailed(String)
    case daemonUnavailable(String)
    case invalidRequest(String)
    case invalidResponse(String)
    case remoteError(String)

    var errorDescription: String? {
        switch self {
        case let .socketPathTooLong(path):
            "Socket path is too long: \(path)"
        case let .socketCreateFailed(details):
            "Failed to create socket: \(details)"
        case let .socketBindFailed(details):
            "Failed to bind socket: \(details)"
        case let .socketListenFailed(details):
            "Failed to listen on socket: \(details)"
        case let .socketAcceptFailed(details):
            "Failed to accept socket client: \(details)"
        case let .socketConnectFailed(details):
            "Failed to connect to daemon: \(details)"
        case let .socketReadFailed(details):
            "Failed to read daemon payload: \(details)"
        case let .socketWriteFailed(details):
            "Failed to write daemon payload: \(details)"
        case let .daemonStartFailed(details):
            "Failed to launch daemon: \(details)"
        case let .daemonUnavailable(details):
            "Daemon unavailable: \(details)"
        case let .invalidRequest(details):
            "Invalid daemon request: \(details)"
        case let .invalidResponse(details):
            "Invalid daemon response: \(details)"
        case let .remoteError(details):
            details
        }
    }
}
