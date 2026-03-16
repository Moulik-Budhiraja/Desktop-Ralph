import CoreGraphics
import PenguinOSXKit
import Testing

struct SpriteSheetCroppingTests {
    @Test
    func assignsLabelsInRowOrder() {
        let cropper = SpriteSheetCropper(
            config: .init(
                rowMergeTolerance: 80,
                rowLabels: ["idle", "walk", "run"]
            )
        )

        let bounds = [
            CGRect(x: 10, y: 10, width: 100, height: 100),
            CGRect(x: 130, y: 10, width: 100, height: 100),
            CGRect(x: 15, y: 170, width: 100, height: 100),
            CGRect(x: 140, y: 180, width: 100, height: 100),
            CGRect(x: 20, y: 340, width: 100, height: 100),
        ]

        let labels = cropper.labelSprites(bounds).map(\.label)

        #expect(labels == [
            "idle_01",
            "idle_02",
            "walk_01",
            "walk_02",
            "run_01",
        ])
    }
}
