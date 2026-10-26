import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

private func u(_ s: String) -> URL { URL(string: s)! }
private func parse(_ s: String) -> URLCommand? { URLCommand.parse(u(s)) }

/// Ayrıştırma: şema, büyük/küçük harf, takma adlar, Unicode adlar, eksik/bozuk parametre.
struct URLCommandParsingCoverageTests {

    @Test func schemeAndCommandCaseInsensitive() {
        #expect(parse("DESKMAP://REAPPLY") == .reapply)
        #expect(parse("Deskmap://Pause") == .pause)
        #expect(parse("deskmap:resume") == .resume)
        #expect(parse("deskmap:toggle") == .toggle)
        #expect(parse("deskmap:profile/Ofis") == .profile(name: "Ofis"))
    }

    @Test func emptyOrUnknownCommandsAreNil() {
        #expect(parse("deskmap://") == nil)
        #expect(parse("deskmap:") == nil)
        #expect(parse("deskmap://frobnicate") == nil)
        #expect(parse("deskmap://frobnicate/1/2/3") == nil)
        #expect(parse("deskmap://reapply2") == nil)
        #expect(parse("https://reapply") == nil)
        #expect(parse("deskmapx://reapply") == nil)
    }

    @Test func nextProfileAndDesktopAliases() {
        #expect(parse("deskmap://next") == .nextProfile)
        #expect(parse("deskmap://nextprofile") == .nextProfile)
        #expect(parse("deskmap://adddesktop/Builtin") == .addDesktop(screen: "builtin"))
        #expect(parse("deskmap://removedesktop/External-2/4")
                == .removeDesktop(screen: "external-2", desktop: 4))
        #expect(parse("deskmap://remove-desktop/builtin/abc") == nil)
        #expect(parse("deskmap://remove-desktop/builtin/-1") == nil)
        #expect(parse("deskmap://remove-desktop/builtin/2/extra") == nil)
        #expect(parse("deskmap://add-desktop/%20%20") == nil)
    }

    @Test func profileNames() {
        #expect(parse("deskmap://profile/%C3%96zel%20Masa%20%C5%9E") == .profile(name: "Özel Masa Ş"))
        #expect(parse("deskmap://profile/Ev/Ofis") == .profile(name: "Ev/Ofis"))
        #expect(parse("deskmap://profile?name=Ev%2FOfis") == .profile(name: "Ev/Ofis"))
        // Sorgudaki ad yoldakini ezer; anahtar büyük/küçük harfe duyarsız.
        #expect(parse("deskmap://profile/Yol?name=Sorgu") == .profile(name: "Sorgu"))
        #expect(parse("deskmap://profile?NAME=Sorgu") == .profile(name: "Sorgu"))
        #expect(parse("deskmap://profile") == nil)
        #expect(parse("deskmap://profile?name=") == nil)
        #expect(parse("deskmap://profile?name=%20%09") == nil)
        #expect(parse("deskmap://profile/%20") == nil)
        #expect(parse("deskmap://profile?name=%20Ofis%20") == .profile(name: "Ofis"))
        #expect(parse("deskmap://profile?name=%F0%9F%96%A5%20Masa") == .profile(name: "🖥 Masa"))
    }

    @Test func pinVariants() {
        #expect(parse("deskmap://pin/12/Builtin/2") == .pin(window: 12, screen: "builtin", desktop: 2))
        #expect(parse("deskmap://pin/12/builtin/2?layout=other")
                == .pin(window: 12, screen: "builtin", desktop: 2, desktopOnly: false))
        #expect(parse("deskmap://pin/12/builtin/2?layout=desktop-only")
                == .pin(window: 12, screen: "builtin", desktop: 2, desktopOnly: true))
        #expect(parse("deskmap://pin/12/builtin/0") == nil)
        #expect(parse("deskmap://pin/12/builtin/-3") == nil)
        #expect(parse("deskmap://pin/12/builtin/x") == nil)
        #expect(parse("deskmap://pin/-1/builtin/1") == nil)
        #expect(parse("deskmap://pin/99999999999/builtin/1") == nil)
        #expect(parse("deskmap://pin/12/builtin/1/9") == nil)
        #expect(parse("deskmap://pin") == nil)
        #expect(parse("deskmap://pin/12") == nil)
    }

    @Test func pinToNameVariants() {
        #expect(parse("deskmap://pin/12?name=Ara%C5%9Ft%C4%B1rma")
                == .pinToName(window: 12, name: "Araştırma"))
        #expect(parse("deskmap://pin/12?name=%20Mail%20&layout=desktop-only")
                == .pinToName(window: 12, name: "Mail", desktopOnly: true))
        #expect(parse("deskmap://pin/12?name=") == nil)
        #expect(parse("deskmap://pin/12?name=%20") == nil)
        #expect(parse("deskmap://pin/abc?name=X") == nil)
        // Üç yol parçası varsa ad değil ekran/masaüstü yolu geçerlidir.
        #expect(parse("deskmap://pin/12/builtin/1?name=X")
                == .pin(window: 12, screen: "builtin", desktop: 1))
    }

    @Test func moveUnpinAndFree() {
        #expect(parse("deskmap://move/7/External-2/3") == .move(window: 7, screen: "external-2", desktop: 3))
        #expect(parse("deskmap://move/7/builtin") == nil)
        #expect(parse("deskmap://unpin") == nil)
        #expect(parse("deskmap://unpin/7/8") == nil)
        #expect(parse("deskmap://unpin/x") == nil)
        #expect(parse("deskmap://free/7/30") == .freeMove(window: 7, duration: 1800))
        #expect(parse("deskmap://free/7/lock") == .freeMove(window: 7, duration: Router.freeMoveUntilLock))
        #expect(parse("deskmap://free/7/LOCK") == .freeMove(window: 7, duration: Router.freeMoveUntilLock))
        #expect(parse("deskmap://free/7/0") == nil)
        #expect(parse("deskmap://free/7/-5") == nil)
        #expect(parse("deskmap://free/7/1.5") == nil)
        #expect(parse("deskmap://free/7/soon") == nil)
        #expect(parse("deskmap://free/7") == nil)
        #expect(parse("deskmap://free/x/5") == nil)
        #expect(parse("deskmap://free-end/7") == .endFreeMove(window: 7))
        #expect(parse("deskmap://free-end") == nil)
        #expect(parse("deskmap://free-end/x") == nil)
    }

    @Test func quitAndBackupTakeNoExtraParts() {
        #expect(parse("deskmap://quit") == .quit)
        #expect(parse("deskmap://quit/now") == nil)
        #expect(parse("deskmap://backup-now") == .backupNow)
        #expect(parse("deskmap://backup-now/x") == nil)
        #expect(parse("deskmap://backup-restore/2026-10-01T10%3A00") == .restoreBackup(id: "2026-10-01T10:00"))
        #expect(parse("deskmap://backup-restore") == nil)
        #expect(parse("deskmap://backup-restore/a/b") == nil)
    }

    @Test func ruleAddAndRemoveEdgeCases() {
        #expect(parse("deskmap://rule-add") == nil)
        #expect(parse("deskmap://rule-add?json=") == nil)
        // Uygulama adı ve bundle kimliği olmayan kural hiçbir pencereye uymaz;
        // beklenen: reddedilmesi. Gerçek: `{}` boş bir kural olarak eklenir
        // (Rule.init(from:) her alanı yumuşak okur, URLCommands.swift:~190 denetlemez).
        withKnownIssue("rule-add boş kuralı (appName/bundleID yok) reddetmiyor") {
            #expect(parse("deskmap://rule-add?json=%7B%7D") == nil)
        }
        #expect(parse("deskmap://rule-add?x=1") == nil)
        #expect(parse("deskmap://rule-remove/a/b") == nil)
        #expect(parse("deskmap://rule-remove/K%C3%BCral-%C4%B01") == .removeRule(id: "Küral-İ1"))
    }

    @Test func ruleAddKeepsUnicodeAppName() throws {
        let json = #"{"id":"R2","appName":"Şablon Üretici","bundleID":"b","tokens":["çalışma","İş"]}"#
        var c = URLComponents(string: "deskmap://rule-add")!
        c.queryItems = [URLQueryItem(name: "json", value: json)]
        guard case .addRule(let rule)? = URLCommand.parse(c.url!) else {
            Issue.record("rule-add did not parse"); return
        }
        #expect(rule.appName == "Şablon Üretici")
        #expect(rule.tokens == ["çalışma", "İş"])
        #expect(rule.docked == nil && rule.undocked == nil)
    }

    private func profileSet(_ json: String, activate: String? = nil) -> URL {
        var c = URLComponents(string: "deskmap://profile-set")!
        c.queryItems = [URLQueryItem(name: "json", value: json)]
            + (activate.map { [URLQueryItem(name: "activate", value: $0)] } ?? [])
        return c.url!
    }

    @Test func profileSetActivateFlagAndNames() {
        for (flag, expected) in [("1", true), ("true", true), ("TRUE", true), ("0", false),
                                 ("yes", false), ("", false)] {
            guard case .setProfile(_, let activate)? =
                    URLCommand.parse(profileSet(#"{"name":"A","rules":[]}"#, activate: flag)) else {
                Issue.record("profile-set \(flag) did not parse"); continue
            }
            #expect(activate == expected, "activate=\(flag)")
        }
        guard case .setProfile(let p, _)? =
                URLCommand.parse(profileSet(#"{"name":"  Çalışma Masası  ","rules":[]}"#)) else {
            Issue.record("profile-set did not parse"); return
        }
        #expect(p.name == "Çalışma Masası")
        // Boş kimlik yeni kimlik üretir (boş bırakılmaz).
        guard case .setProfile(let q, _)? =
                URLCommand.parse(profileSet(#"{"id":"","name":"X","rules":[]}"#)) else {
            Issue.record("profile-set did not parse"); return
        }
        #expect(!q.id.isEmpty)
        #expect(URLCommand.parse(profileSet(#"{"rules":[]}"#)) == nil)
        #expect(URLCommand.parse(profileSet(#"{"name":"X"}"#)) == nil)
        #expect(URLCommand.parse(profileSet(#"{"name":"","rules":[]}"#)) == nil)
    }

    @Test func profileRenameEdgeCases() {
        #expect(parse("deskmap://profile-rename/Ev/Ofis?name=Yeni") == .renameProfile(from: "Ev/Ofis", to: "Yeni"))
        #expect(parse("deskmap://profile-rename/Ofis?name=%20") == nil)
        #expect(parse("deskmap://profile-rename/Ofis?name=") == nil)
        #expect(parse("deskmap://profile-rename/%20?name=X") == nil)
        #expect(parse("deskmap://profile-rename/%C3%96zel?name=%C3%9C%C3%A7")
                == .renameProfile(from: "Özel", to: "Üç"))
    }

    @Test func profileExportEdgeCases() {
        #expect(parse("deskmap://profile-export") == nil)
        #expect(parse("deskmap://profile-export?name=Ofis") == nil)
        #expect(parse("deskmap://profile-export?path=") == nil)
        #expect(parse("deskmap://profile-export?path=/tmp/x.json&name=")
                == .exportProfile(name: nil, path: "/tmp/x.json"))
        #expect(parse("deskmap://profile-export?path=/tmp/%C3%BCr%C3%BCn.json")
                == .exportProfile(name: nil, path: "/tmp/ürün.json"))
    }

    @Test func desktopMoveEdgeCases() {
        #expect(parse("deskmap://desktop-move/builtin/1/2?mode=DOCKED")
                == .moveDesktop(screen: "builtin", from: 1, to: 2, mode: .docked))
        #expect(parse("deskmap://desktop-move/builtin/1") == nil)
        #expect(parse("deskmap://desktop-move/builtin/1/2/3") == nil)
        #expect(parse("deskmap://desktop-move/builtin/1/0") == nil)
        #expect(parse("deskmap://desktop-move/builtin/a/2") == nil)
    }

    @Test func saveAndCopyLayout() {
        #expect(parse("deskmap://rule-save-layout/R1?window=-4") == nil)
        #expect(parse("deskmap://rule-save-layout/R1/R2") == nil)
        #expect(parse("deskmap://rule-copy-layout/R1?from=docked") == .copyLayout(rule: "R1", from: .docked))
        #expect(parse("deskmap://rule-copy-layout/R1?from=UNDOCKED") == .copyLayout(rule: "R1", from: .undocked))
        #expect(parse("deskmap://rule-copy-layout/R1?from=both") == nil)
        #expect(parse("deskmap://rule-copy-layout/R1") == nil)
        #expect(parse("deskmap://rule-copy-layout?from=docked") == nil)
        #expect(parse("deskmap://rule-copy-layout/R1/R2?from=docked") == nil)
    }

    @Test func desktopName() {
        #expect(parse("deskmap://desktop-name/External/2?name=Ara%C5%9Ft%C4%B1rma")
                == .nameDesktop(screen: "external", desktop: 2, name: "Araştırma"))
        #expect(parse("deskmap://desktop-name/builtin/1?name=Mail&mode=undocked")
                == .nameDesktop(screen: "builtin", desktop: 1, name: "Mail", mode: .undocked))
        // Ad verilmezse boş ad: adı silme isteği.
        #expect(parse("deskmap://desktop-name/builtin/1") == .nameDesktop(screen: "builtin", desktop: 1, name: ""))
        #expect(parse("deskmap://desktop-name/builtin/0?name=X") == nil)
        #expect(parse("deskmap://desktop-name/builtin?name=X") == nil)
        #expect(parse("deskmap://desktop-name/builtin/1?name=X&mode=nope") == nil)
    }

    @Test func planDesktopsBoundaries() {
        #expect(parse("deskmap://plan-desktops/builtin/1") == .planDesktops(screen: "builtin", count: 1, mode: nil))
        #expect(parse("deskmap://plan-desktops/builtin/16") == .planDesktops(screen: "builtin", count: 16, mode: nil))
        #expect(parse("deskmap://plan-desktops/builtin/-1") == nil)
        #expect(parse("deskmap://plan-desktops/builtin/two") == nil)
    }

    @Test func screenRoleCommands() {
        #expect(parse("deskmap://screen-role/ABCD-1234/External-2")
                == .screenRole(display: "ABCD-1234", role: "external-2"))
        #expect(parse("deskmap://screen-role/ABCD/builtin") == nil)
        #expect(parse("deskmap://screen-role/ABCD/laptop") == nil)
        #expect(parse("deskmap://screen-role/ABCD") == nil)
        #expect(parse("deskmap://screen-role") == nil)
        #expect(parse("deskmap://screen-role-forget") == .forgetScreenRoles)
        #expect(parse("deskmap://screen-role-forget/ABCD") == .forgetScreen(display: "ABCD"))
        #expect(parse("deskmap://screen-role-forget/ABCD/EF") == nil)
    }

    @Test func requestIDEdgeCases() {
        #expect(URLCommands.requestID(u("deskmap://status?req=")) == "")
        #expect(URLCommands.requestID(u("deskmap://status?other=1&req=a%20b")) == "a b")
        #expect(URLCommands.requestID(u("deskmap://status?REQ=1")) == nil)
        #expect(URLCommands.requestID(u("deskmap:status?req=9")) == "9")
        #expect(URLCommands.requestID(u("deskmap://status?req=1&req=2")) == "1")
        #expect(URLCommand.parse(u("deskmap://reapply?req=1&foo=bar")) == .reapply)
    }
}

