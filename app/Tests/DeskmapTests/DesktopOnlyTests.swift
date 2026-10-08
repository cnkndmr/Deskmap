import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// "Yalnız masaüstü" pini: pencere masaüstünü izler, çerçevesi serbest.
struct DesktopOnlyTests {

    private func screen(_ id: String, frame: CGRect) -> ScreenInfo {
        ScreenInfo(id: id, uuid: id.uppercased(), name: id, isBuiltin: id == "builtin",
                   frame: frame, visibleFrame: frame)
    }

    private var laptop: ScreenInfo { screen("builtin", frame: CGRect(x: 0, y: 0, width: 1000, height: 800)) }
    private var monitor: ScreenInfo { screen("external", frame: CGRect(x: 1000, y: 0, width: 2000, height: 1000)) }

    @Test func codableKeepsFlagAndOmitsItWhenOff() throws {
        let encoded = try JSONEncoder().encode(WindowLayout.anyFrame)
        let back = try JSONDecoder().decode(WindowLayout.self, from: encoded)
        #expect(back.isDesktopOnly)
        #expect(back.label == "Desktop only")
        let plain = String(decoding: try JSONEncoder().encode(WindowLayout.full), as: UTF8.self)
        #expect(!plain.contains("desktopOnly"))
        let old = try JSONDecoder().decode(WindowLayout.self, from: Data(#"{"x":0,"y":0,"w":1,"h":1}"#.utf8))
        #expect(!old.isDesktopOnly)
        #expect(WindowLayout.anyFrame != .full)
    }

    @Test func sameScreenWindowIsLeftAlone() {
        let screens = [laptop, monitor]
        let frame = CGRect(x: 1200, y: 100, width: 300, height: 200)
        #expect(Router.desktopOnlyLayout(frame: frame, target: monitor, screens: screens) == nil)
        #expect(Router.desktopOnlyLayout(frame: nil, target: monitor, screens: screens) == nil)
    }

    @Test func otherScreenWindowMovesProportionally() throws {
        let screens = [laptop, monitor]
        // Laptop'ta sol yarım → monitörde sol yarım.
        let frame = CGRect(x: 0, y: 0, width: 500, height: 800)
        let layout = try #require(Router.desktopOnlyLayout(frame: frame, target: monitor, screens: screens))
        #expect(!layout.isDesktopOnly)
        let rect = Router.targetFrame(for: layout, on: monitor, screens: screens)
        #expect(rect.width == 1000)
        #expect(rect.minX == 1000)
    }
}
