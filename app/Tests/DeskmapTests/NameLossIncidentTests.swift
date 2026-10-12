import Foundation
import Testing
@testable import Deskmap

/// 11.10 olayları (gerçek veriden kırpıldı): yalnız laptop, etkin kurulum
/// laptop (undocked); monitörlü kurulum aynı mantıksal masaüstlerini Dell'e
/// koyuyor ve 1032/1030/1357 kimliklerini laptop kurulumuyla paylaşıyor.
/// Olay 1: monitörlü planın laptop kartında boş görünen 7. satır üç kez
/// silindi (kuyruk 1031, 1030, 1357); laptop kurulumunun 7–9 adları pinleri
/// yerinde kalarak düştü. Olay 2: adlar CLI ile yeniden verilince tarama
/// öbür kurulumun kuyruğunu canlı listeden düşüp üçünü "silinmiş" saydı,
/// pinleri ve monitörlü kurulumdaki karşılıkları hayalete gitti.
struct NameLossIncidentTests {

    private let D = Mode.docked, U = Mode.undocked

    /// 02:26'daki canlı laptop sırası (10. masaüstü sonra silindi).
    private let liveBefore: [UInt64] = [5, 4, 6, 8, 421, 1032, 1031, 1030, 1357, 1436]
    /// 10. silinip yenisi (1508) eklendikten sonra.
    private let liveAfter: [UInt64] = [5, 4, 6, 8, 421, 1032, 1031, 1030, 1357, 1508]

    private func pin(_ app: String, docked: (String, Int)?, undocked: (String, Int)?) -> Rule {
        Rule(appName: app, bundleID: app.lowercased(), tokens: [],
             docked: docked.map { Destination(screen: $0.0, desktop: $0.1) },
             undocked: undocked.map { Destination(screen: $0.0, desktop: $0.1) })
    }

    /// İyi durum (02:26 yedeği), her adlı masaüstüne bir pin.
    private func goodState() -> Document {
        var d = Document()
        d.desktopNames = [
            "docked|builtin": ["4": "AI Setup", "5": "Nova Ek"],
            "docked|external": ["1": "Notes Hub", "2": "Nova Projesi",
                                "3": "Lumen Makale", "4": "Orion Projesi"],
            "undocked|builtin": ["4": "AI Setup", "5": "Notes Hub", "6": "Nova Projesi",
                                 "7": "Nova Ek", "8": "Lumen Makale", "9": "Orion Projesi"],
        ]
        d.desktopNameSpaces = [
            "docked|builtin": ["4": 8],
            "docked|external": ["1": 1045, "2": 1032, "3": 1030, "4": 1357],
            "undocked|builtin": ["4": 8, "5": 421, "6": 1032, "7": 1031, "8": 1030, "9": 1357],
        ]
        d.rules = [
            pin("AI", docked: ("builtin", 4), undocked: ("builtin", 4)),
            pin("Hub", docked: ("external", 1), undocked: ("builtin", 5)),
            pin("Nova", docked: ("external", 2), undocked: ("builtin", 6)),
            pin("Ek", docked: ("builtin", 5), undocked: ("builtin", 7)),
            pin("LUMEN", docked: ("external", 3), undocked: ("builtin", 8)),
            pin("Orion", docked: ("external", 4), undocked: ("builtin", 9)),
        ]
        return d
    }

    private func rule(_ d: Document, _ app: String) -> Rule? { d.rules.first { $0.appName == app } }

    /// Kuralların yerleri (kimlikler her `goodState()`'te yeni).
    private func pins(_ d: Document) -> [String] {
        d.rules.map { "\($0.appName) \($0.docked.map { "\($0.screen)/\($0.desktop)" } ?? "-") \($0.undocked.map { "\($0.screen)/\($0.desktop)" } ?? "-")" }
    }