/// `connectedDisplay` ve `copyLayoutError` saf yardımcıları.
struct URLCommandPureHelperTests {

    private let displays: [(role: String, display: DisplayRoles.Display)] = [
        ("external", .init(uuid: "{ABCD1234-0000-1111-2222-333344445555}", minX: 0, minY: 0, name: "A")),
        ("external-2", .init(uuid: "ABCD9999-0000-1111-2222-333344445555", minX: 1, minY: 0, name: "B")),
        ("external-3", .init(uuid: "FEED0001-0000-1111-2222-333344445555", minX: 2, minY: 0, name: "C")),
    ]

    @Test func connectedDisplayByRole() {
        #expect(URLCommands.connectedDisplay("external-2", in: displays) == "ABCD9999-0000-1111-2222-333344445555")
        #expect(URLCommands.connectedDisplay("EXTERNAL", in: displays) == "{ABCD1234-0000-1111-2222-333344445555}")
        #expect(URLCommands.connectedDisplay("external-9", in: displays) == nil)
    }

    @Test func connectedDisplayByUUIDPrefix() {
        #expect(URLCommands.connectedDisplay("feed", in: displays) == "FEED0001-0000-1111-2222-333344445555")
        #expect(URLCommands.connectedDisplay("{abcd1234", in: displays) == "{ABCD1234-0000-1111-2222-333344445555}")
        // "ABCD" iki monitöre uyar: belirsiz, nil.
        #expect(URLCommands.connectedDisplay("abcd", in: displays) == nil)
        // 4 karakterden kısa önek reddedilir.
        #expect(URLCommands.connectedDisplay("fee", in: displays) == nil)
        #expect(URLCommands.connectedDisplay("", in: displays) == nil)
        #expect(URLCommands.connectedDisplay("abcd1234", in: []) == nil)
    }

