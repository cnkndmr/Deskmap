import CoreGraphics
import Testing
@testable import Deskmap

/// Space durumu bilinmiyorsa pencere yalnız listelenir (P0-3).
struct UnknownSpaceTests {

    private func types(_ table: [UInt64: Int]) -> (UInt64) -> Int? { { table[$0] } }

    @Test func unreadableMembershipIsUnknown() {
        let state = Router.spaceState(spaces: nil, type: types([:]))
        #expect(!state.known)
        #expect(state.spaces.isEmpty)
    }

    @Test func emptyMembershipIsUnknownNotVisible() {
        // Eskiden boş liste "görünür" sayılıyordu.
        #expect(!Router.spaceState(spaces: [], type: types([:])).known)
    }

    @Test func emptyReadMeansSpacelessHelperWindow() {
        #expect(Router.isSpaceless([], pinned: false))
        #expect(!Router.isSpaceless([], pinned: true))
        #expect(!Router.isSpaceless(nil, pinned: false))
        #expect(!Router.isSpaceless([6], pinned: false))
    }

    @Test func unknownSpaceTypeIsUnknownNotUserSpace() {
        let state = Router.spaceState(spaces: [5], type: types([:]))
        #expect(!state.known)
        #expect(!state.isFullscreen)
    }

    @Test func knownSpacesAndFullscreenDetection() {
        let normal = Router.spaceState(spaces: [5], type: types([5: 0]))
        #expect(normal.known && !normal.isFullscreen)
        let full = Router.spaceState(spaces: [5, 6], type: types([5: 0, 6: 4]))
        #expect(full.known && full.isFullscreen)
    }

    @Test func unknownStateIsNotRoutedWhenSkyLightReads() {
        let unknown = Router.WindowState(spaces: [], isFullscreen: false, frame: nil,
                                         isMinimized: false, spacesKnown: false)
        let known = Router.WindowState(spaces: [5], isFullscreen: false, frame: nil,
                                       isMinimized: false, spacesKnown: true)
        #expect(!Router.canRoute(unknown, spacesReadable: true))
        #expect(Router.canRoute(known, spacesReadable: true))
        // SkyLight hiç yoksa: yalnız ekran + düzen, eski davranış.
        #expect(Router.canRoute(unknown, spacesReadable: false))
    }
}
