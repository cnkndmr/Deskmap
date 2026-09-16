import Foundation
import Testing
@testable import Deskmap

/// Var olan bir pinin başlık parçalarını değiştirme: `Document.setTokens`
/// (anahtar çakışması denetimi) ve `TokenPicker` saf yardımcıları.
struct TokenEditingTests {

    private let external = Destination(screen: "external", desktop: 2, layout: .leftHalf)

    private func rule(_ id: String, tokens: [String]) -> Rule {
        Rule(id: id, appName: "Code", bundleID: "com.microsoft.VSCode", tokens: tokens,
             docked: external, undocked: Destination(screen: "builtin"))
    }

    // MARK: Document

    @Test func setTokensKeepsIdentityAndDestinations() {
        var doc = Document()
        doc.rules = [rule("a", tokens: ["Atlas"])]
        let changed = doc.setTokens(["Comet_notes", "notebooks"], for: "a")
        #expect(changed)
        #expect(doc.rules[0].id == "a")
        #expect(doc.rules[0].tokens == ["Comet_notes", "notebooks"])
        #expect(doc.rules[0].docked == external)
        #expect(doc.rules[0].undocked?.screen == "builtin")
    }

    @Test func setTokensRefusesKeyCollisionWithAnotherRule() {
        var doc = Document()
        doc.rules = [rule("a", tokens: ["Atlas"]), rule("b", tokens: ["Comet_notes"])]
        // Büyük/küçük harf farkı çakışmayı gizlemez.
        #expect(doc.conflictingRule(ifTokens: ["comet"], for: "a")?.id == "b")
        let changed = doc.setTokens(["comet"], for: "a")
        #expect(!changed)
        #expect(doc.rules[0].tokens == ["Atlas"])
        // Kuralın kendi parçaları çakışma sayılmaz; uygulama geneline geçiş serbest.
        #expect(doc.conflictingRule(ifTokens: ["atlas"], for: "a") == nil)
        let widened = doc.setTokens([], for: "a")
        #expect(widened)
        #expect(doc.rules[0].isAppWide)
        // Artık boş parçalı kural var; "b" de boşa geçemez.
        #expect(doc.conflictingRule(ifTokens: [], for: "b")?.id == "a")
    }

    @Test func setTokensIgnoresUnknownRule() {
        var doc = Document()
        doc.rules = [rule("a", tokens: ["Atlas"])]
        let changed = doc.setTokens(["X"], for: "yok")
        #expect(!changed)
        #expect(doc.conflictingRule(ifTokens: ["Atlas"], for: "yok") == nil)
        #expect(doc.rules[0].tokens == ["Atlas"])
    }

    @Test func differentAppNeverConflicts() {
        var doc = Document()
        doc.rules = [
            rule("a", tokens: ["Atlas"]),
            Rule(id: "s", appName: "Safari", bundleID: "com.apple.Safari", tokens: ["Atlas"]),
        ]
        #expect(doc.conflictingRule(ifTokens: ["Atlas"], for: "s") == nil)
    }

    // MARK: TokenPicker

    @Test func tokensFollowSegmentOrderAndAppWideWins() {
        let segments = ["Store.swift", "Atlas", "Code"]
        #expect(TokenPicker.tokens(segments: segments, chosen: [2, 0], appWide: false)
                == ["Store.swift", "Code"])
        #expect(TokenPicker.tokens(segments: segments, chosen: [1], appWide: true) == [])
        // Başlık değişip bölüm sayısı azalınca eski dizinler sessizce düşer.
        #expect(TokenPicker.tokens(segments: ["Tek"], chosen: [0, 4], appWide: false) == ["Tek"])
    }

    @Test func preselectionMatchesTokensCaseInsensitively() {
        let segments = ["Store.swift", "atlas", "Code"]
        #expect(TokenPicker.preselection(segments: segments, tokens: ["Atlas", "Code"]) == [1, 2])
        #expect(TokenPicker.preselection(segments: segments, tokens: ["Comet_notes"]).isEmpty)
        #expect(TokenPicker.preselection(segments: [], tokens: ["Atlas"]).isEmpty)
        #expect(TokenPicker.preselection(segments: segments, tokens: []).isEmpty)
    }
}
