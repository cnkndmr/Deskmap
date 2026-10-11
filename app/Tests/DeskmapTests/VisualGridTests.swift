import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Görsel haritanın kart ızgarası ve kalabalık masaüstü kuralı (saf).
struct VisualGridTests {

    private let bounds = CGRect(x: 0, y: 0, width: 270, height: 170)
    private var full: CGRect { bounds.insetBy(dx: 1, dy: 1) }
    private var leftHalf: CGRect { CGRect(x: 1, y: 1, width: 134, height: 168) }

    // MARK: - Örtüşme ve yığınlar

    @Test func overlapRatio() {
        #expect(CardPreviewLayout.overlapRatio(full, full) == 1)
        #expect(CardPreviewLayout.overlapRatio(leftHalf, CGRect(x: 136, y: 1, width: 133, height: 168)) == 0)
        let half = CardPreviewLayout.overlapRatio(full, leftHalf)
        #expect(half > 0.49 && half < 0.51)
    }

    @Test func sameFrameWindowsStackHalvesStaySeparate() {
        let rects = [full, full, leftHalf, full.insetBy(dx: 3, dy: 3)]
        #expect(CardPreviewLayout.stacks(rects) == [[0, 1, 3], [2]])
    }

    @Test func crowdedDesktopCascadesAndCountsTheRest() {
        let rects = Array(repeating: full, count: 10)
        let result = CardPreviewLayout.arrange(rects, bounds: bounds)
        // (168 - 32) / 16 + 1 = 9 sığar, en çok 8 çizilir.
        #expect(result.boxes.count == CardPreviewLayout.maxShown)
        #expect(result.boxes.map(\.item) == Array(0..<8))
        #expect(result.more.count == 1)
        #expect(result.more[0].items == [8, 9])
        // Her kutu bir öncekinin bir sekme altından başlar; her birinin adı görünür.
        for (offset, box) in result.boxes.enumerated() {
            #expect(box.rect.minY == full.minY + CGFloat(offset) * CardPreviewLayout.tab)
            #expect(box.rect.maxY == full.maxY)
            #expect(box.label != nil)
            #expect((box.label?.width ?? 0) > 200)
        }
    }

    @Test func selectedHiddenWindowTakesTheLastSlot() {
        let rects = Array(repeating: full, count: 10)
        let result = CardPreviewLayout.arrange(rects, bounds: bounds, keep: [9])
        #expect(result.boxes.map(\.item) == [0, 1, 2, 3, 4, 5, 6, 9])
        #expect(result.more[0].items == [7, 8])
    }

    @Test func visibleMembersKeepsOrderAndRespectsKeep() {
        #expect(CardPreviewLayout.visibleMembers([4, 5, 6, 7], count: 2, keep: []) == [4, 5])
        #expect(CardPreviewLayout.visibleMembers([4, 5, 6, 7], count: 2, keep: [7]) == [4, 7])
        // Hepsi tutulacaksa sığan kadarı: ilk sıradakiler.
        #expect(CardPreviewLayout.visibleMembers([4, 5, 6], count: 1, keep: [4, 6]) == [4])
    }

    @Test func capacityFollowsHeight() {
        #expect(CardPreviewLayout.capacity(height: 20) == 1)
        #expect(CardPreviewLayout.capacity(height: 48) == 2)
        #expect(CardPreviewLayout.capacity(height: 1000) == CardPreviewLayout.maxShown)
    }

    @Test func biggerWindowsAreDrawnBehindSmallerOnes() {
        let small = CGRect(x: 150, y: 60, width: 80, height: 60)
        let result = CardPreviewLayout.arrange([small, full], bounds: bounds)
        #expect(result.boxes.map(\.item) == [1, 0])
    }

    @Test func labelMovesToTheUncoveredPartOfTheTitleStrip() {
        // Tam ekran kutu arkada, sol yarı önde: tam kutunun adı sağ yarıda.
        let slot = CardPreviewLayout.labelSlot(0, in: [full, leftHalf])
        #expect(slot?.minX == leftHalf.maxX)
        #expect(slot?.maxX == full.maxX)
        // Aynı kutu tamamen örtülürse ad yok.
        #expect(CardPreviewLayout.labelSlot(0, in: [leftHalf, full]) == nil)
        // Alt alta değen basamak şeridi örtmez.
        let below = CGRect(x: 1, y: 1 + CardPreviewLayout.tab, width: 268, height: 100)
        #expect(CardPreviewLayout.labelSlot(0, in: [full, below])?.width == full.width)
    }

    @Test func boxesOutsideTheScreenAreDropped() {
        let outside = CGRect(x: 400, y: 10, width: 50, height: 50)
        let result = CardPreviewLayout.arrange([outside, leftHalf], bounds: bounds)
        #expect(result.boxes.map(\.item) == [1])
    }

