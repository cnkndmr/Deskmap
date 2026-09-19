import Testing
@testable import Deskmap

/// "Neden burada?" ipucu (saf).
struct WhyHereTests {

    @Test func noMatchNoExplanation() {
        #expect(Routing.explanation(for: nil, screenName: nil) == nil)
    }

    @Test func sessionPinExplained() {
        let match = Routing.Match(destination: Destination(screen: "builtin", desktop: 2),
                                  ruleID: Routing.sessionRuleID, rule: nil)
        let text = Routing.explanation(for: match, screenName: "Built-in")
        #expect(text?.contains("temporary pin") == true)
        #expect(text?.contains("Built-in · Desktop 2") == true)
    }

    @Test func ruleExplainedWithScreenFallback() {
        let destination = Destination(screen: "ext-1", desktop: 3, layout: .leftHalf)
        let rule = Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: ["Docs"],
                        docked: destination)
        let match = Routing.Match(destination: destination, ruleID: rule.id, rule: rule)
        let text = Routing.explanation(for: match, screenName: nil)
        #expect(text?.contains("\"Safari · Docs\"") == true)
        #expect(text?.contains("ext-1 · Desktop 3") == true)
    }
}
