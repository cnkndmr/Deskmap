import AppKit
import Foundation

/// Space Router'ın düzgün çalışması için gereken macOS ayarları. Dock ve
/// Spaces tercihleri `defaults` alanlarından okunur; anahtar yoksa
/// macOS'un varsayılanı kabul edilir.
///
/// Neden gerekli (3 Eylül 2026'da yaşandı): "Automatically rearrange
/// Spaces" açıkken Dock'tan başka masaüstündeki uygulamaya geçiş komşu
/// Space'e gidiyor, pencere belirip kayboluyor; Dock'ta "Assign To" atanmış
/// pencere Space Router'ın taşımasıyla çelişiyor.
enum MacSettings {

    struct Check: Identifiable, Equatable {
        let id: String
        /// Ayarın macOS (İngilizce) arayüzündeki adı.
        let title: String
        /// Olması gereken durum ve nedeni.
        let detail: String
        let ok: Bool
    }

    /// Canlı denetlenebilen ayarlar; hepsi `ok` ise kart yalnızca genel
    /// hatırlatmayı gösterir.
    static func checks() -> [Check] {
        let mruSpaces = bool("mru-spaces", domain: "com.apple.dock", default: true)
        let autoSwoosh = bool("workspaces-auto-swoosh", domain: "com.apple.dock", default: true)
        let groupApps = bool("expose-group-apps", domain: "com.apple.dock", default: false)
        let spansDisplays = bool("spans-displays", domain: "com.apple.spaces", default: false)
        return [
            Check(id: "mru",
                  title: "Automatically rearrange Spaces based on most recent use",
                  detail: "KAPALI olmalı. Açıkken macOS masaüstü sırasını değiştirir; Dock'tan "
                        + "uygulamaya geçiş yanlış Space'e gider, pinlerin masaüstü numaraları kayar.",
                  ok: !mruSpaces),
            Check(id: "swoosh",
                  title: "When switching to an application, switch to a Space with open windows",
                  detail: "AÇIK olmalı. Kapalıyken Dock'a tıklamak masaüstü değiştirmez.",
                  ok: autoSwoosh),
            Check(id: "group",
                  title: "Group windows by application",
                  detail: "KAPALI önerilir; açıkken Mission Control sırası ile masaüstü numaraları "
                        + "uyuşmayabilir.",
                  ok: !groupApps),
            Check(id: "spans",
                  title: "Displays have separate Spaces",
                  detail: "AÇIK olmalı. Kapalıyken Space Router harici ekranın masaüstlerini göremez.",
                  ok: !spansDisplays),
        ]
    }

    /// Canlı denetlenemeyen, kurulumda bir kez okunması gereken uyarılar.
    static let reminders: [String] = [
        "Pinlediğin uygulamaların Dock simgesinde sağ tık › Options › Assign To "
            + "\"None\" olmalı. \"This Desktop\" / \"All Desktops\" seçiliyse macOS pencereyi "
            + "kendi atadığı Space'e çeker; Space Router'ın taşımasıyla çelişir.",
        "Ayarlar: System Settings › Desktop & Dock › Mission Control bölümü.",
    ]

    static func openDesktopAndDock() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    private static func bool(_ key: String, domain: String, default fallback: Bool) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        else { return fallback }
        if let number = value as? NSNumber { return number.boolValue }
        return fallback
    }
}
