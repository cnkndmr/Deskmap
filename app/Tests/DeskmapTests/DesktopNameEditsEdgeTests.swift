import Foundation
import Testing
@testable import Deskmap

/// Masaüstü adı düzenlemeleri (`DesktopNameEdits`, `DesktopNamesV2`) kenar
/// durumları: silme sonrası kayma, yetim ad pini kalmaması, hayalet geri
/// getirme, ad çakışması (büyük/küçük harf, Unicode), taşıma, plan
/// yeniden yazımı. Yalnız uydurma veri; disk yok.
struct DesktopNameEdgeTests {

    private func rule(_ id: String, docked: Destination? = nil, undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "App-\(id)", bundleID: "b.\(id)", tokens: [id],
             docked: docked, undocked: undocked)
    }

    private func set(_ d: inout Document, _ name: String?, screen: String, desktop: Int, mode: Mode,
                     live: LiveDesktops? = nil) -> Bool {
        d.setDesktopName(name, screen: screen, desktop: desktop, mode: mode, live: live)
    }

    private func twoProfiles(_ configure: (inout Document) -> Void,
                             other: (inout Document) -> Void) -> (Document, firstID: String, otherID: String) {
        var d = Document()
        configure(&d)
        d.syncActiveProfile()
        let first = d.activeProfileID
        let added = d.addProfile(named: "Other", activate: true)
        other(&d)
        d.syncActiveProfile()
        d.switchProfile(to: first)
        return (d, first, added.id)
    }

    /// Hiçbir kuralın hedefi kayıtsız bir ada bakmaz (etkin çalışma kopyası
    /// ve bütün profiller).
    private func assertNoOrphanNamePins(_ d: Document, sourceLocation: SourceLocation = #_sourceLocation) {
        func check(_ rules: [Rule], _ names: [DesktopName], _ label: String) {
            let ids = Set(names.map(\.id))
            for rule in rules {
                for mode in Mode.allCases {
                    for place in rule.places(mode) {
                        if let id = place.nameID {
                            #expect(ids.contains(id), "\(label): \(rule.id) -> missing name \(id)",
                                    sourceLocation: sourceLocation)
                        }
                    }
                }
            }
        }
        check(d.rules, d.names, "active")
        for profile in d.profiles where profile.id != d.activeProfileID {
            check(profile.rules, profile.names, profile.name)
        }
    }

    // MARK: - Silme: numara kayması

    @Test func unnamedDeletionGhostsTheRowAndShiftsLaterNumbers() {
        var d = V6.document(rules: [
            rule("r1", docked: V6.e(1)), rule("r2", docked: V6.e(2)), rule("r3", docked: V6.e(3)),
            rule("rb", docked: V6.b(2)),
            rule("ru", undocked: V6.at("external", 3)),
        ])
        let ghost = d.recordDeletion(space: nil, role: "external", desktop: 2, mode: .docked,
                                     now: V6.incident)
        #expect(ghost?.pins.map(\.rule.id) == ["r2"])
        #expect(ghost?.name == nil && ghost?.screen == "external" && ghost?.desktop == 2)
        #expect(d.rules.map(\.id) == ["r1", "r3", "rb", "ru"]) // r2 yalnız bu pindi: kural gitti
        #expect(d.rule("r1")?.docked?.desktop == 1)
        #expect(d.rule("r3")?.docked?.desktop == 2)
        #expect(d.rule("rb")?.docked?.desktop == 2) // başka ekran
        #expect(d.rule("ru")?.undocked?.desktop == 3) // başka kurulum (harici ekranda ortak değil)
        #expect(d.ghostDesktops.count == 1)
    }

    @Test func laptopDeletionShiftsBothSetups() {
        var d = V6.document(rules: [
            rule("both", docked: V6.b(3), undocked: V6.b(3)),
            rule("gone", docked: V6.b(2), undocked: V6.b(2)),
            rule("dockedOnly", docked: V6.b(4)),
        ])
        let ghost = d.recordDeletion(space: nil, role: "builtin", desktop: 2, mode: .docked)
        #expect(d.rule("both")?.docked?.desktop == 2 && d.rule("both")?.undocked?.desktop == 2)
        #expect(d.rule("gone") == nil)
        #expect(d.rule("dockedOnly")?.docked?.desktop == 3)
        #expect(Set(ghost?.pins.map(\.mode) ?? []) == [.docked, .undocked])
    }

    @Test func explicitShiftModesLimitTheShift() {
        var d = V6.document(rules: [rule("a", docked: V6.b(3), undocked: V6.b(3))])
        d.recordDeletion(space: nil, role: "builtin", desktop: 1, mode: .docked, shiftModes: [.docked])
        #expect(d.rule("a")?.docked?.desktop == 2)
        #expect(d.rule("a")?.undocked?.desktop == 3)
    }

    @Test func deletingAnEmptyPlanRowCollapsesItButNeverANamedRow() {
        var d = V6.document(names: [DesktopName(id: "M", name: "Mail", space: 11)],
                            plans: DesktopPlans(docked: ["external": ["", "M", ""]]))
        d.recordDeletion(space: nil, role: "external", desktop: 3, mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["", "M"])
        // Adlı satır numarayla (space bilinmeden) silinmez: ad plandan düşmez.
        d.recordDeletion(space: nil, role: "external", desktop: 2, mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["", "M"])
        #expect(d.names.map(\.id) == ["M"])
    }

    @Test func pinsOfDeletedUnnamedDesktopOnlyGhostInTheirOwnMode() {
        var d = V6.document(rules: [
            rule("x", docked: V6.e(2), undocked: V6.at("external", 2)),
        ])
        let ghost = d.recordDeletion(space: nil, role: "external", desktop: 2, mode: .docked)
        #expect(ghost?.pins.map(\.mode) == [.docked])
        #expect(d.rule("x")?.undocked?.desktop == 2)
        #expect(d.rule("x")?.docked == nil)
    }

    @Test func orderedPlacesKeepTheirOrderInTheGhost() {
        var r = rule("multi", docked: V6.e(1))
        r.setPlaces([V6.e(1), V6.at("external-2", 4), V6.b(2)], mode: .docked)
        var d = V6.document(rules: [r])
        let ghost = d.recordDeletion(space: nil, role: "external-2", desktop: 4, mode: .docked)
        #expect(ghost?.pins.first?.order == 1)
        #expect(d.rule("multi")?.places(.docked).map(\.screen) == ["external", "builtin"])
    }

    // MARK: - Silme: adlar

    @Test func namedDeletionRemovesNameCollapsesPlansAndGhostsAllPins() {
        var d = V6.document(
            rules: [
                rule("byName", docked: V6.at("external", 2, name: "M")),
                rule("byNumber", docked: V6.e(2)),
                rule("later", docked: V6.e(3)),
                rule("keep", docked: V6.e(1)),
            ],
            names: [DesktopName(id: "M", name: "Nova", space: 20)],
            plans: DesktopPlans(docked: ["external": ["", "M", ""]], undocked: ["builtin": ["M"]]))
        let ghost = d.recordDeletion(space: 20, role: "external", desktop: 2, mode: .docked,
                                     now: V6.incident)
        #expect(d.names.isEmpty)
        #expect(d.plans.entries(.docked, "external") == ["", ""])
        #expect(d.plans.entries(.undocked, "builtin").isEmpty)
        #expect(ghost?.name == "Nova" && ghost?.nameID == "M" && ghost?.deletedAt == V6.incident)
        #expect(Set(ghost?.pins.map(\.rule.id) ?? []) == ["byName", "byNumber"])
        #expect(d.rule("later")?.docked?.desktop == 2)
        #expect(d.rule("keep")?.docked?.desktop == 1)
        assertNoOrphanNamePins(d)
    }

    /// 12.10 olayının sınıfı: silinen masaüstünün ADI, öbür adların pinlerini
    /// ve kayıtlarını götürmemeli; adlı pinler konumdan değil addan çözülür.
    @Test func deletingOneNamedDesktopKeepsOtherNamesAndTheirPins() {
        var d = V6.document(
            rules: [
                rule("pa", docked: V6.at("external", 1, name: "A")),
                rule("pb", docked: V6.at("external", 2, name: "B")),
                rule("pc", docked: V6.at("external", 3, name: "C")),
                rule("n3", docked: V6.e(3)),
            ],
            names: [DesktopName(id: "A", name: "Alpha", space: 10), DesktopName(id: "B", name: "Beta", space: 11),
                    DesktopName(id: "C", name: "Gamma", space: 12)],
            plans: DesktopPlans(docked: ["external": ["A", "B", "C"]]))
        let ghost = d.recordDeletion(space: 11, role: "external", desktop: 2, mode: .docked)
        #expect(d.names.map(\.id) == ["A", "C"])
        #expect(d.plans.entries(.docked, "external") == ["A", "C"])
        #expect(ghost?.pins.map(\.rule.id) == ["pb"])
        #expect(d.rule("pa")?.docked?.nameID == "A" && d.rule("pc")?.docked?.nameID == "C")
        #expect(d.rule("n3")?.docked?.desktop == 2) // numara pini konumla kayar
        // Önbellek, canlı yeni sıraya göre yenilenince adlar kendi yerine bakar.
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 12]])
        d.refreshNameCaches(live: live)
        #expect(d.rule("pc")?.docked?.desktop == 2)
        #expect(d.rule("pa")?.docked?.desktop == 1)
        assertNoOrphanNamePins(d)
    }

    @Test func deletionWithUnknownSpaceNeverTouchesNamePins() {
        var d = V6.document(
            rules: [rule("p", docked: V6.at("external", 2, name: "M"))],
            names: [DesktopName(id: "M", name: "Nova", space: 20)],
            plans: DesktopPlans(docked: ["external": ["", "M"]]))
        d.recordDeletion(space: 999, role: "external", desktop: 2, mode: .docked)
        #expect(d.names.map(\.id) == ["M"])
        #expect(d.rule("p")?.docked?.nameID == "M")
        #expect(d.ghostDesktops.isEmpty)
    }

    @Test func deletionAppliesToEveryProfileWithItsOwnNamesAndPins() {
        let (built, firstID, otherID) = twoProfiles({ d in
            d.rules = [rule("p1", docked: V6.at("external", 2, name: "M"))]
            d.names = [DesktopName(id: "M", name: "Nova", space: 20)]
            d.plans = DesktopPlans(docked: ["external": ["", "M"]])
        }, other: { d in
            d.rules = [rule("p2", docked: V6.at("external", 2, name: "M2")), rule("p3", docked: V6.e(3))]
            d.names = [DesktopName(id: "M2", name: "Nova", space: 20)]
            d.plans = DesktopPlans(docked: ["external": ["", "M2", ""]])
        })
        var d = built
        let ghost = d.recordDeletion(space: 20, role: "external", desktop: 2, mode: .docked)
        #expect(ghost?.pins.map(\.profileID) == [firstID])
        let other = d.profiles.first { $0.id == otherID }!
        #expect(other.names.isEmpty)
        #expect(other.ghostDesktops.count == 1)
        #expect(other.ghostDesktops.first?.pins.map(\.profileID) == [otherID])
        #expect(other.rules.map(\.id) == ["p3"])
        #expect(other.rules.first?.docked?.desktop == 2)
        #expect(d.names.isEmpty && d.ghostDesktops.count == 1)
        assertNoOrphanNamePins(d)
    }

    @Test func deletingTwiceWithSameNameMergesIntoOneGhostWithoutDuplicatePins() {
        var d = V6.document(
            rules: [rule("p", docked: V6.at("external", 2, name: "M"))],
            names: [DesktopName(id: "M", name: "Nova", space: 20)],
            plans: DesktopPlans(docked: ["external": ["", "M"]]))
        let first = d.recordDeletion(space: 20, role: "external", desktop: 2, mode: .docked)
        // Aynı adla yeniden kurulup yine silinirse ayrı hayalet açılmaz.
        d.names = [DesktopName(id: "M", name: "nova", space: 21)]
        d.rules.append(rule("q", docked: V6.at("external", 2, name: "M")))
        let second = d.recordDeletion(space: 21, role: "external", desktop: 2, mode: .docked)
        #expect(d.ghostDesktops.count == 1)
        #expect(second?.id == first?.id)
        #expect(Set(second?.pins.map(\.rule.id) ?? []) == ["p", "q"])
    }

    // MARK: - Mission Control'ü izleme

    private func followFixture() -> Document {
        V6.document(
            rules: [rule("rb", docked: V6.at("external", 2, name: "B")),
                    rule("rc", docked: V6.at("external", 3, name: "C")),
                    rule("n3", docked: V6.e(3))],
            names: [DesktopName(id: "A", name: "Alpha", space: 10), DesktopName(id: "B", name: "Beta", space: 11),
                    DesktopName(id: "C", name: "Gamma", space: 12)],
            plans: DesktopPlans(docked: ["external": ["A", "B", "C"]]))
    }

    @Test func missionControlDeletionGhostsNameAndKeepsPlanAligned() {
        var d = followFixture()
        let deletions = d.followMissionControl(before: ["external": [10, 11, 12]],
                                               after: ["external": [10, 12]], mode: .docked)
        #expect(deletions == [DesktopDeletion(role: "external", desktop: 2, space: 11, ghost: true)])
        #expect(d.names.map(\.id) == ["A", "C"])
        #expect(d.plans.entries(.docked, "external") == ["A", "C"])
        #expect(d.rule("rb") == nil)
        #expect(d.rule("rc")?.docked?.nameID == "C")
        #expect(d.rule("n3")?.docked?.desktop == 2)
        assertNoOrphanNamePins(d)
    }

    @Test func ownRemovalsAreNotTreatedAsMissionControlDeletions() {
        var d = followFixture()
        let deletions = d.followMissionControl(before: ["external": [10, 11, 12]],
                                               after: ["external": [10, 12]], mode: .docked,
                                               ownRemovals: [11])
        #expect(deletions.isEmpty)
        #expect(d.names.count == 3 && d.ghostDesktops.isEmpty)
    }

    @Test func roleMissingFromAfterIsIgnored() {
        var d = followFixture()
        let deletions = d.followMissionControl(before: ["external": [10, 11, 12]],
                                               after: ["builtin": [1]], mode: .docked)
        #expect(deletions.isEmpty)
        #expect(d.names.count == 3 && d.plans.entries(.docked, "external") == ["A", "B", "C"])
    }

    @Test func severalDeletionsInOneRoleApplyHighestFirstSoNumbersStayRight() {
        var d = V6.document(rules: [
            rule("p2", docked: V6.e(2)), rule("p3", docked: V6.e(3)), rule("p4", docked: V6.e(4)),
            rule("p1", docked: V6.e(1)),
        ])
        let deletions = d.followMissionControl(before: ["external": [10, 11, 12, 13]],
                                               after: ["external": [10, 13]], mode: .docked)
        #expect(deletions.map(\.desktop) == [3, 2])
        #expect(d.rule("p1")?.docked?.desktop == 1)
        #expect(d.rule("p4")?.docked?.desktop == 2)
        #expect(d.rule("p2") == nil && d.rule("p3") == nil)
        #expect(d.ghostDesktops.count == 2)
    }

    @Test func plainDeletionWithoutNameOrPinsLeavesNoGhost() {
        var d = V6.document(rules: [rule("p3", docked: V6.e(3))])
        let deletions = d.followMissionControl(before: ["external": [10, 11, 12]],
                                               after: ["external": [10, 12]], mode: .docked)
        #expect(deletions.map(\.ghost) == [false])
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.rule("p3")?.docked?.desktop == 2)
    }

    @Test func addedDesktopExtendsThePlanAndKeepsNames() {
        var d = V6.document(names: [DesktopName(id: "N", name: "Nova", space: 11)],
                            plans: DesktopPlans(docked: ["external": ["", "N"]]))
        d.followMissionControl(before: ["external": [10, 11]], after: ["external": [10, 11, 12]],
                               mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["", "N", ""])
    }

    @Test func reorderedDesktopsRewritePlanByLiveOrder() {
        var d = V6.document(names: [DesktopName(id: "N", name: "Nova", space: 11)],
                            plans: DesktopPlans(docked: ["external": ["", "N", ""]]))
        d.followMissionControl(before: ["external": [10, 11, 12]], after: ["external": [11, 10, 12]],
                               mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["N", "", ""])
    }

    @Test func unplacedNamesStayInThePlanTail() {
        var d = V6.document(names: [DesktopName(id: "N", name: "Nova", space: 11),
                                    DesktopName(id: "W", name: "Waiting", space: nil)],
                            plans: DesktopPlans(docked: ["external": ["", "N", "W"]]))
        d.followMissionControl(before: ["external": [10, 11]], after: ["external": [11, 10]],
                               mode: .docked)
        #expect(d.plans.entries(.docked, "external").contains("W"))
        #expect(d.plans.place(of: "N", mode: .docked)?.desktop == 1)
    }

    // MARK: - Ad verme

    @Test func namingBindsToTheLiveSpaceAndConvertsNumberPins() {
        var d = V6.document(rules: [rule("p", docked: V6.e(2)), rule("q", docked: V6.e(3))])
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 11, 12]])
        let accepted = d.setDesktopName("  Mail \n", screen: "external", desktop: 2, mode: .docked, live: live)
        #expect(accepted)
        let record = d.names.first
        #expect(record?.name == "Mail" && record?.space == 11)
        #expect(d.plans.entries(.docked, "external") == ["", record!.id])
        // N1: monitördeki ad laptop planının sonuna da girer.
        #expect(d.plans.entries(.undocked, "builtin") == [record!.id])
        #expect(d.rule("p")?.docked?.nameID == record?.id)
        #expect(d.rule("q")?.docked?.nameID == nil)
    }

    @Test func nameConflictIsCaseWhitespaceAndUnicodeInsensitive() {
        var d = V6.document(names: [DesktopName(id: "N", name: "Café Üst", space: nil)],
                            plans: DesktopPlans(docked: ["external": ["N"]]))
        // "é" ayrışık yazımı (e + birleşik vurgu) ve büyük harf aynı ad sayılır.
        #expect(!set(&d, "  CAFE\u{301} üst ", screen: "external", desktop: 2, mode: .docked))
        #expect(!set(&d, "café üst", screen: "builtin", desktop: 1, mode: .undocked))
        #expect(d.names.count == 1)
        // Farklı ad serbest.
        #expect(set(&d, "Cafe Ust", screen: "external", desktop: 2, mode: .docked))
        #expect(d.names.count == 2)
    }

    @Test func emptyAndWhitespaceNamesNeverCreateRecords() {
        var d = V6.document()
        #expect(set(&d, nil, screen: "external", desktop: 1, mode: .docked))
        #expect(set(&d, "   \n\t", screen: "external", desktop: 1, mode: .docked))
        #expect(d.names.isEmpty && d.plans.isEmpty)
    }

    @Test func unicodeAndEmojiNamesRoundTripThroughLookups() {
        var d = V6.document()
        for (index, name) in ["🚀 Lab", "日本語", "Ünal/Çalışma", "a\u{200B}b"].enumerated() {
            #expect(set(&d, name, screen: "external", desktop: index + 1, mode: .docked))
        }
        #expect(d.desktopName(screen: "external", desktop: 1, mode: .docked) == "🚀 Lab")
        #expect(d.desktopName(screen: "external", desktop: 2, mode: .docked) == "日本語")
        #expect(d.desktopName(screen: "external", desktop: 3, mode: .docked) == "Ünal/Çalışma")
        #expect(d.nameRecord(named: "日本語") != nil)
        let back = try? JSONDecoder().decode(Document.self, from: Store.encode(d))
        #expect(back?.names == d.names)
    }

    @Test func renamingKeepsIdentityAndPinsAndRejectsStolenNames() {
        var d = V6.document(
            rules: [rule("p", docked: V6.at("external", 1, name: "A"))],
            names: [DesktopName(id: "A", name: "Alpha", space: nil), DesktopName(id: "B", name: "Beta", space: nil)],
            plans: DesktopPlans(docked: ["external": ["A", "B"]]))
        #expect(set(&d, "ALPHA", screen: "external", desktop: 1, mode: .docked))
        #expect(d.nameRecord("A")?.name == "ALPHA")
        #expect(!set(&d, "beta", screen: "external", desktop: 1, mode: .docked))
        #expect(d.nameRecord("A")?.name == "ALPHA")
        #expect(d.rule("p")?.docked?.nameID == "A")
    }

    @Test func emptyingARowNameTurnsNamePinsBackIntoNumberPins() {
        var d = V6.document(
            rules: [rule("p", docked: V6.at("external", 2, name: "M"), undocked: V6.at("builtin", 1, name: "M"))],
            names: [DesktopName(id: "M", name: "Nova", space: nil)],
            plans: DesktopPlans(docked: ["external": ["", "M"]], undocked: ["builtin": ["M"]]))
        #expect(set(&d, "  ", screen: "external", desktop: 2, mode: .docked))
        #expect(d.names.isEmpty)
        #expect(d.plans.entries(.docked, "external") == ["", ""])
        #expect(d.plans.entries(.undocked, "builtin") == [""])
        #expect(d.rule("p")?.docked?.nameID == nil && d.rule("p")?.docked?.desktop == 2)
        #expect(d.rule("p")?.undocked?.nameID == nil && d.rule("p")?.undocked?.desktop == 1)
        assertNoOrphanNamePins(d)
    }

    @Test func laptopNamePlacesATwinInTheOtherSetup() {
        var d = V6.document(rules: [rule("p", docked: V6.b(2), undocked: V6.b(2))])
        #expect(set(&d, "Notes", screen: "builtin", desktop: 2, mode: .undocked))
        let id = d.names[0].id
        #expect(d.plans.entries(.undocked, "builtin") == ["", id])
        #expect(d.plans.entries(.docked, "builtin") == ["", id]) // aynı sıra boş: aynı yer
        #expect(d.rule("p")?.undocked?.nameID == id)
        #expect(d.rule("p")?.docked?.nameID == id) // ikiz aynı sırada
    }

    @Test func laptopTwinGoesToTheEndWhenTheOtherSlotIsTaken() {
        var d = V6.document(names: [DesktopName(id: "X", name: "Taken", space: nil)],
                            plans: DesktopPlans(docked: ["builtin": ["", "X"]]))
        #expect(set(&d, "Notes", screen: "builtin", desktop: 2, mode: .undocked))
        let id = d.names.first { $0.name == "Notes" }!.id
        #expect(d.plans.entries(.docked, "builtin") == ["", "X", id])
    }

    @Test func reusingAGhostNameAbsorbsItsPinsAndId() {
        var d = V6.document(rules: [])
        let pinRule = rule("r1", docked: V6.at("external", 4))
        d.ghostDesktops = [GhostDesktop(
            screen: "external", name: "Old", desktop: 4, deletedAt: V6.incident,
            pins: [.init(profileID: d.activeProfileID, mode: .docked, rule: pinRule,
                         destination: V6.at("external", 4, name: "OLD"))],
            nameID: "OLD", cause: GhostDesktop.deletedCause)]
        #expect(set(&d, " old ", screen: "external", desktop: 3, mode: .docked))
        #expect(d.names.map(\.id) == ["OLD"])
        #expect(d.ghostDesktops.isEmpty)
        let restored = d.rule("r1")?.docked
        #expect(restored?.nameID == "OLD" && restored?.desktop == 3)
    }

    // MARK: - Adı kaldırma / yerleşmemiş adı silme / satır silme

    @Test func removeNameKeepsRowPositionsInPlans() {
        var d = V6.document(names: [DesktopName(id: "A", name: "Alpha"), DesktopName(id: "B", name: "Beta")],
                            plans: DesktopPlans(docked: ["external": ["A", "B"]],
                                                undocked: ["builtin": ["B"]]))
        d.removeName("A")
        #expect(d.plans.entries(.docked, "external") == ["", "B"])
        d.removeName("missing") // sessizce geçer
        #expect(d.names.map(\.id) == ["B"])
    }

    @Test func deleteNameGhostsPinsCollapsesPlansAndReportsWhereItWas() {
        var d = V6.document(
            rules: [rule("p", docked: V6.at("external", 2, name: "W")),
                    rule("keep", docked: V6.e(1))],
            names: [DesktopName(id: "W", name: "Waiting", space: nil),
                    DesktopName(id: "Z", name: "Zed", space: nil)],
            plans: DesktopPlans(docked: ["external": ["", "W", "Z"]], undocked: ["builtin": ["W"]]))
        let ghost = d.deleteName("W", now: V6.incident)
        #expect(ghost?.screen == "external" && ghost?.desktop == 2 && ghost?.name == "Waiting")
        #expect(ghost?.pins.map(\.rule.id) == ["p"])
        #expect(d.plans.entries(.docked, "external") == ["", "Z"])
        #expect(d.plans.entries(.undocked, "builtin").isEmpty)
        #expect(d.rule("p") == nil && d.rule("keep") != nil)
        let again = d.deleteName("W")
        #expect(again == nil) // ikinci kez: iş yok
        #expect(d.ghostDesktops.count == 1)
        assertNoOrphanNamePins(d)
    }

    @Test func removePlanEntryForUnplacedNameDeletesTheName() {
        var d = V6.document(names: [DesktopName(id: "W", name: "Waiting", space: nil)],
                            plans: DesktopPlans(docked: ["external": ["W"]]))
        let ghost = d.removePlanEntry(screen: "external", desktop: 1, mode: .docked)
        #expect(ghost?.nameID == "W")
        #expect(d.names.isEmpty && d.plans.entries(.docked, "external").isEmpty)
    }

    @Test func removePlanEntryOfALiveBoundNameKeepsTheName() {
        var d = V6.document(names: [DesktopName(id: "N", name: "Nova", space: 20)],
                            plans: DesktopPlans(docked: ["external": ["", "N"]], undocked: ["builtin": ["N"]]))
        let ghost = d.removePlanEntry(screen: "external", desktop: 2, mode: .docked)
        #expect(ghost == nil)
        #expect(d.names.map(\.id) == ["N"])
        #expect(d.plans.entries(.docked, "external") == [""])
        #expect(d.plans.entries(.undocked, "builtin") == ["N"]) // öbür kurulumun görüşü kalır
    }

    @Test func removePlanEntryShiftsNumberPinsOfThatSetupOnly() {
        var d = V6.document(rules: [
            rule("on", docked: V6.e(2), undocked: V6.at("external", 2)),
            rule("later", docked: V6.e(3), undocked: V6.at("external", 3)),
            rule("namePin", docked: V6.at("external", 3, name: "N")),
        ], names: [DesktopName(id: "N", name: "Nova", space: 20)],
        plans: DesktopPlans(docked: ["external": ["", "", "N"]]))
        let ghost = d.removePlanEntry(screen: "external", desktop: 2, mode: .docked)
        #expect(ghost?.pins.map(\.rule.id) == ["on"])
        #expect(d.rule("on")?.undocked?.desktop == 2) // kural yaşıyor (öbür kurulum)
        #expect(d.rule("on")?.docked == nil)
        #expect(d.rule("later")?.docked?.desktop == 2)
        #expect(d.rule("later")?.undocked?.desktop == 3)
        #expect(d.rule("namePin")?.docked?.nameID == "N")
        #expect(d.plans.entries(.docked, "external") == ["", "N"])
    }

    @Test func removePlanEntryOutOfRangeIsHarmless() {
        var d = V6.document(rules: [rule("a", docked: V6.e(1))],
                            plans: DesktopPlans(docked: ["external": ["", ""]]))
        let before = d
        let far = d.removePlanEntry(screen: "external", desktop: 7, mode: .docked)
        #expect(far == nil)
        #expect(d == before)
    }

    /// Beklenen: geçersiz (0) satır numarası hiçbir pini bozmaz. Gerçek:
    /// `desktop > 0` olan her pin bir yukarı kayar ve 1. masaüstü pini 0 olur
    /// (DesktopNameEdits.swift:366, `destination.desktop -= 1` alt sınırsız).
    @Test func removePlanEntryWithZeroDesktopLeavesPinsAlone() {
        var d = V6.document(rules: [rule("a", docked: V6.e(1))])
        let ghost = d.removePlanEntry(screen: "external", desktop: 0, mode: .docked)
        #expect(ghost == nil)
        withKnownIssue("removePlanEntry(desktop: 0) shifts pins below 1") {
            #expect(d.rule("a")?.docked?.desktop == 1)
        }
    }

    // MARK: - Sıralama ve ekranlar arası taşıma

    @Test func moveDesktopRemapsNumberPinsButNotNamePins() {
        var d = V6.document(rules: [
            rule("a", docked: V6.e(1)), rule("b", docked: V6.e(2)), rule("c", docked: V6.e(3)),
            rule("n", docked: V6.at("external", 1, name: "N")),
            rule("other", docked: V6.b(1)),
        ], names: [DesktopName(id: "N", name: "Nova", space: 10)])
        d.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: .docked)
        #expect(d.rule("a")?.docked?.desktop == 3)
        #expect(d.rule("b")?.docked?.desktop == 1)
        #expect(d.rule("c")?.docked?.desktop == 2)
        #expect(d.rule("n")?.docked?.nameID == "N" && d.rule("n")?.docked?.desktop == 1) // önbellek sonra yenilenir
        #expect(d.rule("other")?.docked?.desktop == 1)
    }

    @Test func moveDesktopToSamePlaceOrInvalidIsNoOp() {
        var d = V6.document(rules: [rule("a", docked: V6.e(1))])
        let before = d
        d.moveDesktop(on: "external", from: 2, to: 2, count: 3, mode: .docked)
        d.moveDesktop(on: "external", from: 0, to: 2, count: 3, mode: .docked)
        d.moveDesktop(on: "external", from: 1, to: 0, count: 3, mode: .docked)
        #expect(d == before)
    }

    @Test func moveDesktopWithLiveSpacesCarriesNamesWithContentInEveryProfile() {
        let (built, _, otherID) = twoProfiles({ d in
            d.names = [DesktopName(id: "A", name: "Alpha", space: 10)]
            d.plans = DesktopPlans(docked: ["external": ["A", "", ""]])
        }, other: { d in
            d.names = [DesktopName(id: "A2", name: "Alpha", space: 10)]
            d.plans = DesktopPlans(docked: ["external": ["A2", "", ""]])
        })
        var d = built
        d.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: .docked,
                      liveSpaces: [10, 11, 12])
        // İçerik (space 10) üçüncü sıraya gitti: ad onunla gider, plan permüte olur.
        #expect(d.names.first?.space == 12)
        #expect(d.plans.entries(.docked, "external") == ["", "", "A"])
        let other = d.profiles.first { $0.id == otherID }!
        #expect(other.names.first?.space == 12)
        #expect(other.plans.entries(.docked, "external") == ["", "", "A2"])
    }

    @Test func moveDesktopWithoutLiveSpacesOnlyPermutesTheActivePlan() {
        let (built, _, otherID) = twoProfiles({ d in
            d.plans = DesktopPlans(docked: ["external": ["A", "", ""]])
            d.names = [DesktopName(id: "A", name: "Alpha")]
        }, other: { d in
            d.plans = DesktopPlans(docked: ["external": ["B", "", ""]])
            d.names = [DesktopName(id: "B", name: "Beta")]
        })
        var d = built
        d.moveDesktop(on: "external", from: 1, to: 2, count: 3, mode: .docked)
        #expect(d.plans.entries(.docked, "external") == ["", "A", ""])
        #expect(d.profiles.first { $0.id == otherID }?.plans.entries(.docked, "external") == ["B", "", ""])
    }

    @Test func sharedLaptopMoveShiftsBothSetupsInEveryProfile() {
        let (built, _, otherID) = twoProfiles({ d in
            d.rules = [rule("a", docked: V6.b(1), undocked: V6.b(1))]
        }, other: { d in
            d.rules = [rule("o", docked: V6.b(1), undocked: V6.b(1))]
        })
        var d = built
        d.moveDesktop(on: "builtin", from: 1, to: 2, count: 2, mode: .undocked, sharedLaptop: true)
        #expect(d.rule("a")?.docked?.desktop == 2 && d.rule("a")?.undocked?.desktop == 2)
        let other = d.profiles.first { $0.id == otherID }!
        #expect(other.rules.first?.docked?.desktop == 2 && other.rules.first?.undocked?.desktop == 2)
    }

    @Test func moveDesktopAcrossMovesPinsAndPlanEntries() {
        var d = V6.document(
            rules: [rule("m", docked: V6.at("external", 2)), rule("after", docked: V6.at("external", 3)),
                    rule("target", docked: V6.at("external-2", 1)), rule("ext1", docked: V6.e(1))],
            names: [DesktopName(id: "N", name: "Nova", space: nil)],
            plans: DesktopPlans(docked: ["external": ["", "N", ""], "external-2": ["", ""]]))
        d.moveDesktopAcross(from: "external", desktop: 2, to: "external-2", at: 1, toCount: 2, mode: .docked)
        #expect(d.rule("m")?.docked?.screen == "external-2" && d.rule("m")?.docked?.desktop == 1)
        #expect(d.rule("after")?.docked?.desktop == 2)
        #expect(d.rule("target")?.docked?.desktop == 2) // hedefte `to` ve sonrası +1
        #expect(d.rule("ext1")?.docked?.desktop == 1)
        #expect(d.plans.entries(.docked, "external") == ["", ""])
        #expect(d.plans.entries(.docked, "external-2") == ["N", "", ""])
    }

    @Test func moveDesktopAcrossGuardsAgainstSameScreenAndBadIndices() {
        var d = V6.document(rules: [rule("m", docked: V6.e(1))])
        let before = d
        d.moveDesktopAcross(from: "external", desktop: 1, to: "external", at: 1, toCount: 1, mode: .docked)
        d.moveDesktopAcross(from: "external", desktop: 0, to: "builtin", at: 1, toCount: 1, mode: .docked)
        d.moveDesktopAcross(from: "external", desktop: 1, to: "builtin", at: 0, toCount: 1, mode: .docked)
        #expect(d == before)
    }

    @Test func moveDesktopAcrossWithSpaceMapRebindsNamesInAllProfiles() {
        let (built, _, otherID) = twoProfiles({ d in
            d.names = [DesktopName(id: "A", name: "Alpha", space: 10)]
            d.plans = DesktopPlans(docked: ["external": ["A"]])
        }, other: { d in
            d.names = [DesktopName(id: "B", name: "Beta", space: 10)]
            d.plans = DesktopPlans(docked: ["external": ["B"]])
        })
        var d = built
        d.moveDesktopAcross(from: "external", desktop: 1, to: "builtin", at: 1, toCount: 1, mode: .docked,
                            spaceMap: [10: 77])
        #expect(d.names.first?.space == 77)
        #expect(d.profiles.first { $0.id == otherID }?.names.first?.space == 77)
        #expect(d.profiles.first { $0.id == otherID }?.plans.place(of: "B", mode: .docked)
                == Slot(screen: "builtin", desktop: 1))
        #expect(d.plans.place(of: "A", mode: .docked) == Slot(screen: "builtin", desktop: 1))
        #expect(d.plans.entries(.docked, "external").isEmpty)
    }

    @Test func desktopMappingIsAPermutation() {
        #expect(Document.desktopMapping(from: 1, to: 3, count: 4) == [2: 1, 3: 2, 1: 3, 4: 4])
        #expect(Document.desktopMapping(from: 3, to: 1, count: 4) == [3: 1, 1: 2, 2: 3, 4: 4])
        #expect(Document.desktopMapping(from: 2, to: 2, count: 4) == nil)
        #expect(Document.desktopMapping(from: 0, to: 2, count: 4) == nil)
        let beyond = Document.desktopMapping(from: 2, to: 6, count: 3)
        #expect(Set(beyond?.keys ?? [:].keys) == Set(1...6) && Set(beyond?.values ?? [:].values) == Set(1...6))
    }

    @Test func planDesktopOnlyGrowsThePlan() {
        var d = V6.document(plans: DesktopPlans(docked: ["external": ["A"]]))
        d.planDesktop(on: "external", mode: .docked, count: 3)
        #expect(d.plans.entries(.docked, "external") == ["A", "", ""])
        d.planDesktop(on: "external", mode: .docked, count: 2)
        #expect(d.plans.entries(.docked, "external") == ["A", "", ""])
        d.planDesktop(on: "builtin", mode: .undocked, count: 0)
        #expect(d.plans.entries(.undocked, "builtin").isEmpty)
    }

    // MARK: - Hayalet geri getirme

    private func namedGhostDocument() -> Document {
        var d = V6.document()
        let pid = d.activeProfileID
        d.ghostDesktops = [GhostDesktop(
            screen: "external", name: "Nova", desktop: 3, deletedAt: V6.incident,
            pins: [.init(profileID: pid, mode: .docked, rule: rule("p", docked: V6.at("external", 3, name: "NOVA")),
                         destination: V6.at("external", 3, name: "NOVA")),
                   .init(profileID: pid, mode: .undocked, rule: rule("p", undocked: V6.at("builtin", 2, name: "NOVA")),
                         destination: V6.at("builtin", 2, name: "NOVA"))],
            nameID: "NOVA", cause: GhostDesktop.deletedCause)]
        return d
    }

    @Test func restoringANamedGhostRebuildsNameWithOldIDAndNamePins() {
        var d = namedGhostDocument()
        let id = d.ghostDesktops[0].id
        d.restoreGhost(id, desktop: 2, space: 55, mode: .docked)
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.names == [DesktopName(id: "NOVA", name: "Nova", space: 55)])
        #expect(d.plans.entries(.docked, "external") == ["", "NOVA"])
        let rule = d.rule("p")
        #expect(rule?.docked?.nameID == "NOVA" && rule?.docked?.desktop == 2)
        #expect(rule?.undocked?.nameID == "NOVA")
        assertNoOrphanNamePins(d)
    }

    @Test func restoringAGhostWhoseNameNowExistsReusesTheLiveName() {
        var d = namedGhostDocument()
        d.names = [DesktopName(id: "LIVE", name: "nova", space: 9)]
        d.plans = DesktopPlans(docked: ["external": ["LIVE"]])
        d.restoreGhost(d.ghostDesktops[0].id, desktop: 5, space: 55, mode: .docked)
        #expect(d.names.map(\.id) == ["LIVE"])
        #expect(d.rule("p")?.docked?.nameID == "LIVE")
        #expect(d.rule("p")?.docked?.desktop == 1)
    }

    @Test func restoringAGhostIgnoresAlreadyBoundSpace() {
        var d = namedGhostDocument()
        d.names = [DesktopName(id: "OTHER", name: "Other", space: 55)]
        d.restoreGhost(d.ghostDesktops[0].id, desktop: 2, space: 55, mode: .docked)
        #expect(d.names.first { $0.id == "NOVA" }?.space == nil)
    }

    @Test func restoringAnUnnamedGhostReturnsOnlyThisSetupsPins() {
        var d = V6.document()
        let pid = d.activeProfileID
        d.ghostDesktops = [GhostDesktop(
            screen: "external", name: nil, desktop: 4, deletedAt: V6.incident,
            pins: [.init(profileID: pid, mode: .docked, rule: rule("p", docked: V6.e(4)), destination: V6.e(4)),
                   .init(profileID: pid, mode: .undocked, rule: rule("q", undocked: V6.at("external", 4)),
                         destination: V6.at("external", 4))],
            cause: GhostDesktop.deletedCause)]
        let id = d.ghostDesktops[0].id
        d.restoreGhost(id, desktop: 2, mode: .docked)
        #expect(d.rule("p")?.docked?.desktop == 2)
        #expect(d.rule("q") == nil)
        #expect(d.ghostDesktops.count == 1 && d.ghostDesktops[0].pins.map(\.mode) == [.undocked])
        // Öbür kurulumda geri getirince hayalet tamamen tüketilir.
        d.restoreGhost(id, desktop: 1, mode: .undocked)
        #expect(d.ghostDesktops.isEmpty && d.rule("q")?.undocked?.desktop == 1)
    }

    @Test func restoreNeverOverwritesAnExistingPlaceOrDuplicatesRules() {
        var d = V6.document(rules: [rule("p", docked: V6.at("external", 1))])
        let pid = d.activeProfileID
        d.ghostDesktops = [GhostDesktop(
            screen: "external", name: nil, desktop: 4, deletedAt: V6.incident,
            pins: [.init(profileID: pid, mode: .docked, rule: rule("p", docked: V6.at("external", 4)),
                         destination: V6.at("external", 4))],
            cause: GhostDesktop.deletedCause)]
        d.restoreGhost(d.ghostDesktops[0].id, desktop: 2, mode: .docked)
        #expect(d.rules.count == 1)
        #expect(d.rule("p")?.docked?.desktop == 1) // yeri olan kural ezilmedi
    }

    @Test func restoreAndDiscardUnknownGhostAreNoOps() {
        var d = namedGhostDocument()
        let before = d
        d.restoreGhost("nope", desktop: 1)
        d.discardGhost("nope")
        #expect(d == before)
        d.discardGhost(d.ghostDesktops[0].id)
        #expect(d.ghostDesktops.isEmpty && d.rules.isEmpty)
    }

    // MARK: - Planı kopyalama, R4, aramalar

    @Test func copyPlanReplacesLaptopPlanAndClearsMovedNamesElsewhere() {
        var d = V6.document(plans: DesktopPlans(
            docked: ["builtin": ["X"], "external": ["", "L", "K"]],
            undocked: ["builtin": ["", "L"]]))
        d.copyPlan(from: .undocked, to: .docked)
        #expect(d.plans.entries(.docked, "builtin") == ["", "L"])
        #expect(d.plans.entries(.docked, "external") == ["", "", "K"])
        #expect(d.plans.entries(.undocked, "builtin") == ["", "L"])
    }

    @Test func copyPlanGuards() {
        var d = V6.document(plans: DesktopPlans(docked: ["external": ["K"]]))
        let before = d
        d.copyPlan(from: .docked, to: .docked)
        d.copyPlan(from: .undocked, to: .docked) // iki laptop planı da boş
        #expect(d == before)
    }

    @Test func bindByPlanClaimsEachLiveSpaceOnceAndClearsStaleBindings() {
        var d = V6.document(
            names: [DesktopName(id: "A", name: "A", space: 999), DesktopName(id: "B", name: "B", space: nil),
                    DesktopName(id: "C", name: "C", space: 11)],
            plans: DesktopPlans(docked: ["external": ["A", "B", "C"]]))
        d.bindByPlan(live: LiveDesktops(mode: .docked, spaces: ["external": [10, 11]]))
        #expect(d.nameRecord("A")?.space == 10)   // eski bağ canlı değil: planın yerine
        #expect(d.nameRecord("B")?.space == nil)  // planında 2. sıra, o masaüstü C'nin
        #expect(d.nameRecord("C")?.space == 11)
    }

    @Test func bindByPlanAlsoWorksForInactiveProfiles() {
        let (built, _, otherID) = twoProfiles({ d in
            d.names = [DesktopName(id: "A", name: "A")]
            d.plans = DesktopPlans(docked: ["external": ["A"]])
        }, other: { d in
            d.names = [DesktopName(id: "B", name: "B", space: 888)]
            d.plans = DesktopPlans(docked: ["external": ["", "B"]])
        })
        var d = built
        d.bindByPlan(live: LiveDesktops(mode: .docked, spaces: ["external": [10, 11]]))
        #expect(d.nameRecord("A")?.space == 10)
        #expect(d.profiles.first { $0.id == otherID }?.names.first?.space == 11)
    }

    @Test func desktopNamesTableCoversPlanAndLiveRows() {
        let d = V6.document(names: [DesktopName(id: "A", name: "Alpha", space: 10),
                                    DesktopName(id: "B", name: "Beta", space: nil)],
                            plans: DesktopPlans(docked: ["external": ["A", "", "B"]]))
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 11], "builtin": [1]])
        let table = d.desktopNames(for: .docked, live: live)
        #expect(table == ["external": ["1": "Alpha", "3": "Beta"]])
        #expect(d.desktopNames(for: .undocked).isEmpty)
        // Canlı kurulumda adı olmayan satır planın "" girdisini gösterir (ad yok).
        #expect(d.desktopName(screen: "external", desktop: 2, mode: .docked, live: live) == nil)
        #expect(d.desktopName(screen: "external", desktop: 9, mode: .docked, live: live) == nil)
        #expect(d.desktopName(screen: "external", desktop: 0, mode: .docked) == nil)
        #expect(d.plannedDesktops(mode: .docked, screen: "external") == 3)
    }

    @Test func nameIDPrefersTheLiveSpaceOverStalePlanEntry() {
        let d = V6.document(names: [DesktopName(id: "A", name: "Alpha", space: 11)],
                            plans: DesktopPlans(docked: ["external": ["A", ""]]))
        let live = LiveDesktops(mode: .docked, spaces: ["external": [10, 11]])
        #expect(d.nameID(screen: "external", desktop: 1, mode: .docked, live: live) == nil)
        #expect(d.nameID(screen: "external", desktop: 2, mode: .docked, live: live) == "A")
        // Canlı kurulum başka moddaysa plan konuşur.
        #expect(d.nameID(screen: "external", desktop: 1, mode: .docked, live: LiveDesktops(mode: .undocked, spaces: [:])) == "A")
    }

    @Test func hasAnyDesktopNamesLooksAtInactiveProfilesToo() {
        let (built, _, _) = twoProfiles({ _ in }, other: { d in
            d.names = [DesktopName(id: "B", name: "Beta", space: 5)]
        })
        #expect(built.names.isEmpty && built.hasAnyDesktopNames)
        #expect(built.namedSpacesInAnyProfile == [5])
        #expect(!V6.document().hasAnyDesktopNames)
    }

    @Test func pendingRemovalsAreKeyedByModeAndScreen() {
        var d = V6.document()
        d.pendingRemovals[Document.planKey(mode: .undocked, screen: "builtin")] =
            [PendingRemoval(desktop: 2, space: 7), PendingRemoval(desktop: 3, space: nil)]
        #expect(d.pendingRemovals(mode: .undocked, screen: "builtin").map(\.desktop) == [2, 3])
        #expect(d.pendingRemovals(mode: .docked, screen: "builtin").isEmpty)
        d.dropFirstPendingRemoval(mode: .undocked, screen: "builtin")
        #expect(d.pendingRemovals(mode: .undocked, screen: "builtin").map(\.desktop) == [3])
        d.dropFirstPendingRemoval(mode: .undocked, screen: "builtin")
        #expect(d.pendingRemovals.isEmpty) // boşalan anahtar silinir
        d.dropFirstPendingRemoval(mode: .undocked, screen: "builtin") // boşta: sorun yok
        #expect(Document.splitNameKey("docked|external-2")?.screen == "external-2")
        #expect(Document.splitNameKey("garbage") == nil)
        #expect(Document.splitNameKey("sideways|x") == nil)
    }

    @Test func normalizedTargetDropsNameBindingWhenNothingBacksIt() {
        let d = V6.document(names: [DesktopName(id: "A", name: "Alpha", space: nil)],
                            plans: DesktopPlans(docked: ["external": ["A"]]))
        // Satır adlıysa ad kazanır.
        #expect(d.normalizedTarget(V6.at("external", 1), mode: .docked, live: nil).nameID == "A")
        // Adın bu kurulumda yeri yoksa (önbellek denetlenemez) bağ kalır.
        #expect(d.normalizedTarget(V6.at("external", 5, name: "A"), mode: .undocked, live: nil).nameID == "A")
        // Adın yeri var ama hedef başka satır: numara hedefi olur.
        #expect(d.normalizedTarget(V6.at("external", 5, name: "A"), mode: .docked, live: nil).nameID == nil)
        // Kayıtsız ad: numara hedefi.
        #expect(d.normalizedTarget(V6.at("external", 1, name: "GONE"), mode: .undocked, live: nil).nameID == nil)
    }

    @Test func ghostsOnScreenHideWhenNameIsLiveAgain() {
        var d = V6.document(names: [DesktopName(id: "A", name: "alpha", space: 1)])
        let pid = d.activeProfileID
        d.ghostDesktops = [
            GhostDesktop(screen: "external", name: "Alpha", desktop: 1, deletedAt: V6.incident, cause: "deleted"),
            GhostDesktop(screen: "external", name: nil, desktop: 2, deletedAt: V6.incident,
                         pins: [.init(profileID: pid, mode: .undocked, rule: rule("u", undocked: V6.e(2)),
                                      destination: V6.e(2))], cause: "deleted"),
            GhostDesktop(screen: "builtin", name: "Other", desktop: 1, deletedAt: V6.incident, cause: "deleted"),
        ]
        #expect(d.ghosts(on: "external").count == 2)
        #expect(d.ghosts(on: "external", mode: .docked).isEmpty) // adlı canlı; adsızın docked pini yok
        #expect(d.ghosts(on: "external", mode: .undocked).count == 1)
        #expect(d.ghosts(on: "builtin", mode: .docked).map(\.name) == ["Other"])
    }

    @Test func mergedPinsDeduplicatesByProfileRuleAndMode() {
        func pin(_ profile: String, _ rule: String, _ mode: Mode, desktop: Int = 1) -> GhostDesktop.Pin {
            .init(profileID: profile, mode: mode, rule: Rule(id: rule, appName: "A", bundleID: "b", tokens: []),
                  destination: V6.e(desktop))
        }
        let merged = Document.mergedPins([pin("p", "r", .docked, desktop: 1)],
                                         [pin("p", "r", .docked, desktop: 9), pin("p", "r", .undocked),
                                          pin("q", "r", .docked)])
        #expect(merged.count == 3)
        #expect(merged.first?.destination.desktop == 1) // eski kayıt kazanır
    }
}