    /// `Router.spaceForPendingRemoval` ile aynı: canlı listeden o kurulumun
    /// kuyruğu düşülür, `desktop`. sıradaki kimlik.
    private func spaceForPendingRemoval(_ d: Document, live: [UInt64], desktop: Int, mode: Mode) -> UInt64? {
        let gone = Set(d.pendingRemovals(mode: mode, screen: "builtin").compactMap(\.space))
        let remaining = live.filter { !gone.contains($0) }
        return desktop <= remaining.count ? remaining[desktop - 1] : nil
    }

    /// `Router.followDesktopNames`'in ad adımı (saf kısım): kuyruk ayrımı,
    /// mantıksal liste, canlı küme ve düşen adların hayalete çevrilmesi.
    @discardableResult
    private func followNames(_ d: inout Document, live: [UInt64], previous: [UInt64],
                             seen: Set<UInt64>, mode: Mode) -> ReconcileResult {
        let queue = Router.pendingQueue(d.pendingRemovals, mode: mode)
        let raw = Set(live)
        let logical = ["builtin": live.filter { !queue.active.contains($0) }]
        let result = d.reconcileNames(spaces: logical, seen: seen, mode: mode,
                                      previous: ["builtin": previous.filter { !queue.active.contains($0) }],
                                      live: raw)
        for group in result.ghostGroups {
            d.ghostDesktop(on: group.screen, desktop: group.desktop, modes: Mode.allCases,
                           name: group.active?.name, droppedSpace: group.space,
                           droppedMode: group.active?.place.mode, otherDropped: group.others,
                           live: raw)
        }
        return result
    }

    private func expectGoodNames(_ d: Document) {
        let good = goodState()
        #expect(d.desktopNames == good.desktopNames)
        #expect(d.desktopNameSpaces == good.desktopNameSpaces)
        #expect(d.ghostDesktops.isEmpty)
    }

    // MARK: Olay 1

    /// Haritadaki satırdan silme (Router.removeDesktop): ad ve pini olmayan
    /// 10. masaüstü; başka hiçbir ad ya da pin kımıldamaz.
    @Test func removingUnnamedLiveDesktopKeepsEveryName() {
        var d = goodState()
        let seen = Set(liveBefore)
        followNames(&d, live: liveBefore, previous: liveBefore, seen: [], mode: U)
        let ghost = d.ghostDesktop(on: "builtin", desktop: 10, modes: Mode.allCases,
                                   live: Set(liveBefore.dropLast()))
        #expect(ghost == nil)
        let removed = Array(liveBefore.dropLast())
        followNames(&d, live: removed, previous: removed, seen: seen, mode: U)
        followNames(&d, live: liveAfter, previous: removed, seen: seen, mode: U)
        expectGoodNames(d)
        #expect(pins(d) == pins(goodState()))
    }

    /// Asıl olay 1: monitörlü planın laptop kartında 7. satır üç kez silinir.
    /// Eskiden laptop adları "iki kurulumda" diye laptop kurulumunun 7–9 adları
    /// da kayıp düşüyordu, pinleri 7–9'da kalıyordu.
    @Test func queuedRemovalInOtherSetupDoesNotDropLiveSetupNames() {
        var d = goodState()
        for _ in 0..<3 {
            let space = spaceForPendingRemoval(d, live: liveBefore, desktop: 7, mode: D)
            d.removeDesktopLater(on: "builtin", desktop: 7, mode: D, existing: true, space: space)
        }
        #expect(d.pendingRemovals(mode: D, screen: "builtin").map(\.space) == [1031, 1030, 1357])
        #expect(d.desktopNames["undocked|builtin"] == goodState().desktopNames["undocked|builtin"])
        #expect(d.desktopNameSpaces["undocked|builtin"] == goodState().desktopNameSpaces["undocked|builtin"])
        #expect(rule(d, "Ek")?.undocked?.desktop == 7)
        #expect(rule(d, "Orion")?.undocked?.desktop == 9)
        // Tarama (laptop kurulumu etkin) monitörlü planın kuyruğu yüzünden adı düşürmez.
        let result = followNames(&d, live: liveBefore, previous: liveBefore,
                                 seen: Set(liveBefore), mode: U)
        #expect(result.dropped.isEmpty)
        #expect(d.desktopNames["undocked|builtin"] == goodState().desktopNames["undocked|builtin"])
        #expect(d.ghostDesktops.isEmpty)
    }