    @Test func copyLayoutErrorMapping() {
        #expect(URLCommands.copyLayoutError(.copied, ruleID: "R") == nil)
        #expect(URLCommands.copyLayoutError(.alreadyEqual, ruleID: "R") == nil)
        for result in [Store.AdoptLayoutResult.ruleNotFound, .notSamePlace, .missingPlan] {
            let text = URLCommands.copyLayoutError(result, ruleID: "KURAL-7")
            #expect(text?.contains("KURAL-7") == true)
        }
        let texts = Set([Store.AdoptLayoutResult.ruleNotFound, .notSamePlace, .missingPlan].compactMap {
            URLCommands.copyLayoutError($0, ruleID: "R")
        })
        #expect(texts.count == 3)
    }

    @MainActor @Test func profileLookupExactThenCaseInsensitive() {
        let profiles = [Profile(id: "1", name: "ofis", rules: []), Profile(id: "2", name: "Ofis", rules: []),
                        Profile(id: "3", name: "Özel", rules: [])]
        #expect(URLCommands.profile(named: "Ofis", in: profiles)?.id == "2")
        #expect(URLCommands.profile(named: "ofis", in: profiles)?.id == "1")
        #expect(URLCommands.profile(named: "OFIS", in: profiles)?.id == "1")
        #expect(URLCommands.profile(named: "özel", in: profiles)?.id == "3")
        #expect(URLCommands.profile(named: "ÖZEL", in: profiles)?.id == "3")
        #expect(URLCommands.profile(named: "yok", in: profiles) == nil)
        #expect(URLCommands.profile(named: "", in: profiles) == nil)
    }
}

