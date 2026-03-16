import Foundation

@MainActor
struct ActionTargetDescriptor {
    let reference: String
    let frame: CGRect?
    let role: String?
}

@MainActor
struct ActionExecutionContext {
    let statement: OXAStatement
    let statementIndex: Int
    let totalStatements: Int
    let targets: [ActionTargetDescriptor]
    let snapshotAppPID: pid_t?
}

@MainActor
protocol ActionExecutionMiddleware {
    func willPerform(_ context: ActionExecutionContext) throws
}

@MainActor
struct NoopActionExecutionMiddleware: ActionExecutionMiddleware {
    func willPerform(_ context: ActionExecutionContext) throws {}
}
