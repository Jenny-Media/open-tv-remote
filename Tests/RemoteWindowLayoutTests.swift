import Foundation
import Testing
@testable import JoystickCore

@Suite("Adaptive remote window geometry")
struct RemoteWindowLayoutTests {
    @Test func compactWindowKeepsAllSpaceForTheRemote() {
        let size = CGSize(width: 374, height: 820)
        let layout = RemoteWindowLayout(size: size, expandsRemote: true, division: nil)

        #expect(layout.arrangement == .compact)
        #expect(layout.controls == CGRect(origin: .zero, size: size))
        #expect(layout.companion == nil)
    }

    @Test func openPhoneShowsCompanionWithoutChangingTheTabletLayout() throws {
        let size = CGSize(width: 720, height: 760)
        let phone = RemoteWindowLayout(size: size, expandsRemote: true, division: nil)
        let tablet = RemoteWindowLayout(size: size, expandsRemote: false, division: nil)

        #expect(phone.arrangement == .sideBySide)
        #expect(phone.controls.maxX < (try #require(phone.companion)).minX)
        #expect(tablet.arrangement == .compact)
    }

    @Test func bookPanesStraddleTheActualOffCenterFold() throws {
        let fold = CGRect(x: 315, y: 0, width: 42, height: 760)
        let layout = RemoteWindowLayout(size: CGSize(width: 720, height: 760), expandsRemote: true, division: fold)

        #expect(layout.arrangement == .sideBySide)
        #expect(layout.controls.maxX < fold.minX)
        #expect((try #require(layout.companion)).minX > fold.maxX)
    }

    @Test func tabletopKeepsTheControlsOnTheNearHalf() throws {
        let fold = CGRect(x: 0, y: 325, width: 740, height: 34)
        let layout = RemoteWindowLayout(size: CGSize(width: 740, height: 680), expandsRemote: true, division: fold)

        #expect(layout.arrangement == .tabletop)
        #expect(layout.controls.minY > fold.maxY)
        #expect((try #require(layout.companion)).maxY < fold.minY)
    }

    @Test func compactSplitViewDoesNotCoverTheFold() {
        let fold = CGRect(x: 290, y: 0, width: 30, height: 650)
        let layout = RemoteWindowLayout(size: CGSize(width: 335, height: 650), expandsRemote: true, division: fold)

        #expect(layout.arrangement == .compact)
        #expect(layout.companion == nil)
        #expect(layout.controls.maxX <= fold.minX)
    }

    @Test func cameraExclusionResizesOnlyItsPane() throws {
        let size = CGSize(width: 720, height: 700)
        let camera = CGRect(x: 635, y: 0, width: 65, height: 44)
        let clear = RemoteWindowLayout(size: size, expandsRemote: true, division: nil)
        let withCamera = RemoteWindowLayout(size: size, expandsRemote: true, division: nil, occlusions: [camera])

        #expect(withCamera.controls == clear.controls)
        #expect(!(try #require(withCamera.companion)).intersects(camera))
    }
}
