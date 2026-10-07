import Foundation
import Testing
@testable import Deskmap

/// `Document` üzerindeki kural ve profil işlemleri (Store bunları çağırır).
struct DocumentOperationsTests {

    private let external2 = Destination(screen: "external", desktop: 2, layout: .leftHalf)
    private let builtin1 = Destination(screen: "builtin", desktop: 1)

    private func rule(_ id: String, tokens: [String] = ["A"],
                      docked: Destination? = nil, undocked: Destination? = nil) -> Rule {
        Rule(id: id, appName: "Code", bundleID: "com.microsoft.VSCode", tokens: tokens,
             docked: docked, undocked: undocked)
    }

    // MARK: Düzen kopyalama

    /// Sadece laptop kurulumu monitör bağlı kurulumun üzerine yazılır:
    /// ortak kuralın hedefi kopyalanır, yalnızca laptopta olmayanın monitör
    /// hedefi kalkar, yalnızca monitörde olan kural silinir.
    @Test func copyLayoutReplacesTargetMode() {
        var doc = Document()
        doc.rules = [
            rule("both", tokens: ["A"], docked: external2, undocked: builtin1),
            rule("laptop", tokens: ["B"], undocked: Destination(screen: "builtin", desktop: 3)),
            rule("monitor", tokens: ["C"], docked: external2),
        ]
        let changed = doc.copyLayout(from: .undocked, to: .docked)
        #expect(changed)
        #expect(doc.rules.map(\.id) == ["both", "laptop"])
        #expect(doc.rule("both")?.docked == builtin1)
        #expect(doc.rule("both")?.undocked == builtin1)
        #expect(doc.rule("laptop")?.docked == Destination(screen: "builtin", desktop: 3))
        // Kopya zaten aynıysa belge değişmez.
        let again = doc.copyLayout(from: .undocked, to: .docked)
        #expect(!again)
    }

    // MARK: Düzen kaydetme

    /// "Şu anki boyutu kullan": yalnızca düzen değişir, ekran ve masaüstü
    /// olduğu gibi kalır; diğer modun hedefine dokunulmaz.
    @Test func setLayoutKeepsScreenAndDesktop() {
        var doc = Document()
        doc.rules = [rule("r", docked: external2, undocked: builtin1)]
        let layout = WindowLayout(x: 0.1, y: 0.2, w: 0.6, h: 0.7)
        let changed = doc.setLayout(layout, for: "r", mode: .docked)
        #expect(changed)
        let docked = doc.rule("r")?.docked
        #expect(docked?.screen == "external")
        #expect(docked?.desktop == 2)
        #expect(docked?.layout == layout)
        #expect(doc.rule("r")?.undocked == builtin1)
        #expect(doc.rules.count == 1)
    }

    /// Kural yoksa, bu modda hedef yoksa ya da düzen zaten aynıysa belge
    /// değişmez ve false döner (Store bu durumda geri alma kaydı bırakmaz).
    @Test func setLayoutIsNoOpWithoutTargetOrChange() {
        var doc = Document()
        doc.rules = [rule("r", docked: external2)]
        let before = doc
        let unknownRule = doc.setLayout(.center, for: "yok", mode: .docked)
        let noTarget = doc.setLayout(.center, for: "r", mode: .undocked)
        let sameLayout = doc.setLayout(.leftHalf, for: "r", mode: .docked)
        #expect(!unknownRule && !noTarget && !sameLayout)
        #expect(doc == before)
        #expect(doc.rule("r")?.undocked == nil)
    }

    // MARK: Masaüstü haritası

    @Test func desktopMappingCases() {
        // 1 → 3 (3 satır): 2→1, 3→2, 1→3
        #expect(Document.desktopMapping(from: 1, to: 3, count: 3) == [1: 3, 2: 1, 3: 2])
        // 3 → 1: 1→2, 2→3, 3→1
        #expect(Document.desktopMapping(from: 3, to: 1, count: 3) == [1: 2, 2: 3, 3: 1])
        // Komşu takas.
        #expect(Document.desktopMapping(from: 2, to: 3, count: 4) == [1: 1, 2: 3, 3: 2, 4: 4])
        // Hedef listeden büyükse toplam genişler.
        #expect(Document.desktopMapping(from: 1, to: 4, count: 2) == [1: 4, 2: 1, 3: 2, 4: 3])
        // Geçersiz taşımalar.
        #expect(Document.desktopMapping(from: 2, to: 2, count: 3) == nil)
        #expect(Document.desktopMapping(from: 0, to: 1, count: 3) == nil)
        #expect(Document.desktopMapping(from: 1, to: 0, count: 3) == nil)
    }

