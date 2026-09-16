import Foundation
import Testing
@testable import Deskmap

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

    // MARK: Büyük/küçük harf semantiği (lowercased(); değişmesin)

    @Test func turkishDottedAndDotlessIFollowUnicodeLowercasing() {
        func match(_ token: String, in title: String) -> Bool {
            Rule(appName: "X", bundleID: "x", tokens: [token])
                .matches(bundleID: "x", appName: "X", title: title)
        }
        // "İ".lowercased() = "i" + U+0307 (birleşen nokta); "i" ile aynı değil.
        #expect("İ".lowercased().unicodeScalars.map(\.value) == [0x69, 0x307])
        #expect(!match("istanbul", in: "İstanbul"))
        #expect(match("İstanbul", in: "İSTANBUL"))
        #expect(match("İstanbul", in: "İstanbul"))
        // ASCII "I" → "i"; noktasız "ı" olduğu gibi kalır.
        #expect(match("istanbul", in: "ISTANBUL"))
        #expect(!match("İstanbul", in: "ISTANBUL"))
        #expect(match("i", in: "I"))
        #expect(!match("ı", in: "I"))
        #expect(!match("I", in: "ı"))
        #expect(!match("İ", in: "i"))
        #expect(!match("ığdır", in: "Iğdır"))
        // "IĞDIR".lowercased() = "iğdir": noktasız ı ile eşleşmez.
        #expect(!match("ığdır", in: "IĞDIR"))
    }

    @Test func caseFoldingPairsAreNotMatchedLikeCaseInsensitiveSearch() {
        // `.caseInsensitive` arama tam katlama yapar (ß ≈ SS, ﬁ ≈ fi);
        // küçültme semantiği bunları eşlemez, karar böyle kalmalı.
        let rule = Rule(appName: "X", bundleID: "x", tokens: ["straße"])
        #expect(!rule.matches(bundleID: "x", appName: "X", title: "STRASSE"))
        #expect(rule.matches(bundleID: "x", appName: "X", title: "STRAßE"))
        let ligature = Rule(appName: "X", bundleID: "x", tokens: ["file"])
        #expect(!ligature.matches(bundleID: "x", appName: "X", title: "ﬁle"))
        // Farklı normalleştirme biçimleri yine eşit (Swift String karşılaştırması).
        let accent = Rule(appName: "X", bundleID: "x", tokens: ["CAFE\u{0301}"])
        #expect(accent.matches(bundleID: "x", appName: "X", title: "café"))
    }

    @Test func mutatedTokensMatchWithNewValues() {
        var rule = Rule(appName: "Code", bundleID: "x", tokens: ["Atlas"])
        #expect(rule.matches(bundleID: "x", appName: "Code", title: "atlas"))
        rule.tokens = ["ROUTER"]
        #expect(!rule.matches(bundleID: "x", appName: "Code", title: "atlas"))
        #expect(rule.matches(bundleID: "x", appName: "Code", title: "Router.swift"))
        rule.tokens = []
        #expect(rule.matches(bundleID: "x", appName: "Code", title: "anything"))
        rule.tokens.append("Store")
        #expect(rule.matches(bundleID: "x", appName: "Code", title: "STORE.swift"))
        #expect(!rule.matches(bundleID: "x", appName: "Code", title: "Router.swift"))
    }

    @Test func decodedRulesMatchCaseInsensitively() throws {
        // Çözümleme yolunda da (v2 ve v1) küçük harf kopyası kurulur.
        let v2 = try JSONDecoder().decode(Rule.self, from: Data("""
            {"appName":"Code","bundleID":"x","tokens":["Atlas","Store"]}
            """.utf8))
        #expect(v2.matches(bundleID: "x", appName: "Code", title: "STORE — atlas"))
        #expect(!v2.matches(bundleID: "x", appName: "Code", title: "atlas"))
        let v1 = try JSONDecoder().decode(Rule.self, from: Data("""
            {"app":"Code","match":{"type":"contains","value":"Atlas"}}
            """.utf8))
        #expect(v1.tokens == ["Atlas"])
        #expect(v1.matches(bundleID: "", appName: "code", title: "atlas"))
    }

    @Test func lazyTitleOverloadOnlyLowercasesWhenNeeded() {
        // Çağrılar `#expect` dışında: makro argümanları önceden değerlendirir,
        // bu da `@autoclosure` tembelliğini bozar.
        var calls = 0
        func lowered(_ title: String) -> String { calls += 1; return title.lowercased() }
        let appWide = Rule(appName: "X", bundleID: "x", tokens: [])
        let appWideMatched = appWide.matches(bundleID: "x", appName: "X", loweredTitle: lowered("T"))
        let otherApp = Rule(appName: "Y", bundleID: "y", tokens: ["t"])
        let otherMatched = otherApp.matches(bundleID: "x", appName: "X", loweredTitle: lowered("T"))
        #expect(appWideMatched && !otherMatched)
        #expect(calls == 0)
        let titled = Rule(appName: "X", bundleID: "x", tokens: ["t"])
        let titledMatched = titled.matches(bundleID: "x", appName: "X", loweredTitle: lowered("T"))
        #expect(titledMatched)
        #expect(calls == 1)
    }

    @Test func splitIsStableAcrossConcurrentCalls() {
        // Ayraç deseni paylaşılan bir sabit; eşzamanlı çağrılar aynı sonucu verir.
        let title = "● Alpha — Beta | Gamma : Delta"
        let expected = ["Alpha", "Beta", "Gamma", "Delta"]
        let lock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            if Rule.split(title: title) != expected {
                lock.lock(); mismatches += 1; lock.unlock()
            }
        }
        #expect(mismatches == 0)
    }

    @Test func appWideRuleIgnoresTitle() {
        let rule = Rule(appName: "Music", bundleID: "com.apple.Music", tokens: [])
        #expect(rule.isAppWide)
        #expect(rule.title == "all windows")
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
