import Foundation
import Testing
@testable import Deskmap

/// `deskmap://` (birincil) ve eski `spacerouter://` (Deskmap'in eski adı)
/// şemalarının aynı komutlara çözüldüğünü doğrular; ikisi de kalıcı olarak
/// kabul edilir (Shortcuts/Raycast gibi dış kurulumlar bozulmasın).
struct URLCommandTests {

    @Test func primarySchemeParsesKnownCommands() {
        #expect(URLCommand.parse(URL(string: "deskmap://reapply")!) == .reapply)
        #expect(URLCommand.parse(URL(string: "deskmap://pause")!) == .pause)
        #expect(URLCommand.parse(URL(string: "deskmap://resume")!) == .resume)
        #expect(URLCommand.parse(URL(string: "deskmap://toggle")!) == .toggle)
        #expect(URLCommand.parse(URL(string: "deskmap://next-profile")!) == .nextProfile)
        #expect(URLCommand.parse(URL(string: "deskmap://profile/Ofis")!) == .profile(name: "Ofis"))
        #expect(URLCommand.parse(URL(string: "deskmap://add-desktop/External")!)
                == .addDesktop(screen: "external"))
        #expect(URLCommand.parse(URL(string: "deskmap:add-desktop/builtin")!)
                == .addDesktop(screen: "builtin"))
        #expect(URLCommand.parse(URL(string: "deskmap://add-desktop")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://remove-desktop/external/3")!)
                == .removeDesktop(screen: "external", desktop: 3))
        #expect(URLCommand.parse(URL(string: "deskmap://remove-desktop/external")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://remove-desktop/external/0")!) == nil)
    }

    @Test func legacySchemeStillParsesTheSameCommands() {
        #expect(URLCommand.parse(URL(string: "spacerouter://reapply")!) == .reapply)
        #expect(URLCommand.parse(URL(string: "spacerouter://pause")!) == .pause)
        #expect(URLCommand.parse(URL(string: "spacerouter://resume")!) == .resume)
        #expect(URLCommand.parse(URL(string: "spacerouter://toggle")!) == .toggle)
        #expect(URLCommand.parse(URL(string: "spacerouter://next-profile")!) == .nextProfile)
        #expect(URLCommand.parse(URL(string: "spacerouter://profile/Ofis")!) == .profile(name: "Ofis"))
    }

    @Test func legacySchemeIsCaseInsensitiveAndHostless() {
        #expect(URLCommand.parse(URL(string: "SpaceRouter://Reapply")!) == .reapply)
        #expect(URLCommand.parse(URL(string: "spacerouter:profile/Ofis")!) == .profile(name: "Ofis"))
    }

    @Test func unknownSchemeReturnsNil() {
        #expect(URLCommand.parse(URL(string: "hammerspoon://reapply")!) == nil)
    }

    @Test func schemeConstantsAreDistinct() {
        #expect(URLCommand.scheme == "deskmap")
        #expect(URLCommand.legacyScheme == "spacerouter")
        #expect(URLCommand.scheme != URLCommand.legacyScheme)
    }
}
