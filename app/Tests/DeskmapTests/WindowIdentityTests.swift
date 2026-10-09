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
        #expect(parts("Code", code, "09_main_results.ipynb — Orion")
                == ["Orion", "09_main_results.ipynb"])
        #expect(parts("Code", code, "● PANO.md — Plover-Paper")
                == ["Plover-Paper", "PANO.md"])
        #expect(parts("Code", code, "PANO.md — Plover-Paper — Visual Studio Code")
                == ["Plover-Paper", "PANO.md"])
        #expect(WindowIdentity.resolve(appName: "Code", bundleID: code,
                                       title: "● PANO.md — Plover-Paper", others: [])
                == .rule(["Plover-Paper"]))
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
                                       title: "a.md — Orion", others: [twin]) == .session)
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
        #expect(parts("Finder", "com.apple.finder", "Nova-IEEE-Paper-expo")
                == ["Nova-IEEE-Paper-expo"])
        let excel = "com.microsoft.Excel"
        #expect(parts("Microsoft Excel", excel, "Orion")
                == ["Orion"])
        // Uzantı görünse de görünmese de aynı anahtar.
        #expect(parts("Microsoft Excel", excel, "Orion.xlsx — Saved")
                == ["Orion"])
    }

    @Test func outlookKeepsAccountNotFolder() {
        let account = "user@example.com"
        #expect(parts("Microsoft Outlook", "com.microsoft.Outlook", "Inbox • \(account)") == [account])
        #expect(parts("Microsoft Outlook", "com.microsoft.Outlook", "Inbox (12) • \(account)") == [account])
    }

    @Test func teamsHasNoStableKeyAndFallsBackToSession() {
        let title = "Chat | Example User (You) | Microsoft Teams"
        #expect(parts("Microsoft Teams", "com.microsoft.teams2", title).isEmpty)
        #expect(WindowIdentity.resolve(appName: "Microsoft Teams", bundleID: "com.microsoft.teams2",
                                       title: title, others: []) == .session)
    }

    @Test func terminalKeepsHostWithoutDirectory() {
        let title = "user — user@host:~ — ssh"
        #expect(parts("Terminal", "com.apple.Terminal", title).first == "user@host")
        #expect(parts("Terminal", "com.apple.Terminal",
                      "user — user@host:~/proj — ssh — 120×40").first
                == "user@host")
        // Dizin değişse de kural aynı pencereye uyar.
        let rule = Rule(appName: "Terminal", bundleID: "com.apple.Terminal",
                        tokens: ["user@host"])
        #expect(rule.matches(bundleID: "com.apple.Terminal", appName: "Terminal",
                             title: "user — user@host:~/proj — ssh"))
    }

    // MARK: Yedekler

    @Test func emptyAndGenericTitlesFallBackToSession() {
        #expect(WindowIdentity.resolve(appName: "Notes", bundleID: "com.apple.Notes",
                                       title: "", others: []) == .session)
        #expect(parts("Safari", "com.apple.Safari", "New Tab").isEmpty)
        #expect(parts("Preview", preview, "Untitled").isEmpty)
    }

    @Test func countsAndMarkersAreStripped() {
        #expect(parts("Slack", "com.tinyspeck.slackmacgap", "(3) Genel") == ["Genel"])
        #expect(parts("Notes", "com.apple.Notes", "Liste*") == ["Liste"])
    }

    // MARK: Regresyon

    @Test func terminalNeverNarrowsWithVolatileSegments() {
        let other = snap(2, "Terminal", "com.apple.Terminal", "user — -zsh — 80×24")
        let r = WindowIdentity.resolve(appName: "Terminal", bundleID: "com.apple.Terminal",
                                       title: "user — ✳ Claude Code — 120×40", others: [other])
        #expect(r == .session)
    }

    @Test func safariNeverAddsPageToGroupKey() {
        let other = snap(2, "Safari", "com.apple.Safari", "Asıl — Yahoo")
        let r = WindowIdentity.resolve(appName: "Safari", bundleID: "com.apple.Safari",
                                       title: "Asıl — Google", others: [other])
        #expect(r == .session)
    }

    @Test func shortTokensFallBackToSession() {
        let r = WindowIdentity.resolve(appName: "Safari", bundleID: "com.apple.Safari",
                                       title: "AI — Sayfa", others: [])
        #expect(r == .session)
    }

    @Test func sameKeyIgnoresTokenOrder() {
        let a = Rule(appName: "Code", bundleID: "x", tokens: ["a.md", "Orion"])
        let b = Rule(appName: "Code", bundleID: "x", tokens: ["orion", "A.md"])
        #expect(a.sameKey(as: b))
    }
}
