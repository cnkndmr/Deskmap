import AppKit
import CoreGraphics
import Foundation

/// `deskmap://` URL şemasıyla gelen otomasyon komutları (Shortcuts
/// "Open URLs", Raycast, Hammerspoon `hs.urlevent`, terminalde `open`).
///
///     deskmap://reapply              pinli pencereleri şimdi yerleştir
///     deskmap://pause                yönlendirmeyi duraklat
///     deskmap://resume               yönlendirmeyi sürdür
///     deskmap://toggle               duraklat / sürdür
///     deskmap://profile/<ad>         adı verilen profile geç
///     deskmap://profile?name=<ad>    aynı; "/" içeren adlar için
///     deskmap://next-profile         sıradaki profile geç (döner)
///     deskmap://add-desktop/<ekran>  ekrana masaüstü ekle (builtin, external…)
///     deskmap://remove-desktop/<ekran>/<n>  ekranın n. masaüstünü sil
///     deskmap://reload               rules.json'u diskten yeniden oku
///     deskmap://status               status.json'u hemen yaz
///     deskmap://pin/<pencere>/<ekran>/<n>    pencereyi kapanana dek orada tut
///         [?layout=desktop-only]            yalnız masaüstü (konum/boyut serbest)
///     deskmap://pin/<pencere>?name=<ad>      pencereyi adlı masaüstüne bağla (ad
///                                    nereye giderse pencere de gider)
///     deskmap://quit                 Deskmap'i kapat (kanca testleri)
///     deskmap://unpin/<pencere>      oturum pinini kaldır
///     deskmap://move/<pencere>/<ekran>/<n>   pencereyi bir kez taşı
///     deskmap://free/<pencere>/<dakika|lock>  pinli pencereye serbest hareket izni
///     deskmap://free-end/<pencere>   serbest hareketi bitir (pin geri uygulanır)
///     deskmap://rule-add?json=<kural>        kural ekle (Rule JSON'u)
///     deskmap://rule-remove/<kimlik> kuralı sil
///     deskmap://profile-rename/<ad>?name=<yeni>   profilin adını değiştir
///     deskmap://profile-export?path=</mutlak/yol>[&name=<ad>]  profili dışa aktar
///     deskmap://desktop-move/<ekran>/<n>/<m>[?mode=]  n. masaüstünü m. sıraya taşı
///     deskmap://rule-save-layout/<kimlik>[?window=<pencere>]  pencerenin şu anki
///                                    boyut/konumunu kuralın yerleşimi yap
///     deskmap://profile-set?json=<profil>&activate=1  profili ada göre ekle/güncelle
///     deskmap://plan-desktops/<ekran>/<n>?mode=docked|undocked  ekranda n masaüstü olsun
///     deskmap://desktop-name/<ekran>/<n>?name=<ad>[&mode=]  masaüstüne ad ver (boş ad siler)
///     deskmap://screen-role/<monitör>/<rol>  bağlı monitörü (UUID ya da şu anki
///                                    rolü) bir harici role ver; gerekirse yer değiştirir
///     deskmap://screen-role-forget   hatırlanan monitör rollerini unut (konum sırası)
///     deskmap://screen-fallback/<on|off>  ikinci monitör yokken ilk harici monitör
///     deskmap://backup-now           otomatik yedeği şimdi çalıştır
///     deskmap://backup-restore/<kimlik>  yedeği geri yükle (önce şimdiki hâli
///                                    pre-restore katmanına yedekler; geri alınabilir)
///
/// Her komut `?req=<n>` alabilir: işlendikten sonra status.json `request: n`
/// ile yazılır (`deskmap` komut satırı aracı bununla bekler).
///
/// Ayrıştırma saf bir işlevdir (`parse`), ne Store'a ne de AppKit'e
/// dokunur; böylece tek başına test edilebilir. Çalıştırma `URLCommands`
/// içindedir.
enum URLCommand: Equatable {
    case reapply
    case pause
    case resume
    case toggle
    case profile(name: String)
    case nextProfile
    case addDesktop(screen: String)
    case removeDesktop(screen: String, desktop: Int)
    case reload
    case status
    case pin(window: CGWindowID, screen: String, desktop: Int, desktopOnly: Bool = false)
    case pinToName(window: CGWindowID, name: String, desktopOnly: Bool = false)
    case quit
    case unpin(window: CGWindowID)
    /// `duration` sn; `Router.freeMoveUntilLock` = ekran kilitlenene kadar.
    case freeMove(window: CGWindowID, duration: TimeInterval)
    case endFreeMove(window: CGWindowID)
    case move(window: CGWindowID, screen: String, desktop: Int)
    case addRule(Rule)
    case removeRule(id: String)
    case setProfile(Profile, activate: Bool)
    case planDesktops(screen: String, count: Int, mode: Mode?)
    case renameProfile(from: String, to: String)
    case exportProfile(name: String?, path: String)
    case moveDesktop(screen: String, from: Int, to: Int, mode: Mode?)
    case saveLayout(rule: String, window: CGWindowID?)
    case nameDesktop(screen: String, desktop: Int, name: String, mode: Mode? = nil)
    case screenRole(display: String, role: String)
    case forgetScreenRoles
    case screenFallback(Bool)
    case backupNow
    case restoreBackup(id: String)

