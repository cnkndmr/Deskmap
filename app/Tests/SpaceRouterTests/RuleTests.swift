import Foundation
import Testing
@testable import SpaceRouter

/// `Rule` eşleştirme, sıralama, başlık parçalama ve anahtar karşılaştırması.
struct RuleTests {

    private let code = Rule(appName: "Code", bundleID: "com.microsoft.VSCode", tokens: ["Atlas"])

    @Test func bundleIDTakesPrecedenceOverAppName() {
        // Paket kimliği doluysa yalnızca o karşılaştırılır; ad farklı olabilir.
        #expect(code.matches(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code",
                             title: "Store.swift — Atlas"))
        #expect(!code.matches(bundleID: "com.apple.Safari", appName: "Code",
                              title: "Atlas"))
    }

    @Test func appNameFallbackIsCaseInsensitive() {
        let rule = Rule(appName: "Safari", bundleID: "", tokens: [])
        #expect(rule.matches(bundleID: "com.apple.Safari", appName: "safari", title: ""))
        #expect(rule.matches(bundleID: "", appName: "SAFARI", title: "x"))
        #expect(!rule.matches(bundleID: "", appName: "Safari Technology Preview", title: ""))
    }

    @Test func allTokensRequiredCaseInsensitive() {
        let rule = Rule(appName: "Code", bundleID: "com.microsoft.VSCode",
                        tokens: ["atlas", "Store"])
        #expect(rule.matches(bundleID: rule.bundleID, appName: "Code",
                             title: "STORE.swift — Atlas"))
        #expect(!rule.matches(bundleID: rule.bundleID, appName: "Code",
                              title: "Router.swift — Atlas"))
    }

    @Test func appWideRuleIgnoresTitle() {
        let rule = Rule(appName: "Music", bundleID: "com.apple.Music", tokens: [])
        #expect(rule.isAppWide)
        #expect(rule.title == "tüm pencereler")
        #expect(rule.matches(bundleID: "com.apple.Music", appName: "Music", title: ""))
        #expect(rule.matches(bundleID: "com.apple.Music", appName: "Music", title: "Anything"))
    }

    @Test func bySpecificityOrdersByTokenCountAndKeepsOrderForTies() {
        let a = Rule(id: "a", appName: "X", bundleID: "x", tokens: [])
        let b = Rule(id: "b", appName: "X", bundleID: "x", tokens: ["1", "2"])
        let c = Rule(id: "c", appName: "X", bundleID: "x", tokens: ["1"])
        let d = Rule(id: "d", appName: "X", bundleID: "x", tokens: ["3"])
        #expect([a, c, b, d].bySpecificity.map(\.id) == ["b", "c", "d", "a"])
    }

    @Test func splitOnAllSeparators() {
        let title = "Alpha — Beta – Gamma - Delta | Epsilon · Zeta • Eta : Theta"
        #expect(Rule.split(title: title)
                == ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta"])
    }

    @Test func splitStripsLeadingBullets() {
        // Kaydedilmemiş belge işareti (● / • / *) parçanın başından düşer.
        #expect(Rule.split(title: "● Store.swift — Atlas") == ["Store.swift", "Atlas"])
        #expect(Rule.split(title: "* draft | Notes") == ["draft", "Notes"])
    }

    @Test func splitKeepsHyphenatedWordsAndColonsWithoutSpaces() {
        #expect(Rule.split(title: "well-known - thing") == ["well-known", "thing"])
        #expect(Rule.split(title: "Re: hello") == ["Re: hello"])
        #expect(Rule.split(title: "Plain title") == ["Plain title"])
    }

    @Test func splitEmptyTitle() {
        #expect(Rule.split(title: "") == [])
        #expect(Rule.split(title: " — ") == [" — "])
    }

    @Test func sameKeyComparesIdentityAndTokens() {
        let base = Rule(appName: "Code", bundleID: "com.microsoft.VSCode", tokens: ["Atlas"])
        #expect(base.sameKey(as: Rule(appName: "Other", bundleID: "com.microsoft.VSCode",
                                      tokens: ["atlas"])))
        #expect(!base.sameKey(as: Rule(appName: "Code", bundleID: "com.microsoft.VSCode",
                                       tokens: ["Atlas", "Store"])))
        #expect(!base.sameKey(as: Rule(appName: "Code", bundleID: "com.other", tokens: ["Atlas"])))
        // Paket kimliği yoksa uygulama adı (küçük harfle) anahtardır.
        let named = Rule(appName: "Safari", bundleID: "", tokens: [])
        #expect(named.sameKey(as: Rule(appName: "SAFARI", bundleID: "", tokens: [])))
        #expect(!named.sameKey(as: Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: [])))
    }

    @Test func modeSubscriptReadsAndWritesIndependently() {
        var rule = Rule(appName: "X", bundleID: "x", tokens: [],
                        docked: Destination(screen: "external", desktop: 2))
        #expect(rule[.docked]?.screen == "external")
        #expect(rule[.undocked] == nil)
        rule[.undocked] = Destination(screen: "builtin", desktop: 3)
        rule[.docked] = nil
        #expect(rule.docked == nil)
        #expect(rule.undocked?.desktop == 3)
    }
}
