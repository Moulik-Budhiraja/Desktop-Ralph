import XCTest
@testable import PenguinOSXKit

final class PenguinOSXAppTests: XCTestCase {
    func testCLICommandParsesRalphWanderDefaults() throws {
        let command = try CLICommand.parse(arguments: ["ralph", "wander"])

        guard case let .ralph(.wander(steps, minimumDistance, pauseDuration, socketPath)) = command else {
            return XCTFail("Expected Ralph wander command.")
        }

        XCTAssertEqual(steps, 6)
        XCTAssertEqual(minimumDistance, 220, accuracy: 0.001)
        XCTAssertEqual(pauseDuration, 0.55, accuracy: 0.001)
        XCTAssertEqual(socketPath, RalphControlClient.defaultSocketPath())
    }

    func testCLICommandParsesRalphWanderOptions() throws {
        let command = try CLICommand.parse(arguments: [
            "ralph",
            "wander",
            "--steps", "3",
            "--minimum-distance", "300",
            "--pause", "0.2",
            "--socket", "/tmp/ralph-demo.sock",
        ])

        guard case let .ralph(.wander(steps, minimumDistance, pauseDuration, socketPath)) = command else {
            return XCTFail("Expected Ralph wander command.")
        }

        XCTAssertEqual(steps, 3)
        XCTAssertEqual(minimumDistance, 300, accuracy: 0.001)
        XCTAssertEqual(pauseDuration, 0.2, accuracy: 0.001)
        XCTAssertEqual(socketPath, "/tmp/ralph-demo.sock")
    }

    func testCLICommandRejectsNonPositiveWanderSteps() {
        XCTAssertThrowsError(try CLICommand.parse(arguments: [
            "ralph",
            "wander",
            "--steps", "0",
        ]))
    }
}
