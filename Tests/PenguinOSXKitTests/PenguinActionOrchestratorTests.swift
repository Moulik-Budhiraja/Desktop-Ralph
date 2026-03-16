@testable import PenguinOSXKit
import XCTest

@MainActor
final class PenguinActionOrchestratorTests: XCTestCase {
    func testExecutionOrderIsVisualizeThenExecuteThenFlash() async throws {
        let visualizer = RecordingVisualizer()
        let refStore = SelectorActionRefStore()
        let executor = RecordingExecutor(refStore: refStore)
        let orchestrator = PenguinActionOrchestrator(refStore: refStore, visualizer: visualizer, executor: executor)

        _ = try await orchestrator.execute(programSource: "sleep 10;")

        XCTAssertEqual(visualizer.events, ["idle"])
        XCTAssertEqual(executor.events, ["preflight", "execute:sleep 10"])
    }
}

@MainActor
private final class RecordingVisualizer: ActionVisualizer {
    var events: [String] = []

    func visualize(_ request: ActionVisualizationRequest) async throws {
        self.events.append("visualize")
    }

    func flashAction() async {
        self.events.append("flash")
    }

    func idle() async {
        self.events.append("idle")
    }
}

@MainActor
private final class RecordingExecutor: PenguinActionExecutor {
    var events: [String] = []

    override func preflight(program: OXAProgram) throws {
        self.events.append("preflight")
    }

    override func execute(_ statement: OXAStatement) throws -> StatementExecutionResult {
        switch statement {
        case let .sleep(milliseconds):
            self.events.append("execute:sleep \(milliseconds)")
        default:
            self.events.append("execute")
        }
        return .none
    }

    override func describe(_ statement: OXAStatement) -> String {
        switch statement {
        case let .sleep(milliseconds):
            return "sleep \(milliseconds)"
        default:
            return "noop"
        }
    }
}
