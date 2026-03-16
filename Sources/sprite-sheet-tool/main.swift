import Foundation
import PenguinOSXKit

@main
struct SpriteSheetTool {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let sourcePath = arguments.first else {
            FileHandle.standardError.write(Data("usage: sprite-sheet-tool <source.png> [output-directory]\n".utf8))
            Foundation.exit(64)
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let outputURL: URL
        if arguments.count > 1 {
            outputURL = URL(fileURLWithPath: String(arguments[1]))
        } else {
            outputURL = sourceURL.deletingLastPathComponent().appendingPathComponent("cropped-sprites")
        }

        let cropper = SpriteSheetCropper()
        let manifest = try cropper.exportSprites(from: sourceURL, to: outputURL)
        print("Exported \(manifest.spriteCount) sprites to \(outputURL.path)")
    }
}
