import CoreGraphics
import Foundation
import Testing
@testable import SpaceRouter

/// `--shots` argüman ayrıştırması ve demo belgenin geçerliliği. Hiçbiri
/// diske yazmaz; `Shots.run` (PNG üretip `exit(0)` çağıran gerçek yol)
/// burada hiç çağrılmaz.
struct ShotsTests {

    // MARK: - Argüman ayrıştırma

    @Test func noShotsFlagReturnsNil() {
        #expect(Shots.parseOptions(["SpaceRouter"]) == nil)
        #expect(Shots.parseOptions(["SpaceRouter", "--other", "x"]) == nil)
    }

    @Test func shotsFlagWithoutValueReturnsNil() {
        #expect(Shots.parseOptions(["SpaceRouter", "--shots"]) == nil)
    }

    @Test func shotsFlagReadsDirectory() {
        let options = Shots.parseOptions(["SpaceRouter", "--shots", "/tmp/out"])
        #expect(options?.directory == "/tmp/out")
        #expect(options?.only == nil)
    }

    @Test func onlyFlagReadsCommaSeparatedNames() {
        let options = Shots.parseOptions(
            ["SpaceRouter", "--shots", "/tmp/out", "--only", "01-map, 03-layout"])
        #expect(options?.only == ["01-map", "03-layout"])
    }

    @Test func onlyFlagWithoutValueIsIgnored() {
        let options = Shots.parseOptions(["SpaceRouter", "--shots", "/tmp/out", "--only"])
        #expect(options?.directory == "/tmp/out")
        #expect(options?.only == nil)
    }

    @Test func shouldCaptureRespectsOnlyFilter() {
        let all = Shots.Options(directory: "/tmp", only: nil)
        #expect(Shots.shouldCapture("01-map", options: all))

        let filtered = Shots.Options(directory: "/tmp", only: ["02-pin"])
        #expect(!Shots.shouldCapture("01-map", options: filtered))
        #expect(Shots.shouldCapture("02-pin", options: filtered))
    }

    // MARK: - Demo belgesi

    @Test func profilesAreNotEmpty() {
        let world = DemoData.make()
        #expect(!world.document.profiles.isEmpty)
        for profile in world.document.profiles {
            #expect(!profile.rules.isEmpty)
        }
    }

    @Test func activeProfileMatchesTopLevelRules() {
        let world = DemoData.make()
        #expect(world.document.rules == world.document.activeProfile?.rules)
        #expect(world.document.activeProfile?.name == "Desk")
    }

    @Test func demoRuleDestinationsPointAtKnownScreens() {
        let world = DemoData.make()
        let knownIDs = Set(world.document.screens.map(\.id))
        #expect(knownIDs == ["builtin", "external"])
        for rule in world.document.rules {
            if let docked = rule.docked { #expect(knownIDs.contains(docked.screen)) }
            if let undocked = rule.undocked { #expect(knownIDs.contains(undocked.screen)) }
        }
    }

    @Test func referencedRuleAndWindowIDsExist() {
        let world = DemoData.make()
        #expect(world.document.rules.contains { $0.id == DemoData.messagesRuleID })
        #expect(world.document.rules.contains { $0.id == DemoData.extraRuleID })
        #expect(world.windows.contains { $0.id == DemoData.unpinnedMessagesWindowID })
    }

    @Test func pinnedWindowResolvesThroughRouting() {
        let world = DemoData.make()
        guard let reminders = world.windows.first(where: { $0.appName == "Reminders" }) else {
            Issue.record("Demo dünyasında Reminders penceresi yok")
            return
        }
        let match = Routing.select(
            rules: world.document.rules, sessionPins: [:], mode: .docked,
            windowID: reminders.id, bundleID: reminders.bundleID, appName: reminders.appName,
            title: reminders.title)
        #expect(match?.destination.screen == "external")
    }

    @Test func unpinnedWindowDoesNotResolve() {
        let world = DemoData.make()
        guard let window = world.windows.first(where: { $0.id == DemoData.unpinnedMessagesWindowID })
        else {
            Issue.record("Pinsiz demo penceresi yok")
            return
        }
        let match = Routing.select(
            rules: world.document.rules, sessionPins: [:], mode: .docked,
            windowID: window.id, bundleID: window.bundleID, appName: window.appName,
            title: window.title)
        #expect(match == nil)
    }
}