    /// Geri alma masaüstü taşımasını ters taşımayla (to → from, aynı satır
    /// sayısı) geri getirir; Store belgeyi yükler, Router oturum pinlerini
    /// bu ters haritayla kaydırır. İki harita art arda birim olmalı.
    @Test func desktopMappingInverseRestoresIdentity() {
        for count in 1...5 {
            for from in 1...count {
                for to in 1...(count + 2) where to != from {
                    let forward = Document.desktopMapping(from: from, to: to, count: count)
                    let inverse = Document.desktopMapping(from: to, to: from, count: count)
                    #expect(forward != nil && inverse != nil)
                    guard let forward, let inverse else { continue }
                    #expect(Set(forward.keys) == Set(inverse.keys),
                            "\(from)→\(to), \(count) satır")
                    for (old, new) in forward {
                        #expect(inverse[new] == old, "\(from)→\(to), \(count) satır: \(old)")
                    }
                }
            }
        }
    }

    @Test func moveDesktopShiftsOnlyMatchingScreenAndMode() {
        var doc = Document()
        doc.rules = [
            rule("a", docked: Destination(screen: "external", desktop: 1)),
            rule("b", tokens: ["B"], docked: Destination(screen: "external", desktop: 3)),
            rule("c", tokens: ["C"], docked: Destination(screen: "builtin", desktop: 1),
                 undocked: Destination(screen: "external", desktop: 1)),
        ]
        doc.moveDesktop(on: "external", from: 1, to: 3, count: 3, mode: .docked)
        #expect(doc.rules[0].docked?.desktop == 3)
        #expect(doc.rules[1].docked?.desktop == 2)
        #expect(doc.rules[2].docked?.desktop == 1)     // başka ekran
        #expect(doc.rules[2].undocked?.desktop == 1)   // başka mod
    }

    @Test func desktopsToAddAcrossMakesRoomForDisplacedDesktops() {
        // Plan 3, gerçek 2, konum 1: gerçek 2 → 3'e kayacağı için bir masaüstü gerekir.
        #expect(Document.desktopsToAddAcross(real: 2, at: 1) == 1)
        #expect(Document.desktopsToAddAcross(real: 2, at: 2) == 1)
        #expect(Document.desktopsToAddAcross(real: 2, at: 3) == 1)
        #expect(Document.desktopsToAddAcross(real: 2, at: 4) == 2)
        #expect(Document.desktopsToAddAcross(real: 0, at: 1) == 0)
    }

    @Test func acrossPlacementCases() {
        func at(_ screen: String, _ desktop: Int) -> String? {
            Document.acrossPlacement(screen: screen, desktop: desktop,
                                     from: "builtin", desktop: 2, to: "external", at: 1)
                .map { "\($0.screen)/\($0.desktop)" }
        }
        #expect(at("builtin", 1) == nil)
        #expect(at("builtin", 2) == "external/1")
        #expect(at("builtin", 4) == "builtin/3")
        #expect(at("external", 1) == "external/2")
        #expect(at("external", 3) == "external/4")
        #expect(at("other", 2) == nil)
        // Aynı ekranda bu işlev hiçbir şey yapmaz.
        #expect(Document.acrossPlacement(screen: "builtin", desktop: 2, from: "builtin",
                                         desktop: 2, to: "builtin", at: 1) == nil)
        // Sona ekleme: hedefte kimse kaymaz.
        #expect(Document.acrossPlacement(screen: "external", desktop: 3, from: "builtin",
                                         desktop: 1, to: "external", at: 4) == nil)
    }

    @Test func moveDesktopAcrossRemapsBothScreensAndPlans() {
        var doc = Document()
        doc.rules = [
            rule("a", docked: Destination(screen: "builtin", desktop: 2)),
            rule("b", tokens: ["B"], docked: Destination(screen: "builtin", desktop: 3),
                 undocked: Destination(screen: "builtin", desktop: 3)),
            rule("c", tokens: ["C"], docked: Destination(screen: "external", desktop: 1)),
            rule("d", tokens: ["D"], docked: Destination(screen: "builtin", desktop: 1)),
        ]
        doc.setPlannedDesktops(3, mode: .docked, screen: "builtin")
        let before = doc
        doc.moveDesktopAcross(from: "builtin", desktop: 2, to: "external", at: 1,
                              toCount: 2, mode: .docked)
        #expect(doc.rules[0].docked == Destination(screen: "external", desktop: 1))
        #expect(doc.rules[1].docked == Destination(screen: "builtin", desktop: 2))
        #expect(doc.rules[1].undocked == Destination(screen: "builtin", desktop: 3)) // başka mod
        #expect(doc.rules[2].docked == Destination(screen: "external", desktop: 2))
        #expect(doc.rules[3].docked == Destination(screen: "builtin", desktop: 1))
        #expect(doc.plannedDesktops(mode: .docked, screen: "builtin") == 2)
        #expect(doc.plannedDesktops(mode: .docked, screen: "external") == 3)
        // Ters taşıma pinleri geri getirir.
        doc.moveDesktopAcross(from: "external", desktop: 1, to: "builtin", at: 2,
                              toCount: 2, mode: .docked)
        #expect(doc.rules == before.rules)
    }

    @Test func moveDesktopAcrossRemapsInactiveProfiles() {
        var doc = Document()
        var other = Profile(name: "Diğer")
        other.rules = [rule("x", docked: Destination(screen: "builtin", desktop: 1))]
        doc.profiles.append(other)
        doc.moveDesktopAcross(from: "builtin", desktop: 1, to: "external", at: 3,
                              toCount: 2, mode: .docked)
        let moved = doc.profiles.first { $0.id == other.id }?.rules.first?.docked
        #expect(moved == Destination(screen: "external", desktop: 3))
    }

    // MARK: Adlar ve eşitleme

    @Test func uniqueNameAppendsCounter() {
        let taken = [Profile(name: "Ad"), Profile(name: "ad (2)"), Profile(name: "Başka")]
        #expect(Document.uniqueName("Yeni", in: taken) == "Yeni")
        #expect(Document.uniqueName("  Ad ", in: taken) == "Ad (3)")
        #expect(Document.uniqueName("başka", in: taken) == "başka (2)")
        #expect(Document.uniqueName("Ad", in: []) == "Ad")
    }

    @Test func syncActiveProfileWritesRulesOrRecreatesProfile() {
        var doc = Document()
        doc.rules = [rule("a")]
        doc.syncActiveProfile()
        #expect(doc.activeProfile?.rules == doc.rules)

        // Aktif profil kayıp: kurallar çakışmayan adla yeni profile yazılır.
        doc.activeProfileID = "gone"
        doc.syncActiveProfile()
        #expect(doc.profiles.count == 2)
        #expect(doc.profiles[1].name == "\(Document.defaultProfileName) (2)")
        #expect(doc.profiles[1].rules == doc.rules)
        #expect(doc.activeProfileID == doc.profiles[1].id)
    }

    // MARK: Pin / unpin

    @Test func pinUpdatesSameKeyRuleAndReturnsItsID() {
        var doc = Document()
        doc.rules = [rule("existing", tokens: ["Atlas"], undocked: builtin1)]
        let draft = Rule(appName: "Visual Studio Code", bundleID: "com.microsoft.VSCode",
                         tokens: ["atlas"])
        let id = doc.pin(draft, destination: external2, mode: .docked)
        #expect(id == "existing")
        #expect(doc.rules.count == 1)
        #expect(doc.rules[0].docked == external2)
        #expect(doc.rules[0].undocked == builtin1)
        // Yeni anahtar: yeni kural, yalnızca bu modda hedefli.
        let fresh = Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: [])
        let newID = doc.pin(fresh, destination: builtin1, mode: .undocked)
        #expect(newID == fresh.id)
        #expect(doc.rules.count == 2)
        #expect(doc.rules[1].undocked == builtin1)
        #expect(doc.rules[1].docked == nil)
    }

    @Test func unpinRemovesRuleOnlyWhenNoDestinationRemains() {
        var doc = Document()
        doc.rules = [rule("both", docked: external2, undocked: builtin1),
                     rule("one", tokens: ["B"], docked: external2)]
        doc.unpin("both", mode: .docked)
        #expect(doc.rules.count == 2)
        #expect(doc.rules[0].docked == nil)
        #expect(doc.rules[0].undocked == builtin1)
        doc.unpin("one", mode: .docked)
        #expect(doc.rules.map(\.id) == ["both"])
        doc.unpin("missing", mode: .docked)
        #expect(doc.rules.count == 1)
    }

    @Test func setDestinationOnlyTouchesGivenMode() {
        var doc = Document()
        doc.rules = [rule("r", docked: external2)]
        doc.setDestination(builtin1, for: "r", mode: .undocked)
        #expect(doc.rules[0].docked == external2)
        #expect(doc.rules[0].undocked == builtin1)
        doc.setDestination(nil, for: "r", mode: .docked)
        #expect(doc.rules[0].docked == nil)
        doc.setDestination(builtin1, for: "nope", mode: .docked)
        #expect(doc.rules.count == 1)
    }

    // MARK: Profiller

    @Test func switchProfileSyncsCurrentAndLoadsTarget() {
        var doc = Document()
        let first = doc.activeProfileID
        doc.rules = [rule("a")]
        doc.profiles.append(Profile(id: "p2", name: "İş", rules: [rule("b")]))

        doc.switchProfile(to: "p2")
        #expect(doc.activeProfileID == "p2")
        #expect(doc.rules.map(\.id) == ["b"])
        // Önceki profil son kurallarını aldı.
        #expect(doc.profiles.first { $0.id == first }?.rules.map(\.id) == ["a"])
        // Bilinmeyen kimlik ve aynı profil: değişiklik yok.
        let before = doc
        doc.switchProfile(to: "nope")
        doc.switchProfile(to: "p2")
        #expect(doc == before)
    }

    @Test func addProfileCopyingRegeneratesRuleIDs() {
        var doc = Document()
        doc.rules = [rule("a", docked: external2), rule("b", tokens: ["B"])]
        let empty = doc.addProfile()
        #expect(empty.name == "Profile 2")
        #expect(empty.rules.isEmpty)
        #expect(doc.activeProfileID == empty.id)
        #expect(doc.rules.isEmpty)

        doc.switchProfile(to: doc.profiles[0].id)
        let copy = doc.addProfile(named: Document.defaultProfileName, copyingCurrent: true)
        #expect(copy.name == "\(Document.defaultProfileName) (2)")
        #expect(copy.rules.count == 2)
        #expect(Set(copy.rules.map(\.id)).isDisjoint(with: ["a", "b"]))
        #expect(copy.rules[0].docked == external2)
        #expect(copy.rules.map(\.tokens) == [["A"], ["B"]])
        #expect(doc.rules == copy.rules)
        #expect(doc.profiles.count == 3)
    }

    @Test func deleteProfileKeepsLastAndSwitchesFromActive() {
        var doc = Document()
        let only = doc.activeProfileID
        doc.deleteProfile(only)
        #expect(doc.profiles.count == 1)

        doc.rules = [rule("a")]
        doc.profiles.append(Profile(id: "p2", name: "İş", rules: [rule("b")]))
        doc.switchProfile(to: "p2")
        doc.deleteProfile("p2")
        #expect(doc.profiles.map(\.id) == [only])
        #expect(doc.activeProfileID == only)
        #expect(doc.rules.map(\.id) == ["a"])

        // Aktif olmayanı silmek kuralları etkilemez.
        doc.profiles.append(Profile(id: "p3", name: "Üç"))
        doc.deleteProfile("p3")
        #expect(doc.rules.map(\.id) == ["a"])
        #expect(doc.activeProfileID == only)
    }

    @Test func renameProfileTrimsAndIgnoresEmpty() {
        var doc = Document()
        let id = doc.activeProfileID
        doc.renameProfile(id, to: "  Ev  ")
        #expect(doc.activeProfile?.name == "Ev")
        doc.renameProfile(id, to: "   ")
        #expect(doc.activeProfile?.name == "Ev")
        doc.renameProfile("nope", to: "X")
        #expect(doc.profiles.count == 1)
    }

    // MARK: Dışa / içe aktarma

    @Test func importRejectsForeignFileWithoutRules() {
        var doc = Document()
        let json = Data("{ \"kind\": \"something-else\", \"name\": \"X\" }".utf8)
        #expect(throws: (any Error).self) { try doc.importProfile(from: json) }
        #expect(throws: (any Error).self) { try doc.importProfile(from: Data("not json".utf8)) }
        #expect(doc.profiles.count == 1)
    }

    /// Eski ad döneminde dışa aktarılmış `.spacerouter.json` dosyaları
    /// (`kind: "spacerouter-profile"`), kuralları boş olsa bile kabul edilir.
    @Test func importAcceptsLegacySpaceRouterKindEvenWithoutRules() throws {
        var doc = Document()
        let json = Data("""
        { "kind": "spacerouter-profile", "name": "Eski", "rules": [] }
        """.utf8)
        let profile = try doc.importProfile(from: json)
        #expect(profile.name == "Eski")
        #expect(profile.rules.isEmpty)
        #expect(doc.activeProfileID == profile.id)
    }

    @Test func importAcceptsPlainRulesFileAndMergesScreens() throws {
        var doc = Document()
        doc.screens = [KnownScreen(id: "builtin", name: "Dahili", aspect: 1.55)]
        doc.rules = [rule("a")]
        let json = Data("""
        { "rules": [ { "id": "a", "appName": "Code", "bundleID": "c", "tokens": ["X"],
                       "docked": { "screen": "external-2", "desktop": 2 } },
                     { "id": "bad", "appName": "B", "docked": { "desktop": "x" } } ],
          "screens": [ { "id": "builtin", "name": "Başka ad", "aspect": 1.6 },
                       { "id": "external-2", "name": "Dell", "aspect": 1.78 } ] }
        """.utf8)
        let profile = try doc.importProfile(from: json)
        #expect(profile.name == "Imported")
        #expect(profile.rules.count == 1)          // bozuk kural atlandı
        #expect(profile.rules[0].id != "a")        // kimlik yenilendi
        #expect(profile.rules[0].tokens == ["X"])
        #expect(doc.activeProfileID == profile.id)
        #expect(doc.rules == profile.rules)
        // Önceki profil kurallarını korudu; bilinen ekran ezilmedi, yeni eklendi.
        #expect(doc.profiles[0].rules.map(\.id) == ["a"])
        #expect(doc.screens.map(\.id) == ["builtin", "external-2"])
        #expect(doc.screens[0].name == "Dahili")
    }

    @Test func exportImportRoundTripUniquifiesName() throws {
        var doc = Document()
        doc.screens = [KnownScreen(id: "external", name: "LG", aspect: 1.78)]
        doc.rules = [rule("a", docked: external2), rule("b", tokens: ["B", "C"], undocked: builtin1)]
        let data = try doc.exportData(for: doc.activeProfileID)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"kind\" : \"deskmap-profile\""))
        #expect(text.contains("\"name\" : \"\(Document.defaultProfileName)\""))

        let imported = try doc.importProfile(from: data)
        #expect(imported.name == "\(Document.defaultProfileName) (2)")
        #expect(imported.rules.count == 2)
        #expect(imported.rules.map(\.tokens) == [["A"], ["B", "C"]])
        #expect(imported.rules[0].docked == external2)
        #expect(imported.rules[1].undocked == builtin1)
        #expect(Set(imported.rules.map(\.id)).isDisjoint(with: ["a", "b"]))
        #expect(doc.profiles.count == 2)
        #expect(doc.screens.count == 1)

        #expect(throws: (any Error).self) { try doc.exportData(for: "nope") }
    }
}