    // MARK: - Izgara

    @Test func gridColumnsFollowWidth() {
        let min = CardGridLayout.minCardWidth
        #expect(CardGridLayout.columns(width: 240, minWidth: min, spacing: 10) == 1)
        // Harita sütunu 1710 pt ekranda ≈ 567 pt: iki kart.
        #expect(CardGridLayout.columns(width: 567, minWidth: min, spacing: 10) == 2)
        #expect(CardGridLayout.columns(width: 770, minWidth: min, spacing: 10) == 3)
        #expect(CardGridLayout.columns(width: .infinity, minWidth: min, spacing: 10) == 1)
        #expect(CardGridLayout.columnWidth(width: 570, columns: 2, spacing: 10) == 280)
    }

    @Test func screenAspectIsClamped() {
        #expect(CardScreen.aspect(of: CGSize(width: 1600, height: 1000)) == 1.6)
        #expect(CardScreen.aspect(of: CGSize(width: 1000, height: 2000)) == 0.9)
        #expect(CardScreen.aspect(of: CGSize(width: 1000, height: 0)) == 1.6)
    }

    @Test func listKeyNamesPlanScreenAndDesktop() {
        #expect(UIState.listKey(mode: .docked, screen: "builtin", desktop: 3)
                == "\(Mode.docked.rawValue)|builtin|3")
    }

    // MARK: - Ayrıntı sütunu

    @Test func desktopChoicesIncludeRealPlannedAndCurrent() {
        let current = Destination(screen: "ext", desktop: 6)
        #expect(DestinationChoices.desktopCount(real: 3, planned: 0, current: current, screen: "ext") == 6)
        #expect(DestinationChoices.desktopCount(real: 3, planned: 4, current: current, screen: "builtin") == 4)
        #expect(DestinationChoices.desktopCount(real: nil, planned: 0, current: current, screen: "x") == 1)
    }

    @Test func whyHereSentenceIsCapitalised() {
        #expect(WhyHereBox.sentence("pin \"Mail\"", locale: Locale(identifier: "en")) == "Pin \"Mail\"")
        #expect(WhyHereBox.sentence("istanbul", locale: Locale(identifier: "tr")) == "İstanbul")
        #expect(WhyHereBox.sentence("") == "")
    }

    @Test func reasonIsTheExplanationWithoutItsPrefix() {
        let destination = Destination(screen: "builtin", desktop: 2, layout: .leftHalf)
        let rule = Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: ["Docs"],
                        docked: destination)
        let match = Routing.Match(destination: destination, ruleID: rule.id, rule: rule)
        let reason = Routing.reason(for: match, screenName: "Built-in")
        #expect(reason?.hasPrefix("pin \"Safari · Docs\"") == true)
        #expect(Routing.explanation(for: match, screenName: "Built-in") == "Why here: " + (reason ?? ""))
        #expect(Routing.reason(for: nil, screenName: nil) == nil)
    }

    // MARK: - Kenar çubuğu

    @Test func quickStartPinsOnlyPlaceableWindows() {
        func window(_ id: CGWindowID, placed: Bool, fullscreen: Bool = false) -> Router.WindowSnapshot {
            Router.WindowSnapshot(
                id: id, pid: 1, appName: "Mail", bundleID: "com.apple.mail", title: "x",
                placement: placed ? Router.Placement(screen: "builtin", desktop: 1) : nil,
                frame: nil, isMinimized: false,
                fullscreen: fullscreen
                    ? Router.FullscreenSlot(screen: "builtin", space: 1, afterDesktop: 1, order: 1) : nil)
        }
        let windows = [window(1, placed: true), window(2, placed: false),
                       window(3, placed: true, fullscreen: true)]
        #expect(QuickStartCard.placeable(windows).map(\.id) == [1])
    }

    // MARK: - Shots

    @Test func scenarioFlagIsParsed() {
        let options = Shots.parseOptions(["Deskmap", "--shots", "/tmp/out", "--scenario", "crowded"])
        #expect(options?.scenario == "crowded")
        #expect(Shots.parseOptions(["Deskmap", "--shots", "/tmp/out"])?.scenario == nil)
    }

    @Test func crowdedWorldHasACrowdedDesktop() {
        let world = DemoData.crowded()
        let first = world.windows.filter { $0.placement == Router.Placement(screen: "builtin", desktop: 1) }
        #expect(first.count >= 8)
        #expect(world.windows.contains { $0.fullscreen != nil })
        #expect(world.document.rules.filter { $0.appName == "Preview" }.count == 5)
    }
}
