import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// "Bu pencereyi pinle" için kararlı kimlik: oynak başlık parçaları atılır.
struct WindowIdentityTests {

    private func parts(_ app: String, _ bundle: String, _ title: String) -> [String] {
        WindowIdentity.candidates(appName: app, bundleID: bundle, title: title)
    }

    private func snap(_ id: CGWindowID, _ app: String, _ bundle: String, _ title: String)
        -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app, bundleID: bundle, title: title,
                              placement: nil, frame: nil, isMinimized: false)
    }

    private let preview = "com.apple.Preview"

    // MARK: Preview

    @Test func previewDropsPageNumbers() {
        #expect(parts("Preview", preview, "teori.pdf – Page 2 of 6") == ["teori.pdf"])
        #expect(parts("Preview", preview, "ek-03-konu-anlatimi.report.pdf – Page 13 of 61")
                == ["ek-03-konu-anlatimi.report.pdf"])
    }

    @Test func previewEditedAndMultiDocument() {
        #expect(parts("Preview", preview, "main.pdf — Edited") == ["main.pdf"])
        #expect(parts("Preview", preview, "main.pdf (Edited)") == ["main.pdf"])
        #expect(parts("Preview", preview, "2 documents, 2 total pages").isEmpty)
    }

    @Test func pageChangeKeepsTheSameRuleMatching() {
        let first = WindowIdentity.resolve(appName: "Preview", bundleID: preview,
                                           title: "teori.pdf – Page 2 of 6", others: [])
        guard case .rule(let tokens) = first else { Issue.record("kural bekleniyordu"); return }
        let rule = Rule(appName: "Preview", bundleID: preview, tokens: tokens)
        #expect(rule.matches(bundleID: preview, appName: "Preview", title: "teori.pdf – Page 6 of 6"))
        #expect(rule.matches(bundleID: preview, appName: "Preview", title: "teori.pdf — Edited"))
        #expect(!rule.matches(bundleID: preview, appName: "Preview", title: "baska.pdf – Page 1 of 2"))
    }

    // MARK: Editörler

    @Test func codeKeepsWorkspaceNotFile() {
        let code = "com.microsoft.VSCode"
        #expect(parts("Code", code, "09_main_results.ipynb — Orion-Makale")
                == ["Orion-Makale", "09_main_results.ipynb"])
        #expect(parts("Code", code, "● PANO.md — Lumen-Makale")
                == ["Lumen-Makale", "PANO.md"])
        #expect(parts("Code", code, "PANO.md — Lumen-Makale — Visual Studio Code")
                == ["Lumen-Makale", "PANO.md"])
        #expect(WindowIdentity.resolve(appName: "Code", bundleID: code,
                                       title: "● PANO.md — Lumen-Makale", others: [])
                == .rule(["Lumen-Makale"]))
    }

    @Test func narrowsWithNextSegmentWhenAmbiguous() {
        let code = "com.microsoft.VSCode"
        let other = snap(2, "Code", code, "b.md — Orion")
        #expect(WindowIdentity.resolve(appName: "Code", bundleID: code,
                                       title: "a.md — Orion", others: [other])
                == .rule(["Orion", "a.md"]))
        // Aynı başlıklı ikinci pencere: kural ayıramaz.
        let twin = snap(3, "Code", code, "a.md — Orion")
        #expect(WindowIdentity.resolve(appName: "Code", bundleID: code,
                                       title: "a.md — Orion", others: [twin]) == .none)
    }

    // MARK: Tarayıcılar

    @Test func safariUsesTabGroupName() {
        let safari = "com.apple.Safari"
        #expect(parts("Safari", safari, "Asıl — Google").first == "Asıl")
        #expect(parts("Safari", safari, "Research — menu bar apps - Google'da Ara").first
                == "Research")
        #expect(WindowIdentity.resolve(appName: "Safari", bundleID: safari,
                                       title: "Asıl — Google", others: []) == .rule(["Asıl"]))
    }

    @Test func chromeKeepsPageTitleWithoutBrowserName() {
        #expect(parts("Google Chrome", "com.google.Chrome", "(3) Gelen Kutusu - Google Chrome")
                == ["Gelen Kutusu"])
    }

    // MARK: Finder, Office, Outlook, Teams, Terminal

    @Test func finderAndExcelUseTheName() {
        #expect(parts("Finder", "com.apple.finder", "Nova-Paper-conf2027")
                == ["Nova-Paper-conf2027"])
        let excel = "com.microsoft.Excel"
        #expect(parts("Microsoft Excel", excel, "Orion-Project-Timeline")
                == ["Orion-Project-Timeline"])
        // Uzantı görünse de görünmese de aynı anahtar.
        #expect(parts("Microsoft Excel", excel, "Orion-Project-Timeline.xlsx — Saved")
                == ["Orion-Project-Timeline"])
    }

    @Test func outlookKeepsAccountNotFolder() {
        let account = "jane.doe@example.com"
        #expect(parts("Microsoft Outlook", "com.microsoft.Outlook", "Inbox • \(account)") == [account])
        #expect(parts("Microsoft Outlook", "com.microsoft.Outlook", "Inbox (12) • \(account)") == [account])
    }

    @Test func teamsHasNoStableKeyAndFallsBackToSession() {
        let title = "Chat | Doe, Jane (You) | Microsoft Teams"
        #expect(parts("Microsoft Teams", "com.microsoft.teams2", title).isEmpty)
        #expect(WindowIdentity.resolve(appName: "Microsoft Teams", bundleID: "com.microsoft.teams2",
                                       title: title, others: []) == .none)
    }

    @Test func terminalKeepsHostWithoutDirectory() {
        let title = "jane — jane@build-server:~ — ssh"
        #expect(parts("Terminal", "com.apple.Terminal", title).first == "jane@build-server")
        #expect(parts("Terminal", "com.apple.Terminal",
                      "jane — jane@build-server:~/proj — ssh — 120×40").first
                == "jane@build-server")
        // Dizin değişse de kural aynı pencereye uyar.
        let rule = Rule(appName: "Terminal", bundleID: "com.apple.Terminal",
                        tokens: ["jane@build-server"])
        #expect(rule.matches(bundleID: "com.apple.Terminal", appName: "Terminal",
                             title: "jane — jane@build-server:~/proj — ssh"))
    }

    // MARK: Yedekler

    @Test func emptyAndGenericTitlesFallBackToSession() {
        #expect(WindowIdentity.resolve(appName: "Notes", bundleID: "com.apple.Notes",
                                       title: "", others: []) == .none)
        #expect(parts("Safari", "com.apple.Safari", "New Tab").isEmpty)
        #expect(parts("Preview", preview, "Untitled").isEmpty)
    }

    @Test func countsAndMarkersAreStripped() {
        #expect(parts("Slack", "com.tinyspeck.slackmacgap", "(3) Genel") == ["Genel"])
        #expect(parts("Notes", "com.apple.Notes", "Liste*") == ["Liste"])
    }

    // MARK: Regresyon

    @Test func terminalNeverNarrowsWithVolatileSegments() {
        let other = snap(2, "Terminal", "com.apple.Terminal", "jane — -zsh — 80×24")
        let r = WindowIdentity.resolve(appName: "Terminal", bundleID: "com.apple.Terminal",
                                       title: "jane — ✳ Claude Code — 120×40", others: [other])
        #expect(r == .none)
    }

    @Test func safariNeverAddsPageToGroupKey() {
        let other = snap(2, "Safari", "com.apple.Safari", "Asıl — Yahoo")
        let r = WindowIdentity.resolve(appName: "Safari", bundleID: "com.apple.Safari",
                                       title: "Asıl — Google", others: [other])
        #expect(r == .none)
    }

    @Test func shortTokensFallBackToSession() {
        let r = WindowIdentity.resolve(appName: "Safari", bundleID: "com.apple.Safari",
                                       title: "AI — Sayfa", others: [])
        #expect(r == .none)
    }

    @Test func sameKeyIgnoresTokenOrder() {
        let a = Rule(appName: "Code", bundleID: "x", tokens: ["a.md", "Orion"])
        let b = Rule(appName: "Code", bundleID: "x", tokens: ["orion", "A.md"])
        #expect(a.sameKey(as: b))
    }

    // MARK: Üç katman: belge yolu, başlık geçmişi, sezgi

    private func doc(_ id: CGWindowID, _ app: String, _ bundle: String, _ title: String,
                     document: String? = nil, tabGroup: String? = nil) -> Router.WindowSnapshot {
        var window = snap(id, app, bundle, title)
        window.document = document
        window.tabGroup = tabGroup
        return window
    }

    @Test func documentPathSeparatesSameNamedFiles() {
        let a = doc(1, "Preview", preview, "main.pdf – Page 1 of 3", document: "/a/main.pdf")
        let b = doc(2, "Preview", preview, "main.pdf – Page 2 of 9", document: "/b/main.pdf")
        // Belge güveni öğrenilmeden yol kullanılmaz.
        #expect(WindowIdentity.resolve(a, others: [b]) == .none)
        var history = WindowIdentity.Observations()
        history.observe([a, b])
        let paged = doc(1, "Preview", preview, "main.pdf – Page 2 of 3", document: "/a/main.pdf")
        history.observe([paged, b])
        #expect(history.stableDocumentApps == [preview])
        let r = WindowIdentity.resolve(a, others: [b], history: history)
        #expect(r == .path("/a/main.pdf"))
        // Uygulama öğrenildi: aynı uygulamanın öbür penceresi de yol alır.
        #expect(WindowIdentity.resolve(b, others: [a], history: history) == .path("/b/main.pdf"))
        let rule = r.rule(appName: "Preview", bundleID: preview)!
        #expect(rule.matches(a))
        #expect(!rule.matches(b))
        #expect(!rule.isAppWide)
        #expect(rule.title == "main.pdf")
    }

    @Test func sameDocumentInTwoWindowsFallsBackToTitle() {
        let a = doc(1, "Preview", preview, "main.pdf – Page 1 of 3", document: "/a/main.pdf")
        let b = doc(2, "Preview", preview, "main.pdf – Page 2 of 3", document: "/a/main.pdf")
        let history = WindowIdentity.Observations(stableDocumentApps: [preview])
        #expect(WindowIdentity.resolve(a, others: [b], history: history) == .none)
    }

    @Test func changingDocumentIsNotTrusted() {
        let code = "com.microsoft.VSCode"
        var history = WindowIdentity.Observations(stableDocumentApps: [code])
        let first = doc(1, "Code", code, "a.md — Proj", document: "/p/a.md")
        history.observe([first])
        #expect(WindowIdentity.resolve(first, others: [], history: history) == .path("/p/a.md"))
        let second = doc(1, "Code", code, "b.md — Proj", document: "/p/b.md")
        history.observe([second])
        #expect(WindowIdentity.resolve(second, others: [], history: history) == .rule(["Proj"]))
        // Aynı uygulamanın yeni penceresi de belgeyle anahtarlanmaz.
        let fresh = doc(5, "Code", code, "c.md — Other", document: "/o/c.md")
        #expect(WindowIdentity.resolve(fresh, others: [], history: history) == .rule(["Other"]))
        #expect(history.volatileDocumentApps == [code])
    }

    @Test func stableSegmentWinsAfterTitleChanges() {
        let terminal = "com.apple.Terminal"
        var history = WindowIdentity.Observations()
        history.observe([snap(1, "Terminal", terminal, "jane — jane@devbox:~ — ssh — 80×24")])
        history.observe([snap(1, "Terminal", terminal, "jane — jane@devbox:~/x — vim — 80×24")])
        let now = snap(1, "Terminal", terminal, "jane — jane@devbox:~/x — vim — 80×24")
        #expect(history.stableSegments(of: now) == ["jane@devbox", "jane"])
        #expect(WindowIdentity.resolve(now, others: [], history: history) == .rule(["jane@devbox"]))
    }

    @Test func everySegmentChangedMeansNoKey() {
        let chrome = "com.google.Chrome"
        var history = WindowIdentity.Observations()
        history.observe([snap(1, "Google Chrome", chrome, "Gelen Kutusu - Google Chrome")])
        let now = snap(1, "Google Chrome", chrome, "Haberler - Google Chrome")
        history.observe([now])
        #expect(history.stableSegments(of: now) == [])
        #expect(WindowIdentity.resolve(now, others: [], history: history) == .none)
        // Pencere kapanınca geçmişi unutulur.
        history.observe([])
        #expect(history.entries.isEmpty)
    }

    @Test func safariTabGroupFromToolbar() {
        let safari = "com.apple.Safari"
        let grouped = doc(1, "Safari", safari, "Research — Bir sayfa", tabGroup: "Research")
        #expect(WindowIdentity.resolve(grouped, others: []) == .rule(["Research"]))
        // Grupsuz pencere: başlığı " — " içerse de ad anahtarı yok.
        let loose = doc(2, "Safari", safari, "Asıl — Google", tabGroup: "")
        #expect(WindowIdentity.resolve(loose, others: []) == .none)
        #expect(AX.tabGroupName(identifier: "TabGroupPickerButton?TabGroup=Research") == "Research")
        #expect(AX.tabGroupName(identifier: "TabGroupPickerButton") == "")
        #expect(AX.tabGroupName(identifier: "BackButton") == nil)
        // Grupsuz pencerede seçici hiç yok: araç çubuğu okunduysa "" (başlık sezgisi yok).
        #expect(AX.tabGroup(toolbars: [["BackButton", nil]]) == "")
        #expect(AX.tabGroup(toolbars: [["BackButton", "TabGroupPickerButton?TabGroup=Research"]]) == "Research")
        #expect(AX.tabGroup(toolbars: []) == nil)
        let bare = doc(3, "Safari", safari, "DMDelta Page", tabGroup: AX.tabGroup(toolbars: [["BackButton"]]))
        #expect(WindowIdentity.resolve(bare, others: []) == .none)
    }

    @Test func documentPathParsing() {
        #expect(AX.documentPath("file:///Users/x/My%20Docs/main.pdf") == "/Users/x/My Docs/main.pdf")
        #expect(AX.documentPath("https://example.com/a.pdf") == nil)
        #expect(AX.documentPath("") == nil)
    }

    @Test func pathRuleCodableAndSpecificity() throws {
        let rule = Rule(appName: "Preview", bundleID: preview, tokens: [], path: "/a/main.pdf",
                        docked: Destination(screen: "builtin"))
        let back = try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(rule))
        #expect(back == rule && back.path == "/a/main.pdf")
        // Eski kayıt: path yok.
        let old = try JSONDecoder().decode(Rule.self, from: Data(#"{"appName":"Preview","tokens":[]}"#.utf8))
        #expect(old.path == nil && old.isAppWide)
        let titled = Rule(appName: "Preview", bundleID: preview, tokens: ["main.pdf", "x"])
        #expect([titled, rule].bySpecificity.first?.path == "/a/main.pdf")
        #expect(!rule.sameKey(as: Rule(appName: "Preview", bundleID: preview, tokens: [])))
    }
}
