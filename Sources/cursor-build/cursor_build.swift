import Foundation
import PenguinOSXKit

@main
struct CursorBuild {
    static func main() async {
        let exitCode = await PenguinOSXApp().run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(exitCode)
    }
}