/// Komutların sahte (demo) Store/Router üzerinde çalıştırılması. AppModel.shared
/// kullanan komutlar (screen-role, desktop-name, plan/move-desktop, save-layout,
/// pin?name, backup) ve `reload` (gerçek rules.json'u okur) bilerek denenmez.
@MainActor
struct URLCommandRunTests {

    @MainActor final class World {
        let store: Store
        let screens: ScreenService
        let router: Router
        init(rules: [Rule] = [], profiles: [Profile]? = nil, windows: [Router.WindowSnapshot] = []) {
            var doc = Document()
            doc.rules = rules
            if let profiles {
                doc.profiles = profiles
                doc.activeProfileID = profiles[0].id
                doc.rules = profiles[0].rules
            }
            store = Store(demo: doc)
            screens = ScreenService(displays: { [RouterHarness.builtin, RouterHarness.monitor] })
            router = Router(store: store, screens: screens, demoWindows: windows)
        }
        func handle(_ s: String) { URLCommands.handle(URL(string: s)!, store: store, router: router) }
    }

    static func window(_ id: CGWindowID, app: String = "Notlar", title: String = "Taslak") -> Router.WindowSnapshot {
        .init(id: id, pid: 1, appName: app, bundleID: "b.\(app)", title: title,
              placement: nil, frame: nil, isMinimized: false)
    }

