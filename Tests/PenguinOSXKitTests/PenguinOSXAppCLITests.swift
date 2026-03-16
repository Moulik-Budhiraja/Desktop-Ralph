import XCTest
@testable import PenguinOSXKit

final class PenguinOSXAppCLITests: XCTestCase {
    func testDefaultCommandLaunchesAutonomousApp() throws {
        let command = try CLICommand.parse(arguments: [])

        guard case let .app(configuration) = command else {
            return XCTFail("Expected app command.")
        }

        XCTAssertEqual(configuration.launchMode, .autonomous)
        XCTAssertEqual(configuration.controlSocketPath, RalphControlClient.defaultSocketPath())
    }

    func testParseControlledAppCommand() throws {
        let command = try CLICommand.parse(arguments: [
            "app",
            "--controlled",
            "--control-socket",
            "/tmp/custom-ralph.sock",
        ])

        guard case let .app(configuration) = command else {
            return XCTFail("Expected app command.")
        }

        XCTAssertEqual(configuration.launchMode, .controlled)
        XCTAssertEqual(configuration.controlSocketPath, "/tmp/custom-ralph.sock")
    }

    func testParseRalphSayCommand() throws {
        let command = try CLICommand.parse(arguments: [
            "ralph",
            "say",
            "Ralph says hello",
            "--socket",
            "/tmp/custom-ralph.sock",
        ])

        guard case let .ralph(ralphCommand) = command else {
            return XCTFail("Expected Ralph command.")
        }

        guard case let .say(text, socketPath) = ralphCommand else {
            return XCTFail("Expected Ralph say command.")
        }

        XCTAssertEqual(text, "Ralph says hello")
        XCTAssertEqual(socketPath, "/tmp/custom-ralph.sock")
    }

    func testParseRalphMoveCommand() throws {
        let command = try CLICommand.parse(arguments: [
            "ralph",
            "move",
            "--x",
            "320",
            "--socket",
            "/tmp/custom-ralph.sock",
            "--y",
            "180",
            "--duration",
            "1.4",
        ])

        guard case let .ralph(ralphCommand) = command else {
            return XCTFail("Expected Ralph command.")
        }

        guard case let .move(x, y, duration, socketPath) = ralphCommand else {
            return XCTFail("Expected Ralph move command.")
        }

        XCTAssertEqual(x, 320)
        XCTAssertEqual(y, 180)
        XCTAssertEqual(duration, 1.4)
        XCTAssertEqual(socketPath, "/tmp/custom-ralph.sock")
    }

    func testParseRalphNudgeCommand() throws {
        let command = try CLICommand.parse(arguments: [
            "ralph",
            "nudge",
            "--dx",
            "-64",
            "--dy",
            "48",
        ])

        guard case let .ralph(ralphCommand) = command else {
            return XCTFail("Expected Ralph command.")
        }

        guard case let .nudge(dx, dy, duration, socketPath) = ralphCommand else {
            return XCTFail("Expected Ralph nudge command.")
        }

        XCTAssertEqual(dx, -64)
        XCTAssertEqual(dy, 48)
        XCTAssertEqual(duration, 0.8)
        XCTAssertEqual(socketPath, RalphControlClient.defaultSocketPath())
    }
}
