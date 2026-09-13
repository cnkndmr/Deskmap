import CoreGraphics
import Foundation
import Testing
@testable import SpaceRouter

/// Ekran haritasının saf kararları: gölgede kalan kurallar.
struct MapLogicTests {

    private let external = Destination(screen: "external", desktop: 2)
    private let builtin = Destination(screen: "builtin", desktop: 1)

    private func window(_ id: CGWindowID, title: String,
                        app: (name: String, bundle: String) = ("Code", "com.microsoft.VSCode"))
        -> Router.WindowSnapshot {
        Router.WindowSnapshot(id: id, pid: 1, appName: app.name, bundleID: app.bundle,
                              title: title, placement: nil, frame: nil, isMinimized: false)
    }

    private func code(_ id: String, tokens: [String],
                      docked: Destination? = nil, undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "Code", bundleID: "com.microsoft.VSCode", tokens: tokens,
             docked: docked, undocked: undocked)
    }

    // MARK: Gölgede kalan kurallar

    @Test func appWideRuleLosingToSpecificIsShadowed() {
        let wide = code("wide", tokens: [], docked: builtin)
        let specific = code("atlas", tokens: ["atlas"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [wide, specific], windows: [window(1, title: "Store.swift — Atlas")],
            sessionPins: [:], mode: .docked)
        #expect(result.winners == ["atlas"])
        #expect(result.shadowedBy == ["wide": "atlas"])
    }

    @Test func ruleWinningElsewhereIsNotShadowed() {
        let wide = code("wide", tokens: [], docked: builtin)
        let specific = code("atlas", tokens: ["atlas"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [wide, specific],
            windows: [window(1, title: "Store.swift — Atlas"), window(2, title: "Other.swift")],
            sessionPins: [:], mode: .docked)
        // Geniş kural 2 numaralı pencerede kazandı; gölgede sayılmaz.
        #expect(result.winners == ["atlas", "wide"])
        #expect(result.shadowedBy.isEmpty)
    }

    @Test func sessionPinShadowsMatchingRule() {
        let rule = code("atlas", tokens: ["atlas"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [rule], windows: [window(1, title: "Atlas")],
            sessionPins: [1: builtin], mode: .docked)
        #expect(result.winners == [Routing.sessionRuleID])
        #expect(result.shadowedBy == ["atlas": Routing.sessionRuleID])
    }

    @Test func rulesWithoutTargetInModeOrWithoutWindowAreIgnored() {
        let noTarget = code("undockedOnly", tokens: ["atlas"], undocked: external)
        let wide = code("wide", tokens: [], docked: builtin)
        let closed = code("closed", tokens: ["comet"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [noTarget, wide, closed], windows: [window(1, title: "Atlas")],
            sessionPins: [:], mode: .docked)
        #expect(result.winners == ["wide"])
        // Bu modda hedefi olmayan kural gölgede değil (zaten devrede değil);
        // penceresi kapalı kural da değil (o "penceresi yok" çipi olarak görünür).
        #expect(result.shadowedBy.isEmpty)
    }

    @Test func firstShadowingWinnerIsReported() {
        let wide = code("wide", tokens: [], docked: builtin)
        let a = code("a", tokens: ["alpha"], docked: external)
        let b = code("b", tokens: ["beta"], docked: external)
        let result = ScreenMapView.shadows(
            rules: [wide, a, b],
            windows: [window(1, title: "Alpha"), window(2, title: "Beta")],
            sessionPins: [:], mode: .docked)
        #expect(result.shadowedBy == ["wide": "a"])
        #expect(result.winners == ["a", "b"])
    }

    @Test func emptyInputs() {
        let empty = ScreenMapView.shadows(rules: [], windows: [], sessionPins: [:], mode: .docked)
        #expect(empty == ScreenMapView.RuleShadows())
        let noWindows = ScreenMapView.shadows(
            rules: [code("x", tokens: [], docked: builtin)], windows: [],
            sessionPins: [:], mode: .docked)
        #expect(noWindows == ScreenMapView.RuleShadows())
    }
}
