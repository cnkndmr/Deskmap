import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Ana harici monitör hatası (Faz 1): işlem × durum tablosu
/// docs/bug-tables.md §A (her hücrede test adı). Bilinen (düzeltilmemiş)
/// hatalar `withKnownIssue` ile işaretli; gerçek pencere taşınmaz, ekranlar
/// ve masaüstüleri sahte.
///
/// Ortam (15.10 denemesinin günlüğünden, nötr adlarla): dahili ekran
/// (0, 0); geniş monitör "Wide" solda ve üstte (minX −1686); sanal ekran
/// "Virtual" dahilinin sağında (minX 1710). Sanal ekran denemede iki kez
/// kapanıp yeniden açıldı.
struct PrimaryExternalBugTests {

    private func n(_ id: String, _ space: UInt64?) -> DesktopName { DesktopName(id: id, name: id, space: space) }
    private func s(_ role: String, _ desktop: Int) -> Slot { Slot(screen: role, desktop: desktop) }

    /// Rol sırası (main): yalnız konum.
    private func order(_ displays: [(uuid: String, minX: CGFloat)]) -> [String] {
        displays.sorted { ScreenService.externalOrder(($0.minX, 0, $0.uuid), ($1.minX, 0, $1.uuid)) }
            .map(\.uuid)
    }

    /// Monitördeki üç adlı masaüstü (space 101–103), her birinde bir pencere;
    /// plan `external` rolünde. `externalSpaces`: şu an `external` rolünü
    /// alan ekranın masaüstüleri; `others`: öbür harici ekran.
    private func input(externalSpaces: [UInt64], others: [UInt64]?) -> PlanApply.Input {
        var live: [String: [UInt64]] = ["builtin": [1, 2], "external": externalSpaces]
        if let others { live["external-2"] = others }
        return PlanApply.Input(
            mode: .docked, live: live,
            contents: [101: [11], 102: [12], 103: [13], 201: []],
            names: [n("ALPHA", 101), n("BETA", 102), n("GAMMA", 103)],
            plans: ["external": ["ALPHA", "BETA", "GAMMA"]],
            compactBeyondPlan: true)
    }

    // MARK: - A1 · Sanal ekran takıldı (seçim yok)

    /// A1-a: sanal ekran monitörün sağında: monitör `external` kalır (doğru).
    @Test func virtualRightOfMonitorKeepsMonitorExternal() {
        #expect(order([("WIDE", -1686), ("VIRTUAL", 1710)]).first == "WIDE")
    }

    /// A1-b: sanal ekran monitörün soluna konursa `external` rolünü alır:
    /// monitörün bütün düzeni sanal ekrana taşınır (K2: rol konumdan).
    @Test func virtualLeftOfMonitorStealsExternalRole() {
        withKnownIssue("Rol yalnız konumdan; hatırlanan ana monitör yok (main)") {
            #expect(order([("WIDE", -1686), ("VIRTUAL", -3606)]).first == "WIDE")
        }
    }

    // MARK: - A2 · Doğru roller: plan sessiz

    @Test func correctRolesNeedNoWork() {
        let out = PlanApply.compute(input(externalSpaces: [101, 102, 103], others: [201]))
        #expect(out.isEmpty)
    }

    // MARK: - A3 · Rol yer değiştirdi (menü seçimi ya da konum)

    /// Menüde öbür monitör seçildi (ya da A1-b): `external` artık sanal
    /// ekranın tek masaüstü. Plan bütün adlı masaüstülerin pencerelerini oraya
    /// taşır ve sanal ekranda masaüstü açar. Kullanıcıya sorulmadan toplu
    /// taşıma: Faz 1 denemesinde görülen "çalışmıyor"un en olası nedeni.
    @Test func roleSwapMigratesWholeLayoutWithoutConsent() {
        let out = PlanApply.compute(input(externalSpaces: [201], others: [101, 102, 103]))
        withKnownIssue("Rol değişimi onaysız toplu taşıma başlatıyor") {
            #expect(out.moves.isEmpty)
            #expect(out.creates.isEmpty)
        }
    }

    // MARK: - A4 · Ana monitör çıktı, yalnız sanal ekran kaldı

    /// Tek harici ekran her zaman `external`: monitör çıkınca sanal ekran
    /// monitörün planını alır (main'de ve Faz 1'de aynı).
    @Test func loneVirtualDisplayTakesMonitorPlan() {
        let out = PlanApply.compute(input(externalSpaces: [201], others: nil))
        withKnownIssue("Tek harici ekran, hangisi olursa olsun, monitör planını alıyor") {
            #expect(out.creates["external", default: 0] == 0)
            #expect(out.rebinds.isEmpty)
        }
    }
}
