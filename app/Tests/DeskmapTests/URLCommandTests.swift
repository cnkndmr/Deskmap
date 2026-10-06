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

/// Komut satırı aracının (`deskmap`) kullandığı komutlar.
struct URLCommandCLITests {

    @Test func windowCommands() {
        #expect(URLCommand.parse(URL(string: "deskmap://pin/1234/External/2?req=7")!)
                == .pin(window: 1234, screen: "external", desktop: 2))
        #expect(URLCommand.parse(URL(string: "deskmap://move/1234/builtin/1")!)
                == .move(window: 1234, screen: "builtin", desktop: 1))
        #expect(URLCommand.parse(URL(string: "deskmap://unpin/1234")!) == .unpin(window: 1234))
        #expect(URLCommand.parse(URL(string: "deskmap://pin/abc/builtin/1")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://move/1234/builtin/0")!) == nil)
        #expect(URLCommand.parse(URL(string: "deskmap://pin/1234/builtin")!) == nil)
    }

    @Test func reloadStatusAndRuleRemove() {
        #expect(URLCommand.parse(URL(string: "deskmap://reload")!) == .reload)
        #expect(URLCommand.parse(URL(string: "deskmap://status?req=x1")!) == .status)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-remove/ABC-1")!) == .removeRule(id: "ABC-1"))
        #expect(URLCommand.parse(URL(string: "deskmap://rule-remove")!) == nil)
    }

    @Test func ruleAddDecodesJSON() throws {
        let json = #"{"id":"R1","appName":"cmux","bundleID":"","tokens":[],"docked":{"screen":"external","desktop":2,"layout":{"x":0,"y":0,"w":1,"h":1}}}"#
        var components = URLComponents(string: "deskmap://rule-add")!
        components.queryItems = [URLQueryItem(name: "json", value: json), URLQueryItem(name: "req", value: "9")]
        guard case .addRule(let rule)? = URLCommand.parse(components.url!) else {
            Issue.record("rule-add did not parse"); return
        }
        #expect(rule.id == "R1" && rule.appName == "cmux")
        #expect(rule.docked?.screen == "external" && rule.docked?.desktop == 2)
        #expect(URLCommand.parse(URL(string: "deskmap://rule-add?json=notjson")!) == nil)
    }

    @Test func requestIDIsRead() {
        #expect(URLCommands.requestID(URL(string: "deskmap://pause?req=42")!) == "42")
        #expect(URLCommands.requestID(URL(string: "deskmap://pause")!) == nil)
    }
}