    @Test func pauseResumeToggle() {
        let w = World()
        #expect(w.store.document.enabled)
        w.handle("deskmap://pause")
        #expect(!w.store.document.enabled)
        w.handle("deskmap://pause")
        #expect(!w.store.document.enabled)
        w.handle("deskmap://resume")
        #expect(w.store.document.enabled)
        w.handle("deskmap://toggle")
        #expect(!w.store.document.enabled)
        w.handle("deskmap://toggle")
        #expect(w.store.document.enabled)
    }

    @Test func unknownCommandReportsAndKeepsState() {
        let w = World()
        w.handle("deskmap://frobnicate")
        #expect(w.store.lastError?.contains("deskmap://frobnicate") == true)
        #expect(w.store.document.enabled && w.store.document.rules.isEmpty)
        // Geçerli ama bozuk parametreli komut da bilinmeyen sayılır.
        let v = World()
        v.handle("deskmap://pin/1/builtin/0")
        #expect(v.store.lastError != nil && v.router.sessionPins.isEmpty)
    }

    @Test func requestClearsPreviousErrorOnlyWhenPresent() {
        let w = World()
        w.store.report("eski hata")
        w.handle("deskmap://pause")
        #expect(w.store.lastError == "eski hata")
        w.handle("deskmap://pause?req=5")
        #expect(w.store.lastError == nil)
        // Hatalı komut req taşısa bile hata yeniden bildirilir.
        w.handle("deskmap://bogus?req=6")
        #expect(w.store.lastError != nil)
    }

