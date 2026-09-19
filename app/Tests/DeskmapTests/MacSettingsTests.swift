import Foundation
import Testing
@testable import Deskmap

/// macOS ayarları kartı: "ayarlar uygun" kararı yalnız zorunlu ayarlara bakar.
struct MacSettingsTests {

    private func check(_ id: String, ok: Bool, required: Bool = true) -> MacSettings.Check {
        MacSettings.Check(id: id, title: id, detail: "", ok: ok, required: required)
    }

    @Test func allRequiredOKIgnoresRecommendedSetting() {
        let checks = [check("mru", ok: true), check("group", ok: false, required: false)]
        #expect(MacSettings.allRequiredOK(checks))
    }

    @Test func anyRequiredFailureMakesCardNeedFixing() {
        let checks = [check("mru", ok: false), check("group", ok: true, required: false)]
        #expect(!MacSettings.allRequiredOK(checks))
    }

    @Test func emptyAndAllOKAreOK() {
        #expect(MacSettings.allRequiredOK([]))
        #expect(MacSettings.allRequiredOK([check("a", ok: true), check("b", ok: true)]))
    }

    /// Yalnız "Pencereleri uygulamaya göre grupla" önerilen; diğerleri zorunlu.
    @Test func onlyGroupSettingIsRecommended() {
        let checks = MacSettings.checks()
        #expect(checks.map(\.id) == ["mru", "swoosh", "group", "spans"])
        #expect(checks.filter { !$0.required }.map(\.id) == ["group"])
    }

    /// Başlıklar `L()`'den geçer; Türkçe tabloda karşılıkları var.
    @Test func titlesAreLocalizedToTurkish() {
        for (key, turkish) in [
            ("Group windows by application", "Pencereleri uygulamaya göre grupla"),
            ("Displays have separate Spaces", "Ekranların ayrı Alanları var"),
            ("Recommended", "Önerilen"),
        ] {
            #expect(Self.turkish[key] == turkish)
        }
    }

    private static let turkish: [String: String] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/tr.lproj/Localizable.strings")
        guard let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String] else { return [:] }
        return table
    }()
}
