import Foundation
import Testing
@testable import JoystickCore

@Suite("Adaptive remote window geometry")
struct RemoteWindowLayoutTests {
    @Test func compactWindowKeepsAllSpaceForTheRemote() {
        let size = CGSize(width: 374, height: 820)
        let layout = RemoteWindowLayout(size: size, division: nil)

        #expect(layout.arrangement == .compact)
        #expect(layout.controls == CGRect(origin: .zero, size: size))
        #expect(layout.companion == nil)
        #expect(!layout.usesTrailingShortcuts)
    }

    @Test func fullyOpenWindowKeepsTheRemoteAsTheOnlyPane() {
        let size = CGSize(width: 840, height: 590)
        let layout = RemoteWindowLayout(size: size, division: nil)

        #expect(layout.arrangement == .compact)
        #expect(layout.controls == CGRect(origin: .zero, size: size))
        #expect(layout.companion == nil)
        #expect(layout.hasWideFlatSurface)
        #expect(!layout.usesTrailingShortcuts)
    }

    @Test func shortLandscapeWindowMakesRoomForTrailingShortcuts() {
        let size = CGSize(width: 680, height: 360)
        let layout = RemoteWindowLayout(size: size, division: nil)

        #expect(layout.controls == CGRect(origin: .zero, size: size))
        #expect(layout.companion == nil)
        #expect(layout.usesTrailingShortcuts)
        #expect(!layout.hasWideFlatSurface)
    }

    @Test func bookKeepsRemoteAndShortcutsOnEitherSideOfTheFold() throws {
        let fold = CGRect(x: 315, y: 0, width: 42, height: 760)
        let layout = RemoteWindowLayout(size: CGSize(width: 720, height: 760), division: fold)

        #expect(layout.arrangement == .book)
        #expect(layout.controls.maxX < fold.minX)
        #expect((try #require(layout.companion)).minX > fold.maxX)
        #expect(!layout.usesTrailingShortcuts)
        #expect(!layout.hasWideFlatSurface)
    }

    @Test func swappingBookSidesPreservesTheCameraExclusion() throws {
        let size = CGSize(width: 720, height: 700)
        let fold = CGRect(x: 340, y: 0, width: 40, height: size.height)
        let camera = CGRect(x: 635, y: 0, width: 65, height: 44)
        let left = RemoteWindowLayout(size: size, division: fold, occlusions: [camera])
        let right = RemoteWindowLayout(size: size, division: fold, occlusions: [camera], bookRemoteOnRight: true)

        #expect(right.controls == (try #require(left.companion)))
        #expect(right.companion == left.controls)
        #expect(!right.controls.intersects(camera))
    }

    @Test func tabletopKeepsTheControlsOnTheNearHalf() throws {
        let fold = CGRect(x: 0, y: 325, width: 740, height: 34)
        let layout = RemoteWindowLayout(size: CGSize(width: 740, height: 680), division: fold, bookRemoteOnRight: true)

        #expect(layout.arrangement == .tabletop)
        #expect(layout.controls.minY > fold.maxY)
        #expect((try #require(layout.companion)).maxY < fold.minY)
    }

    @Test func compactSplitViewDoesNotCoverTheFold() {
        let fold = CGRect(x: 290, y: 0, width: 30, height: 650)
        let layout = RemoteWindowLayout(size: CGSize(width: 335, height: 650), division: fold)

        #expect(layout.arrangement == .compact)
        #expect(layout.companion == nil)
        #expect(layout.controls.maxX <= fold.minX)
    }

    @Test func cameraExclusionResizesOnlyItsPane() throws {
        let size = CGSize(width: 720, height: 700)
        let camera = CGRect(x: 635, y: 0, width: 65, height: 44)
        let fold = CGRect(x: 340, y: 0, width: 40, height: size.height)
        let clear = RemoteWindowLayout(size: size, division: fold)
        let withCamera = RemoteWindowLayout(size: size, division: fold, occlusions: [camera])

        #expect(withCamera.controls == clear.controls)
        #expect(!(try #require(withCamera.companion)).intersects(camera))
    }
}