    @Test func handleManyRunsInOrder() {
        let w = World()
        URLCommands.handle([URL(string: "deskmap://pause")!, URL(string: "deskmap://resume")!,
                            URL(string: "deskmap://toggle")!], store: w.store, router: w.router)
        #expect(!w.store.document.enabled)
    }

    @Test func profileSwitchAndMissingProfile() {
        let a = Profile(id: "A", name: "Ofis", rules: [])
        let b = Profile(id: "B", name: "Özel Masa", rules: [])
        let w = World(profiles: [a, b])
        w.handle("deskmap://profile/%C3%B6zel%20masa")
        #expect(w.store.document.activeProfileID == "B")
        w.handle("deskmap://profile/Yok")
        #expect(w.store.document.activeProfileID == "B")
        #expect(w.store.lastError?.contains("Yok") == true)
        w.handle("deskmap://profile/ofis")
        #expect(w.store.document.activeProfileID == "A")
    }

    @Test func nextProfileCyclesAndIgnoresSingle() {
        let single = World(profiles: [Profile(id: "A", name: "A", rules: [])])
        single.handle("deskmap://next-profile")
        #expect(single.store.document.activeProfileID == "A")
        let w = World(profiles: [Profile(id: "A", name: "A", rules: []), Profile(id: "B", name: "B", rules: []),
                                 Profile(id: "C", name: "C", rules: [])])
        w.handle("deskmap://next-profile")
        #expect(w.store.document.activeProfileID == "B")
        w.handle("deskmap://next-profile")
        w.handle("deskmap://next-profile")
        #expect(w.store.document.activeProfileID == "A")
    }

