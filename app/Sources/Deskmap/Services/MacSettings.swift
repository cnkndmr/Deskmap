import AppKit
import Foundation

/// Deskmap'in düzgün çalışması için gereken macOS ayarları. Dock ve
/// Spaces tercihleri `defaults` alanlarından okunur; anahtar yoksa
/// macOS'un varsayılanı kabul edilir.
///
/// Neden gerekli (3 Eylül 2026'da yaşandı): "Automatically rearrange
/// Spaces" açıkken Dock'tan başka masaüstündeki uygulamaya geçiş komşu
/// Space'e gidiyor, pencere belirip kayboluyor; Dock'ta "Assign To" atanmış
/// pencere Deskmap'in taşımasıyla çelişiyor.
enum MacSettings {

    struct Check: Identifiable, Equatable {
        let id: String
        /// Ayarın macOS arayüzündeki adı; Türkçe macOS'ta Sistem Ayarları'nın
        /// kendi Türkçe adıyla gösterilir (aranacak metin budur).
        let title: String
        /// Olması gereken durum ve nedeni.
        let detail: String
        let ok: Bool
        /// Zorunlu ayar yanlışsa Deskmap düzgün çalışmaz; önerilen ayar
        /// (`required == false`) yalnızca sarı ipucu olarak gösterilir.
        var required: Bool = true
    }

    /// Kartın "ayarlar uygun" kararı (saf): yalnız zorunlu ayarlara bakılır.
    /// Önerilen ayar kapalı olsa da kart kapatılabilir.
    static func allRequiredOK(_ checks: [Check]) -> Bool {
        checks.allSatisfy { $0.ok || !$0.required }
    }

    /// Canlı denetlenebilen ayarlar; zorunluların hepsi `ok` ise kart
    /// yalnızca genel hatırlatmayı gösterir.
    static func checks() -> [Check] {
        let mruSpaces = bool("mru-spaces", domain: "com.apple.dock", default: true)
        let autoSwoosh = bool("workspaces-auto-swoosh", domain: "com.apple.dock", default: true)
        let groupApps = bool("expose-group-apps", domain: "com.apple.dock", default: false)
        let spansDisplays = bool("spans-displays", domain: "com.apple.spaces", default: false)
        return [
            Check(id: "mru",
                  title: L("Automatically rearrange Spaces based on most recent use"),
                  detail: L("Must be OFF. When on, macOS reorders your desktops: switching to an app from the Dock goes to the wrong Space and pin desktop numbers shift."),
                  ok: !mruSpaces),
            Check(id: "swoosh",
                  title: L("When switching to an application, switch to a Space with open windows"),
                  detail: L("Must be ON. When off, clicking an app in the Dock does not switch desktops."),
                  ok: autoSwoosh),
            Check(id: "group",
                  title: L("Group windows by application"),
                  detail: L("OFF is recommended. When on, the Mission Control order may not match desktop numbers."),
                  ok: !groupApps, required: false),
            Check(id: "spans",
                  title: L("Displays have separate Spaces"),
                  detail: L("Must be ON. When off, Deskmap cannot see the external display's desktops."),
                  ok: !spansDisplays),
        ]
    }

    /// Canlı denetlenemeyen, kurulumda bir kez okunması gereken uyarılar.
    static let reminders: [String] = [
        L("For apps you pin, right-click the Dock icon › Options › Assign To must be \"None\". With \"This Desktop\" or \"All Desktops\", macOS pulls the window to the Space it assigned, which conflicts with Deskmap's moves."),
        L("Settings: System Settings › Desktop & Dock › Mission Control section."),
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
