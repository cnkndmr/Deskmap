import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// `--shots` argüman ayrıştırması ve demo belgenin geçerliliği. Hiçbiri
/// diske yazmaz; `Shots.run` (PNG üretip `exit(0)` çağıran gerçek yol)
/// burada hiç çağrılmaz.
struct ShotsTests {

    // MARK: - Argüman ayrıştırma

    @Test func noShotsFlagReturnsNil() {
        #expect(Shots.parseOptions(["Deskmap"]) == nil)
        #expect(Shots.parseOptions(["Deskmap", "--other", "x"]) == nil)
    }

    @Test func shotsFlagWithoutValueReturnsNil() {
        #expect(Shots.parseOptions(["Deskmap", "--shots"]) == nil)
    }

    @Test func shotsFlagReadsDirectory() {
        let options = Shots.parseOptions(["Deskmap", "--shots", "/tmp/out"])
        #expect(options?.directory == "/tmp/out")
        #expect(options?.only == nil)
    }

    @Test func onlyFlagReadsCommaSeparatedNames() {
        let options = Shots.parseOptions(
            ["Deskmap", "--shots", "/tmp/out", "--only", "01-map, 03-layout"])
        #expect(options?.only == ["01-map", "03-layout"])
    }

    @Test func onlyFlagWithoutValueIsIgnored() {
        let options = Shots.parseOptions(["Deskmap", "--shots", "/tmp/out", "--only"])
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

    // MARK: - Demo dizisi (--scenario demo)

    @Test func scenarioFlagIsParsed() {
        let options = Shots.parseOptions(["Deskmap", "--shots", "/tmp/out", "--scenario", "demo"])
        #expect(options?.scenario == "demo")
    }

    @Test func demoSequenceStagesAreConsistent() {
        for stage in DemoData.DemoStage.allCases {
            let screens = DemoData.demoScreens(stage)
            let screenIDs = Set(screens.map(\.id))
            let document = DemoData.demoDocument(stage)
            let counts = DemoData.demoDesktopCounts(stage)
            #expect(Set(counts.keys) == screenIDs)
            #expect(document.rules == document.activeProfile?.rules)
            for rule in document.rules {
                #expect(rule.undocked == nil)
                if let docked = rule.docked {
                    #expect(document.screens.contains { $0.id == docked.screen })
                    #expect(docked.desktop <= (counts[docked.screen] ?? counts["builtin"] ?? 0))
                }
            }
            for window in DemoData.demoWindows(stage) {
                #expect(window.frame != nil)
                guard let placement = window.placement else {
                    Issue.record("Demo dizisi penceresi yerleşimsiz: \(window.id)")
                    continue
                }
                #expect(screenIDs.contains(placement.screen))
            }
        }
    }

    @Test func demoSequenceWindowsStartPiledThenLandOnTheirRule() {
        let piled = DemoData.demoWindows(.monitorConnected)
        #expect(piled.allSatisfy { $0.placement == Router.Placement(screen: "builtin", desktop: 1) })
        for stage in [DemoData.DemoStage.placed, .secondMonitor] {
            let rules = DemoData.demoRules(stage)
            for window in DemoData.demoWindows(stage) {
                let match = Routing.select(
                    rules: rules, sessionPins: [:], mode: .docked, windowID: window.id,
                    bundleID: window.bundleID, appName: window.appName, title: window.title)
                #expect(match?.destination.screen == window.placement?.screen)
                #expect(match?.destination.desktop == window.placement?.desktop)
            }
        }
        #expect(DemoData.demoWindows(.secondMonitor).contains { $0.placement?.screen == "external-2" })
    }

    // MARK: - Pin grubu demosu

    /// Kalabalık senaryonun "Nova drafts" grubu geçerli: 3 üye, ad dolu, aynı
    /// masaüstünde (laptop 3, monitörlü planda), Expo_template grupsuz;
    /// kayıt hem profilde hem çalışma kopyasında.
    @Test func crowdedPinGroupIsValid() throws {
        let world = DemoData.crowded()
        let doc = world.document
        let group = try #require(doc.pinGroup(DemoData.crowdedPinGroupID))
        #expect(!group.name.isEmpty)
        #expect(doc.activeProfile?.pinGroups == [group])
        let members = doc.pinGroupMembers(group.id, mode: .docked)
        #expect(members.count == 3)
        #expect(Set(members.compactMap(\.docked).map { "\($0.screen)/\($0.desktop)" }) == ["builtin/3"])
        let expo = try #require(doc.rules.first { $0.tokens == ["Expo_template"] })
        #expect(expo.groupID == nil)
        // Kutu çizilir: kapalı üyeler aynı masaüstünde tek kutuda.
        let split = PinGroupLayout.split(windows: [], closed: doc.rules.filter { $0.docked?.desktop == 3
                                                                                  && $0.docked?.screen == "builtin" },
                                         groups: doc.pinGroups, ruleFor: { _ in nil })
        #expect(split.boxes.count == 1)
        #expect(split.boxes.first?.total == 3)
        #expect(split.restClosed.contains { $0.id == expo.id })
    }
}