    /// Arayüz/CLI yolu (Store): öbür kurulumda ya da monitörde adlı gerçek
    /// masaüstü bu planın kuyruğuna alınmaz, bildirilir.
    @MainActor @Test func storeRefusesQueuingANamedDesktopOfAnotherPlace() {
        let store = Store(demo: goodState())
        let accepted = store.removeDesktopLater(on: "builtin", desktop: 7, mode: D,
                                                existing: true, space: 1031)
        #expect(!accepted)
        #expect(store.document.pendingRemovals.isEmpty)
        #expect(store.document.desktopNames == goodState().desktopNames)
        #expect(store.lastError?.contains("Nova Ek") == true)
        // Boş ve hiçbir yerde adı olmayan masaüstü sıraya alınabilir.
        #expect(store.removeDesktopLater(on: "builtin", desktop: 10, mode: D,
                                         existing: true, space: 1436))
        #expect(store.document.pendingRemovals(mode: D, screen: "builtin").map(\.space) == [1436])
    }

    @Test func pendingRemovalConflictIgnoresTheRowsOwnName() {
        let d = goodState()
        #expect(d.pendingRemovalConflict(on: "builtin", desktop: 7, mode: D, space: 1031) == "Nova Ek")
        // 1030 monitörlü kurulumda Dell'de adlı (Lumen Makale).
        #expect(d.pendingRemovalConflict(on: "builtin", desktop: 8, mode: D, space: 1030) == "Lumen Makale")
        // Satırın kendi adı aynı mantıksal masaüstü: engel değil.
        #expect(d.pendingRemovalConflict(on: "builtin", desktop: 4, mode: D, space: 8) == nil)
        #expect(d.pendingRemovalConflict(on: "builtin", desktop: 10, mode: D, space: 1436) == nil)
    }

    // MARK: Olay 2

    /// Olay 1 sonrası bozuk ara durum (kuyruk duruyor, 7–9 adları yok) +
    /// CLI `deskmap name --mode undocked builtin 7 Nova Ek` (8, 9 aynı).
    /// Eskiden tarama mantıksal listeden kuyruğu (öbür kurulumunkini de)
    /// düşüyordu: 1031/1030/1357 "görülmüş ve yok" sayıldı, üçü hayalete,
    /// 7–9 pinleri ve monitörlü kurulumdaki karşılıklar (Dell 3/4, laptop 5)
    /// da gitti.
    /// Olay 1 sonrası durum + üç CLI adlandırması.
    private func afterEvent1Renamed() -> Document {
        var d = goodState()
        d.desktopNames["undocked|builtin"] = ["4": "AI Setup", "5": "Notes Hub", "6": "Nova Projesi"]
        d.desktopNameSpaces["undocked|builtin"] = ["4": 8, "5": 421, "6": 1032]
        d.pendingRemovals = ["docked|builtin": [PendingRemoval(desktop: 7, space: 1031),
                                                PendingRemoval(desktop: 7, space: 1030),
                                                PendingRemoval(desktop: 7, space: 1357)]]
        for (desktop, name) in [(7, "Nova Ek"), (8, "Lumen Makale"), (9, "Orion Projesi")] {
            // URLCommands .nameDesktop: hedef etkin kurulum → canlı kimlik.
            let accepted = d.setDesktopName(name, screen: "builtin", desktop: desktop, mode: U,
                                            space: liveAfter[desktop - 1])
            #expect(accepted)
        }
        return d
    }

    /// Eski hesap (bütün kuyruklar düşülmüş liste, canlı küme yok) olay 2'yi
    /// birebir üretir: üç hayalet, 7–9 ve Dell 3/4, laptop 5 pinleri gider.
    @Test func oldComputationReproducesEvent2() {
        var d = afterEvent1Renamed()
        let seen = Set(liveBefore).union(liveAfter)
        let pending: Set<UInt64> = [1031, 1030, 1357]
        let logical = liveAfter.filter { !pending.contains($0) }
        let result = d.reconcileNames(spaces: ["builtin": logical], seen: seen, mode: U,
                                      previous: ["builtin": logical])
        #expect(Set(result.dropped.map(\.name)) == ["Nova Ek", "Lumen Makale", "Orion Projesi"])
        for drop in result.dropped.sorted(by: { $0.place.desktop > $1.place.desktop }) {
            d.ghostDesktop(on: drop.place.screen, desktop: drop.place.desktop, modes: Mode.allCases,
                           name: drop.name, droppedSpace: drop.place.space, droppedMode: drop.place.mode)
        }
        #expect(d.ghostDesktops.map(\.desktop) == [9, 8, 7])
        #expect(d.desktopNames["docked|external"] == ["1": "Notes Hub", "2": "Nova Projesi"])
        #expect(d.desktopNames["docked|builtin"] == ["4": "AI Setup"])
        #expect(d.rules.map(\.appName) == ["AI", "Hub", "Nova"])
    }

    @Test func namingLiveDesktopsWithOtherSetupQueueDoesNotGhostThem() {
        var d = afterEvent1Renamed()
        let seen = Set(liveBefore).union(liveAfter)
        let result = followNames(&d, live: liveAfter, previous: liveAfter, seen: seen, mode: U)
        #expect(result.dropped.isEmpty)
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.desktopNames == goodState().desktopNames)
        #expect(d.desktopNameSpaces == goodState().desktopNameSpaces)
        #expect(pins(d) == pins(goodState()))
    }

    /// Canlı kimliğe bağlı ad mantıksal listede olmasa da (eski hesap: bütün
    /// kuyruklar düşülmüş liste) silinmiş sayılmaz.
    @Test func reconcileNeverDropsANameBoundToALiveSpace() {
        var d = goodState()
        let logical = liveAfter.filter { ![1031, 1030, 1357].contains($0) }
        let result = d.reconcileNames(spaces: ["builtin": logical], seen: Set(liveAfter), mode: U,
                                      previous: ["builtin": logical], live: Set(liveAfter))
        #expect(result.dropped.isEmpty)
        // Gerçekten silinen (görülmüş, hiçbir listede yok) yine düşer.
        var gone = goodState()
        let without = liveAfter.filter { $0 != 1357 }
        let removed = gone.reconcileNames(spaces: ["builtin": without], seen: Set(liveAfter), mode: U,
                                          previous: ["builtin": liveAfter], live: Set(without))
        #expect(removed.dropped.map(\.name) == ["Orion Projesi"])
    }

    /// Düşen adın öbür kurulumdaki karşılığı başka bir canlı masaüstüne
    /// bağlıysa (yalnız ad eşleşiyor) hayalete katılmaz.
    @Test func ghostSkipsCounterpartBoundToAnotherLiveSpace() {
        var d = goodState()
        d.desktopNameSpaces["docked|external"]?["4"] = 2000
        d.desktopNames["undocked|builtin"]?["9"] = nil
        d.desktopNameSpaces["undocked|builtin"]?["9"] = nil
        d.ghostDesktop(on: "builtin", desktop: 9, modes: Mode.allCases, name: "Orion Projesi",
                       droppedSpace: 1357, droppedMode: U, live: Set(liveAfter).union([2000]).subtracting([1357]))
        #expect(d.desktopName(screen: "external", desktop: 4, mode: D) == "Orion Projesi")
        #expect(rule(d, "Orion")?.docked == Destination(screen: "external", desktop: 4))
        #expect(rule(d, "Orion")?.undocked == nil)
        // Aynı kimliğe bağlı karşılık (aynı fiziksel masaüstü) yine birlikte gider.
        var same = goodState()
        same.desktopNames["undocked|builtin"]?["9"] = nil
        same.desktopNameSpaces["undocked|builtin"]?["9"] = nil
        same.ghostDesktop(on: "builtin", desktop: 9, modes: Mode.allCases, name: "Orion Projesi",
                          droppedSpace: 1357, droppedMode: U, live: Set(liveAfter).subtracting([1357]))
        #expect(same.desktopName(screen: "external", desktop: 4, mode: D) == nil)
        #expect(same.ghostDesktops.first?.pins.count == 2)
    }

    /// Mission Control'de silinen masaüstünün numarası etkin kurulumun
    /// sırasıyla sayılır: öbür kurulumun kuyruğu numarayı kaydırmaz.
    @Test func outsideRemovalNumbersIgnoreOtherSetupQueue() {
        let after = liveAfter.filter { $0 != 1357 }
        let numbers = Router.removedOutsideDeskmap(
            before: ["builtin": liveAfter], after: ["builtin": after],
            pending: [1031], numbering: [])
        #expect(numbers == ["builtin": [9]])
        // Etkin kurulumun kendi kuyruğu düşülür (pinleri zaten kaymış).
        #expect(Router.removedOutsideDeskmap(
            before: ["builtin": liveAfter], after: ["builtin": after],
            pending: [1031], numbering: [1031]) == ["builtin": [8]])
    }

    @Test func pendingQueueSplitsActiveSetup() {
        let queue = Router.pendingQueue(
            ["docked|builtin": [PendingRemoval(desktop: 7, space: 1031)],
             "undocked|builtin": [PendingRemoval(desktop: 3, space: 6),
                                  PendingRemoval(desktop: 4, space: nil)]], mode: U)
        #expect(queue.all == [1031, 6])
        #expect(queue.active == [6])
        #expect(queue.unresolved == ["builtin"])
    }

    // MARK: Profil başına adlar (şema 5)

    /// Olay 1 ve 2'nin korumaları her profilde geçerli: etkin olmayan bir
    /// profil aynı adları taşıyorsa öbür kurulumun kuyruğu onun adlarını da
    /// düşürmez, hayalet açmaz.
    @Test func otherSetupQueueKeepsNamesInEveryProfile() throws {
        var d = goodState()
        d.syncActiveProfile()
        let duplicated = d.duplicateProfile(d.activeProfileID, named: "Copy")
        let copy = try #require(duplicated)
        for _ in 0..<3 {
            let space = spaceForPendingRemoval(d, live: liveBefore, desktop: 7, mode: D)
            d.removeDesktopLater(on: "builtin", desktop: 7, mode: D, existing: true, space: space)
        }
        let result = followNames(&d, live: liveBefore, previous: liveBefore,
                                 seen: Set(liveBefore), mode: U)
        #expect(result.ghostGroups.isEmpty)
        #expect(d.desktopNames["undocked|builtin"] == goodState().desktopNames["undocked|builtin"])
        let other = try #require(d.profiles.first { $0.id == copy.id })
        #expect(other.desktopNames == goodState().desktopNames)
        #expect(other.desktopNameSpaces == goodState().desktopNameSpaces)
        #expect(other.ghostDesktops.isEmpty)
    }

    /// Gerçekten silinen adlı masaüstü (Mission Control) her profilde kendi
    /// hayaletini açar; pinler profil başına bir kez kayar.
    @Test func realDeletionGhostsInEveryProfileOnce() throws {
        var d = goodState()
        d.syncActiveProfile()
        let duplicated = d.duplicateProfile(d.activeProfileID, named: "Copy")
        let copy = try #require(duplicated)
        let without = liveAfter.filter { $0 != 1357 }
        followNames(&d, live: liveAfter, previous: liveAfter, seen: [], mode: U)
        let result = followNames(&d, live: without, previous: liveAfter,
                                 seen: Set(liveAfter), mode: U)
        #expect(result.ghostGroups.count == 1)
        #expect(d.ghostDesktops.map(\.name) == ["Orion Projesi"])
        let other = try #require(d.profiles.first { $0.id == copy.id })
        #expect(other.ghostDesktops.map(\.name) == ["Orion Projesi"])
        #expect(other.ghostDesktops.first?.pins.allSatisfy { $0.profileID == copy.id } == true)
        #expect(other.rules.first { $0.appName == "Orion" }?.undocked == nil)
        #expect(other.rules.first { $0.appName == "LUMEN" }?.undocked?.desktop == 8)
    }
}
