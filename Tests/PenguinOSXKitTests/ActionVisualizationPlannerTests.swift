import AppKit
@testable import PenguinOSXKit
import XCTest

final class ActionVisualizationPlannerTests: XCTestCase {
    func testVisualizedStatementsAreRecognized() {
        XCTAssertTrue(ActionVisualizationPlanner.isVisualized(.sendClick(targetRef: "abcdef123")))
        XCTAssertTrue(ActionVisualizationPlanner.isVisualized(.sendDrag(sourceRef: "abcdef123", targetRef: "fedcba321")))
        XCTAssertFalse(ActionVisualizationPlanner.isVisualized(.sleep(milliseconds: 50)))
        XCTAssertFalse(ActionVisualizationPlanner.isVisualized(.open(app: "Finder")))
    }

    func testLeadInShrinksForRepeatedTarget() {
        let current = OXAStatement.sendClick(targetRef: "abcdef123")
        let next = OXAStatement.sendRightClick(targetRef: "abcdef123")
        XCTAssertEqual(ActionVisualizationPlanner.leadInDuration(current: current, next: next), .milliseconds(120))
        XCTAssertEqual(ActionVisualizationPlanner.leadInDuration(current: current, next: nil), .milliseconds(180))
    }

    func testClampedCenterStaysWithinBounds() {
        let center = ActionVisualizationPlanner.clampedCenter(
            for: CGRect(x: -100, y: -50, width: 20, height: 20),
            in: CGRect(x: 0, y: 0, width: 500, height: 400))
        XCTAssertEqual(center, CGPoint(x: 0, y: 0))
    }
}