    @Test func pinRequiresKnownWindow() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://pin/99/builtin/1")
        #expect(w.router.sessionPins.isEmpty)
        #expect(w.store.lastError?.contains("99") == true)
        w.handle("deskmap://pin/10/builtin/3")
        #expect(w.router.sessionPins[10]?.screen == "builtin")
        #expect(w.router.sessionPins[10]?.desktop == 3)
        #expect(w.router.sessionPins[10]?.layout.isDesktopOnly == false)
    }

    @Test func pinDesktopOnlyUsesAnyFrameLayout() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://pin/10/external/2?layout=desktop-only")
        #expect(w.router.sessionPins[10]?.layout.isDesktopOnly == true)
    }

    @Test func unpinRemovesAndIsIdempotent() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://pin/10/builtin/1")
        #expect(w.router.sessionPins[10] != nil)
        w.handle("deskmap://unpin/10")
        #expect(w.router.sessionPins.isEmpty)
        w.handle("deskmap://unpin/10")
        w.handle("deskmap://unpin/777")
        #expect(w.router.sessionPins.isEmpty)
    }

    @Test func moveUnknownWindowReports() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://move/55/builtin/1")
        #expect(w.store.lastError?.contains("55") == true)
    }

    @Test func pinToNameUnknownWindowReportsBeforeTouchingAppModel() {
        let w = World()
        w.handle("deskmap://pin/55?name=Mail")
        #expect(w.store.lastError?.contains("55") == true)
        #expect(w.router.sessionPins.isEmpty)
    }

    @Test func freeMoveNeedsPin() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://free/10/15")
        #expect(w.router.freeMoves[10] == nil)
        #expect(w.store.lastError?.contains("10") == true)
    }

    @Test func freeMoveGrantAndEnd() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://pin/10/builtin/1")
        let before = Date()
        w.handle("deskmap://free/10/15")
        guard let until = w.router.freeMoves[10] else { Issue.record("no free move"); return }
        #expect(abs(until.timeIntervalSince(before) - 900) < 5)
        w.handle("deskmap://free/10/lock")
        #expect(w.router.freeMoves[10].map(Router.isUntilLock) == true)
        w.handle("deskmap://free-end/10")
        #expect(w.router.freeMoves[10] == nil)
        // Pin hâlâ duruyor.
        #expect(w.router.sessionPins[10] != nil)
    }

    @Test func unpinDropsFreeMove() {
        let w = World(windows: [Self.window(10)])
        w.handle("deskmap://pin/10/builtin/1")
        w.handle("deskmap://free/10/lock")
        w.handle("deskmap://unpin/10")
        #expect(w.router.freeMoves[10] == nil)
    }

    @Test func ruleAddAndRemove() {
        let w = World()
        let json = #"{"id":"R-ç","appName":"Çizim","bundleID":"","tokens":[]}"#
        var c = URLComponents(string: "deskmap://rule-add")!
        c.queryItems = [URLQueryItem(name: "json", value: json)]
        URLCommands.handle(c.url!, store: w.store, router: w.router)
        #expect(w.store.document.rules.map(\.id) == ["R-ç"])
        w.handle("deskmap://rule-remove/yok")
        #expect(w.store.lastError?.contains("yok") == true)
        #expect(w.store.document.rules.count == 1)
        w.handle("deskmap://rule-remove/R-%C3%A7")
        #expect(w.store.document.rules.isEmpty)
    }

    @Test func profileSetCreatesReplacesAndActivates() {
        let w = World(profiles: [Profile(id: "A", name: "Ofis", rules: [])])
        func send(_ json: String, activate: Bool) {
            var c = URLComponents(string: "deskmap://profile-set")!
            c.queryItems = [URLQueryItem(name: "json", value: json),
                            URLQueryItem(name: "activate", value: activate ? "1" : "0")]
            URLCommands.handle(c.url!, store: w.store, router: w.router)
        }
        send(#"{"name":"Yeni Düzen","rules":[]}"#, activate: false)
        #expect(w.store.profiles.map(\.name) == ["Ofis", "Yeni Düzen"])
        #expect(w.store.document.activeProfileID == "A")
        send(#"{"name":"Yeni Düzen","rules":[{"id":"K","appName":"X","bundleID":"","tokens":[]}]}"#, activate: true)
        #expect(w.store.profiles.count == 2)
        #expect(w.store.document.activeProfile?.name == "Yeni Düzen")
        #expect(w.store.document.rules.map(\.id) == ["K"])
    }

    @Test func profileRenameChecksExistenceAndDuplicates() {
        let w = World(profiles: [Profile(id: "A", name: "Ofis", rules: []), Profile(id: "B", name: "Ev", rules: [])])
        w.handle("deskmap://profile-rename/Yok?name=X")
        #expect(w.store.lastError?.contains("Yok") == true)
        w.handle("deskmap://profile-rename/Ofis?name=Ev")
        #expect(w.store.lastError?.contains("Ev") == true)
        #expect(w.store.profiles.map(\.name) == ["Ofis", "Ev"])
        w.handle("deskmap://profile-rename/ofis?name=%C4%B0%C5%9F%20Yeri")
        #expect(w.store.profiles.map(\.name) == ["İş Yeri", "Ev"])
    }

    @Test func profileExportWritesFileToTempDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-urltest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let w = World(profiles: [Profile(id: "A", name: "Ofis", rules: []), Profile(id: "B", name: "Ev", rules: [])])
        let activePath = dir.appendingPathComponent("aktif.json").path
        let namedPath = dir.appendingPathComponent("ev.json").path
        var c = URLComponents(string: "deskmap://profile-export")!
        c.queryItems = [URLQueryItem(name: "path", value: activePath)]
        URLCommands.handle(c.url!, store: w.store, router: w.router)
        c.queryItems = [URLQueryItem(name: "path", value: namedPath), URLQueryItem(name: "name", value: "EV")]
        URLCommands.handle(c.url!, store: w.store, router: w.router)
        let active = try String(contentsOfFile: activePath, encoding: .utf8)
        let named = try String(contentsOfFile: namedPath, encoding: .utf8)
        #expect(active.contains("Ofis") && !active.contains("\"Ev\""))
        #expect(named.contains("Ev"))
        #expect(w.store.lastError == nil)
    }

    @Test func profileExportMissingProfileAndBadPathReport() {
        let w = World(profiles: [Profile(id: "A", name: "Ofis", rules: [])])
        w.handle("deskmap://profile-export?path=/tmp/deskmap-never-written.json&name=Yok")
        #expect(w.store.lastError?.contains("Yok") == true)
        #expect(!FileManager.default.fileExists(atPath: "/tmp/deskmap-never-written.json"))
        let w2 = World(profiles: [Profile(id: "A", name: "Ofis", rules: [])])
        w2.handle("deskmap://profile-export?path=/nonexistent-deskmap-dir-xyz/a.json")
        #expect(w2.store.lastError != nil)
    }

    @Test func copyLayoutCommandResults() {
        var half = WindowLayout.full
        half.w = 0.5
        var shared = V6.rule("Mail", docked: Destination(screen: "builtin", desktop: 1, layout: .full),
                             undocked: Destination(screen: "builtin", desktop: 1, layout: half))
        shared.id = "same"
        var apart = V6.rule("Web", docked: V6.b(1), undocked: V6.b(2))
        apart.id = "apart"
        var single = V6.rule("Not", docked: V6.b(1))
        single.id = "single"
        let w = World(rules: [shared, apart, single])
        w.handle("deskmap://rule-copy-layout/ghost?from=docked")
        #expect(w.store.lastError?.contains("ghost") == true)
        w.handle("deskmap://rule-copy-layout/apart?from=docked")
        #expect(w.store.lastError?.contains("apart") == true)
        w.handle("deskmap://rule-copy-layout/single?from=docked")
        #expect(w.store.lastError?.contains("single") == true)
        w.store.clearError()
        w.handle("deskmap://rule-copy-layout/same?from=docked")
        #expect(w.store.lastError == nil)
        #expect(w.store.rule("same")?.undocked?.layout.w == 1)
        // İkinci kopya: düzenler artık aynı, hata yok.
        w.handle("deskmap://rule-copy-layout/same?from=docked")
        #expect(w.store.lastError == nil)
    }

    @Test func statusCommandWritesStatusWithRequest() throws {
        let w = World(windows: [Self.window(10)])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-urltest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let status = StatusFile(url: url, store: w.store, router: w.router, screens: w.screens)
        URLCommands.handle(URL(string: "deskmap://status?req=abc")!, store: w.store, router: w.router, status: status)
        var data = try Data(contentsOf: url)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["request"] as? String == "abc")
        // Bilinmeyen komut da isteği yanıtlar (araç beklemesin).
        URLCommands.handle(URL(string: "deskmap://bogus?req=def")!, store: w.store, router: w.router, status: status)
        data = try Data(contentsOf: url)
        json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["request"] as? String == "def")
        #expect((json["lastError"] as? String)?.contains("bogus") == true)
        // req yoksa alan hiç yazılmaz.
        URLCommands.handle(URL(string: "deskmap://status")!, store: w.store, router: w.router, status: status)
        json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["request"] == nil)
    }
}
