import Testing
@testable import osx

@Suite("Ralph Sprite Animation")
struct RalphSpriteAnimationTests {
    @MainActor
    @Test("Loads a non-repeating button click animation")
    func loadsButtonClickAnimation() throws {
        let animations = try RalphSpriteAssetLoader.loadAnimationSet()

        #expect(animations.clickDown.repeats == false)
        #expect(animations.clickDown.frames.count == 8)
        #expect(animations.clickDown.totalDuration > 0)
    }
}
