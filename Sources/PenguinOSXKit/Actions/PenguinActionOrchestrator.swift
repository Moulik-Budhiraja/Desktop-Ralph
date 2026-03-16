import Foundation

@MainActor
final class PenguinActionOrchestrator {
    private let refStore: SelectorActionRefStore
    private let visualizer: ActionVisualizer
    private let executor: PenguinStatementExecuting

    init(refStore: SelectorActionRefStore, visualizer: ActionVisualizer, executor: PenguinStatementExecuting) {
        self.refStore = refStore
        self.visualizer = visualizer
        self.executor = executor
    }

    func execute(programSource: String) async throws -> String {
        let program = try OXAParser.parse(programSource)
        try self.executor.preflight(program: program)

        var output: [String] = []
        for (index, statement) in program.statements.enumerated() {
            let next = index + 1 < program.statements.count ? program.statements[index + 1] : nil
            try await self.visualizeIfNeeded(statement, next: next)
            let result = try self.executor.execute(statement)
            if ActionVisualizationPlanner.isVisualized(statement) {
                await self.visualizer.flashAction()
            }
            output.append("ok [\(index + 1)] \(self.executor.describe(statement))")
            if let readOutput = result.readOutput {
                output.append("value [\(index + 1)] \(readOutput)")
            }
        }

        await self.visualizer.idle()
        return output.isEmpty ? "ok actions=0" : output.joined(separator: "\n")
    }

    private func visualizeIfNeeded(_ statement: OXAStatement, next: OXAStatement?) async throws {
        guard ActionVisualizationPlanner.isVisualized(statement) else { return }

        let targetFrame = ActionVisualizationPlanner.targetReference(of: statement).flatMap {
            self.refStore.frame(for: $0) ?? self.refStore.element(for: $0)?.frame()
        }
        let sourceFrame = ActionVisualizationPlanner.sourceReference(of: statement).flatMap {
            self.refStore.frame(for: $0) ?? self.refStore.element(for: $0)?.frame()
        }
        let screen = ActionVisualizationPlanner.screen(containing: targetFrame ?? sourceFrame)
        let request = ActionVisualizationRequest(
            statement: statement,
            targetFrame: targetFrame,
            sourceFrame: sourceFrame,
            leadInDuration: ActionVisualizationPlanner.leadInDuration(current: statement, next: next))
        _ = screen
        try await self.visualizer.visualize(request)
    }
}