    static let scheme = "deskmap"

    /// `url` geçerli bir komutsa onu döndürür; şema `deskmap` değilse, komut bilinmiyorsa ya da profil adı boşsa
    /// `nil`. Komut adı büyük/küçük harfe duyarsızdır; `deskmap:reapply`
    /// (host'suz) biçimi de kabul edilir.
    static func parse(_ url: URL) -> URLCommand? {
        guard let urlScheme = url.scheme?.lowercased(),
              urlScheme == scheme
        else { return nil }

        // `deskmap://profile/Ofis`: host "profile", yol ["Ofis"].
        // `deskmap:profile/Ofis`:   host yok, yol ["profile", "Ofis"].
        // `pathComponents` yüzde kodlamasını çözer.
        var parts = url.pathComponents.filter { $0 != "/" }
        // macOS 15 Foundation'ı `//`'suz (opak) URL'de `pathComponents`'i boş
        // döndürüyor; yolu URLComponents'ten al (o da kodlamayı çözer).
        if parts.isEmpty, url.host == nil,
           let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path {
            parts = path.split(separator: "/").map(String.init)
        }
        let command: String
        if let host = url.host, !host.isEmpty {
            command = host.lowercased()
        } else if !parts.isEmpty {
            command = parts.removeFirst().lowercased()
        } else {
            return nil
        }

        func windowTarget() -> (CGWindowID, String, Int)? {
            guard parts.count == 3, let window = CGWindowID(parts[0]),
                  let desktop = Int(parts[2]), desktop >= 1 else { return nil }
            return (window, parts[1].lowercased(), desktop)
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch command {
        case "reload":       return .reload
        case "status":       return .status
        case "backup-now":   return parts.isEmpty ? .backupNow : nil
        case "backup-restore":
            guard parts.count == 1, !parts[0].isEmpty else { return nil }
            return .restoreBackup(id: parts[0])
        case "quit":         return parts.isEmpty ? .quit : nil
        case "pin":
            let desktopOnly = query.first { $0.name == "layout" }?.value == "desktop-only"
            if parts.count == 1, let window = CGWindowID(parts[0]),
               let name = query.first(where: { $0.name == "name" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return .pinToName(window: window, name: name, desktopOnly: desktopOnly)
            }
            return windowTarget().map {
                .pin(window: $0.0, screen: $0.1, desktop: $0.2, desktopOnly: desktopOnly)
            }
        case "move":
            return windowTarget().map { .move(window: $0.0, screen: $0.1, desktop: $0.2) }
        case "unpin":
            guard parts.count == 1, let window = CGWindowID(parts[0]) else { return nil }
            return .unpin(window: window)
        case "free":
            guard parts.count == 2, let window = CGWindowID(parts[0]) else { return nil }
            if parts[1].lowercased() == "lock" {
                return .freeMove(window: window, duration: Router.freeMoveUntilLock)
            }
            guard let minutes = Int(parts[1]), minutes > 0 else { return nil }
            return .freeMove(window: window, duration: TimeInterval(minutes * 60))
        case "free-end":
            guard parts.count == 1, let window = CGWindowID(parts[0]) else { return nil }
            return .endFreeMove(window: window)
        case "rule-add":
            guard let json = query.first(where: { $0.name == "json" })?.value,
                  let rule = try? JSONDecoder().decode(Rule.self, from: Data(json.utf8))
            else { return nil }
            return .addRule(rule)
        case "rule-remove":
            guard parts.count == 1 else { return nil }
            return .removeRule(id: parts[0])
        case "profile-set":
            struct Payload: Decodable {
                var id: String?
                var name: String
                var rules: [Rule]
            }
            guard let json = query.first(where: { $0.name == "json" })?.value,
                  let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
            else { return nil }
            let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let flag = query.first { $0.name == "activate" }?.value?.lowercased()
            var profile = Profile(name: name, rules: payload.rules)
            if let id = payload.id, !id.isEmpty { profile.id = id }
            return .setProfile(profile, activate: flag == "1" || flag == "true")
        case "profile-rename":
            let old = parts.joined(separator: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            let new = (query.first { $0.name == "name" }?.value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !old.isEmpty, !new.isEmpty else { return nil }
            return .renameProfile(from: old, to: new)
        case "profile-export":
            guard let path = query.first(where: { $0.name == "path" })?.value,
                  path.hasPrefix("/") else { return nil }
            let name = query.first { $0.name == "name" }?.value
            return .exportProfile(name: name?.isEmpty == true ? nil : name, path: path)
        case "desktop-move":
            guard parts.count == 3, let from = Int(parts[1]), let to = Int(parts[2]),
                  from >= 1, to >= 1, from != to else { return nil }
            var mode: Mode?
            if let raw = query.first(where: { $0.name == "mode" })?.value {
                guard let parsed = Mode(rawValue: raw.lowercased()) else { return nil }
                mode = parsed
            }
            return .moveDesktop(screen: parts[0].lowercased(), from: from, to: to, mode: mode)
        case "rule-save-layout":
            guard parts.count == 1 else { return nil }
            var window: CGWindowID?
            if let raw = query.first(where: { $0.name == "window" })?.value {
                guard let id = CGWindowID(raw) else { return nil }
                window = id
            }
            return .saveLayout(rule: parts[0], window: window)
        case "desktop-name":
            guard parts.count == 2, let desktop = Int(parts[1]), desktop >= 1 else { return nil }
            let name = query.first { $0.name == "name" }?.value ?? ""
            var mode: Mode?
            if let raw = query.first(where: { $0.name == "mode" })?.value {
                guard let parsed = Mode(rawValue: raw.lowercased()) else { return nil }
                mode = parsed
            }
            return .nameDesktop(screen: parts[0].lowercased(), desktop: desktop, name: name, mode: mode)
        case "plan-desktops":
            guard parts.count == 2, let count = Int(parts[1]), (1...16).contains(count)
            else { return nil }
            var mode: Mode?
            if let raw = query.first(where: { $0.name == "mode" })?.value {
                guard let parsed = Mode(rawValue: raw.lowercased()) else { return nil }
                mode = parsed
            }
            return .planDesktops(screen: parts[0].lowercased(), count: count, mode: mode)
        case "screen-role":
            guard parts.count == 2, DisplayRoles.isExternalRole(parts[1].lowercased()) else { return nil }
            return .screenRole(display: parts[0], role: parts[1].lowercased())
        case "screen-role-forget":
            return .forgetScreenRoles
        case "screen-fallback":
            guard parts.count == 1 else { return nil }
            switch parts[0].lowercased() {
            case "on", "1", "true":   return .screenFallback(true)
            case "off", "0", "false": return .screenFallback(false)
            default:                  return nil
            }
        case "reapply":      return .reapply
        case "pause":        return .pause
        case "resume":       return .resume
        case "toggle":       return .toggle
        case "next-profile", "nextprofile", "next":
            return .nextProfile
        case "add-desktop", "adddesktop":
            let screen = parts.joined(separator: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return screen.isEmpty ? nil : .addDesktop(screen: screen.lowercased())
        case "remove-desktop", "removedesktop":
            guard parts.count == 2, let desktop = Int(parts[1]), desktop >= 1 else { return nil }
            return .removeDesktop(screen: parts[0].lowercased(), desktop: desktop)
        case "profile":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let fromQuery = query?.first { $0.name.lowercased() == "name" }?.value
            let raw = fromQuery ?? parts.joined(separator: "/")
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .profile(name: name)
        default:
            return nil
        }
    }
}

/// URL komutlarını Store ve Router üzerinde çalıştırır. Bilinmeyen komut
/// ya da profil çökmez; alt çubukta (yerelleştirilmiş) bir hata gösterilir.
@MainActor
enum URLCommands {

    static func handle(_ urls: [URL], store: Store, router: Router, status: StatusFile? = nil) {
        for url in urls { handle(url, store: store, router: router, status: status) }
    }

    static func handle(_ url: URL, store: Store, router: Router, status: StatusFile? = nil) {
        let request = requestID(url)
        guard let command = URLCommand.parse(url) else {
            store.report(L("Unknown URL command: %@", url.absoluteString))
            status?.write(request: request)
            return
        }
        // Komut satırı aracı hatayı bu komuttan ayırt edebilsin.
        if request != nil { store.clearError() }
        run(command, store: store, router: router)
        status?.write(request: request)
    }

    /// `?req=<n>`: komut satırı aracının istek kimliği.
    nonisolated static func requestID(_ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "req" }?.value
    }

    /// Komuttaki monitör: şu anki rolü (`external-2`) ya da UUID'si (en az 4
    /// karakterlik baş, büyük/küçük harf ve süslü parantez fark etmez); tek
    /// eşleşme gerekir (saf).
    nonisolated static func connectedDisplay(
        _ text: String, in current: [(role: String, display: DisplayRoles.Display)]
    ) -> String? {
        let lowered = text.lowercased()
        if let hit = current.first(where: { $0.role == lowered }) { return hit.display.uuid }
        let key = ScreenInfo.normalize(text)
        guard key.count >= 4 else { return nil }
        let hits = current.filter { ScreenInfo.normalize($0.display.uuid).hasPrefix(key) }
        return hits.count == 1 ? hits[0].display.uuid : nil
    }

    static func run(_ command: URLCommand, store: Store, router: Router) {
        switch command {
        case .reapply:
            router.reapplyAll()
        case .pause:
            store.document.enabled = false
        case .resume:
            store.document.enabled = true
        case .toggle:
            store.document.enabled.toggle()
        case .profile(let name):
            guard let profile = profile(named: name, in: store.profiles) else {
                store.report(L("Profile not found: %@", name))
                return
            }
            store.switchProfile(to: profile.id)
        case .nextProfile:
            let profiles = store.profiles
            guard profiles.count > 1,
                  let index = profiles.firstIndex(where: { $0.id == store.document.activeProfileID })
            else { return }
            store.switchProfile(to: profiles[(index + 1) % profiles.count].id)
        case .removeDesktop(let screen, let desktop):
            Task {
                if await !router.removeDesktop(on: screen, desktop: desktop) {
                    store.report(L("Could not remove desktop %ld on %@", desktop, screen))
                }
            }
        case .reload:
            store.load()
        case .status:
            break
        case .backupNow:
            guard let backups = AppModel.shared.backups else { return }
            if let error = backups.runNow().skipped {
                store.report(L("No backup taken: %@", error.localizedDescription))
            }
        case .restoreBackup(let id):
            AppModel.shared.backups?.restore(id, store: store, router: router)
        case .pin(let window, let screen, let desktop, let desktopOnly):
            guard router.windows.contains(where: { $0.id == window }) else {
                store.report(L("Window not found: %@", String(window)))
                return
            }
            router.pinSession(window, destination: Destination(
                screen: screen, desktop: desktop, layout: desktopOnly ? .anyFrame : .full))
        case .pinToName(let window, let name, let desktopOnly):
            guard router.windows.contains(where: { $0.id == window }) else {
                store.report(L("Window not found: %@", String(window)))
                return
            }
            guard let record = store.document.nameRecord(named: name) else {
                store.report(L("Desktop name not found: %@", name))
                return
            }
            let mode = AppModel.shared.screens.mode
            let place = record.space.flatMap { store.live?.place(of: $0) }
                ?? store.document.plans.place(of: record.id, mode: mode)
            router.pinSession(window, destination: Destination(
                screen: place?.screen ?? "builtin", desktop: place?.desktop ?? 1,
                layout: desktopOnly ? .anyFrame : .full, nameID: record.id))
        case .quit:
            store.flush()
            NSApplication.shared.terminate(nil)
        case .unpin(let window):
            router.unpinSession(window)
        case .freeMove(let window, let duration):
            router.allowFreeMove([window], for: duration)
            if router.freeMoves[window] == nil {
                store.report(L("Free move needs a pinned window: %@", String(window)))
            }
        case .endFreeMove(let window):
            router.endFreeMove([window])
        case .move(let window, let screen, let desktop):
            guard router.windows.contains(where: { $0.id == window }) else {
                store.report(L("Window not found: %@", String(window)))
                return
            }
            router.moveWindow(window, to: Router.Placement(screen: screen, desktop: desktop))
        case .addRule(let rule):
            store.add(rule)
        case .removeRule(let id):
            guard store.rule(id) != nil else {
                store.report(L("Rule not found: %@", id))
                return
            }
            store.remove(id)
        case .setProfile(let profile, let activate):
            store.upsertProfile(profile, activate: activate)
        case .planDesktops(let screen, let count, let mode):
            planDesktops(screen: screen, count: count, mode: mode, store: store, router: router)
        case .screenRole(let display, let role):
            let current = AppModel.shared.screens.connectedExternals
            guard let uuid = Self.connectedDisplay(display, in: current) else {
                store.report(L("No connected monitor matches %@", display))
                return
            }
            // Bir monitör ancak bağlı monitör sayısı kadar rolden birini alır:
            // "Monitör 3"e verilen tek monitör Monitör 1'i boş bırakırdı.
            guard let index = DisplayRoles.externalIndex(of: role), index <= current.count else {
                store.report(L("Only %ld monitors are connected", current.count))
                return
            }
            store.chooseDisplay(uuid, for: role,
                                current: current.map { (role: $0.role, uuid: $0.display.uuid) })
        case .forgetScreenRoles:
            store.forgetDisplayRoles()
        case .screenFallback(let on):
            store.setDisplayFallback(on)
        case .nameDesktop(let screen, let desktop, let name, let mode):
            let target = mode ?? AppModel.shared.screens.mode
            if !store.setDesktopName(name, screen: screen, desktop: desktop, mode: target) {
                store.report(L("A desktop named %@ already exists", name))
            }
        case .renameProfile(let from, let to):
            guard let profile = profile(named: from, in: store.profiles) else {
                store.report(L("Profile not found: %@", from))
                return
            }
            if store.profiles.contains(where: { $0.id != profile.id && $0.name == to }) {
                store.report(L("A profile named %@ already exists", to))
                return
            }
            store.renameProfile(profile.id, to: to)
        case .exportProfile(let name, let path):
            let target = name.flatMap { profile(named: $0, in: store.profiles) }
                ?? (name == nil ? store.document.activeProfile : nil)
            guard let target else {
                store.report(L("Profile not found: %@", name ?? ""))
                return
            }
            do {
                try store.exportData(for: target.id).write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                store.report(L("Could not export: %@", error.localizedDescription))
            }
        case .moveDesktop(let screen, let from, let to, let mode):
            moveDesktop(screen: screen, from: from, to: to, mode: mode, store: store, router: router)
        case .saveLayout(let ruleID, let windowID):
            saveLayout(ruleID: ruleID, windowID: windowID, store: store, router: router)
        case .addDesktop(let screen):
            Task {
                if await !router.addDesktop(on: screen) {
                    store.report(L("Could not add a desktop to %@", screen))
                }
            }
        }
    }

    /// Haritadaki sürükle-bırak ile aynı: hem kural hedefleri hem (etkin
    /// modda) pencereler ve oturum pinleri yeni sıraya geçer. Satır sayısı
    /// haritadaki gibi: gerçek, kural, pencere, pin ve plan sayılarının en büyüğü.
    private static func moveDesktop(screen: String, from: Int, to: Int, mode: Mode?,
                                    store: Store, router: Router) {
        let screens = AppModel.shared.screens
        let mode = mode ?? screens.mode
        let live = mode == screens.mode
        let used = store.document.rules.compactMap { $0[mode] }
            .filter { $0.screen == screen }.map(\.desktop).max() ?? 0
        let windows = live ? router.windows.compactMap(\.placement)
            .filter { $0.screen == screen }.map(\.desktop).max() ?? 0 : 0
        let session = live ? router.sessionPins.values
            .filter { $0.screen == screen }.map(\.desktop).max() ?? 0 : 0
        let real = live ? router.desktopCounts[screen] ?? 0 : 0
        let planned = store.document.plannedDesktops(mode: mode, screen: screen)
        let count = max(real, used, windows, session, planned, 1)
        guard from <= count, to <= count else {
            store.report(L("Desktop %ld on %@ does not exist", max(from, to), screen))
            return
        }
        let liveSpaces = router.reorderedSpaces(on: screen, from: from, to: to,
                                                reorderWindows: live)
        let sessionMoved = router.moveDesktop(on: screen, from: from, to: to, count: count,
                                              reorderWindows: live)
        store.moveDesktop(
            on: screen, from: from, to: to, count: count, mode: mode, sharedLaptop: live,
            liveSpaces: liveSpaces,
            undoingSessionPins: sessionMoved
                ? { router.moveDesktop(on: screen, from: to, to: from, count: count,
                                       reorderWindows: live) }
                : nil)
    }

    /// Paneldeki "Şu anki boyut ve konumu kullan" ile aynı: kuralın etkin
    /// moddaki yerleşimi, kurala uyan pencerenin (ya da verilen pencerenin)
    /// şu anki çerçevesinden. Ekran ve masaüstü değişmez.
    private static func saveLayout(ruleID: String, windowID: CGWindowID?,
                                   store: Store, router: Router) {
        let mode = AppModel.shared.screens.mode
        guard let rule = store.rule(ruleID) else {
            store.report(L("Rule not found: %@", ruleID))
            return
        }
        guard let destination = rule[mode] else {
            store.report(L("Rule has no target in this plan: %@", ruleID))
            return
        }
        let matching = router.windows.filter {
            rule.matches($0)
        }
        let window = windowID.map { id in matching.first { $0.id == id } } ?? matching.first
        guard let window,
              let layout = window.currentLayout(like: destination.layout,
                                                screens: AppModel.shared.screens.screens)
        else {
            store.report(L("No open window for rule: %@", ruleID))
            return
        }
        _ = store.saveLayout(layout, for: ruleID, mode: mode)
    }

    /// Önce tam eşleşme, sonra büyük/küçük harfe duyarsız eşleşme.
    static func profile(named name: String, in profiles: [Profile]) -> Profile? {
        profiles.first { $0.name == name }
            ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Ekranda `count` masaüstü olsun. Etkin modda Mission Control ile
    /// ekler/siler; etkin olmayan modda plana yazar / silmeyi sıraya alır
    /// (haritadaki + ve sil yollarıyla aynı). Silinecek masaüstüne kural
    /// ya da oturum pini bakıyorsa hata bildirir, hiçbir şey yapmaz.
    private static func planDesktops(screen: String, count: Int, mode: Mode?,
                                     store: Store, router: Router) {
        let screens = AppModel.shared.screens
        let mode = mode ?? screens.mode
        let isLive = mode == screens.mode
        let real = router.desktopCounts[screen]
        let planned = store.document.plannedDesktops(mode: mode, screen: screen)
        let have = isLive ? (real ?? 0) : planned
        if isLive && real == nil {
            store.report(L("Could not add a desktop to %@", screen))
            return
        }
        guard count != have else { return }
        if count > have {
            guard isLive else {
                store.planDesktop(on: screen, mode: mode, count: count)
                return
            }
            Task {
                for _ in have..<count {
                    if await !router.addDesktop(on: screen) {
                        store.report(L("Could not add a desktop to %@", screen))
                        return
                    }
                }
            }
            return
        }
        if let blocked = store.document.desktopBlockingRemoval(
            on: screen, mode: mode, keeping: count, total: have,
            sessionPins: isLive ? Array(router.sessionPins.values) : []) {
            store.report(L("Desktop %ld on %@ still has pinned rules", blocked, screen))
            return
        }
        if isLive {
            Task {
                for desktop in stride(from: have, to: count, by: -1) {
                    if await !router.removeDesktop(on: screen, desktop: desktop) {
                        store.report(L("Could not remove desktop %ld on %@", desktop, screen))
                        return
                    }
                }
            }
        } else {
            // Etkin olmayan kurulum: yalnız plan kısalır (gerçek masaüstü silinmez).
            for desktop in stride(from: have, to: count, by: -1) {
                store.removePlanEntry(on: screen, desktop: desktop, mode: mode)
            }
        }
    }
}
