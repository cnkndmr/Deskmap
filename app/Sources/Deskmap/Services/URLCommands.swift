import CoreGraphics
import Foundation

/// `deskmap://` URL şemasıyla gelen otomasyon komutları (Shortcuts
/// "Open URLs", Raycast, Hammerspoon `hs.urlevent`, terminalde `open`).
/// Eski `spacerouter://` şeması da (Deskmap'in eski adı) aynen kabul
/// edilir — bakımcının Shortcuts/Raycast kurulumları bozulmasın diye.
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
///     deskmap://unpin/<pencere>      oturum pinini kaldır
///     deskmap://move/<pencere>/<ekran>/<n>   pencereyi bir kez taşı
///     deskmap://rule-add?json=<kural>        kural ekle (Rule JSON'u)
///     deskmap://rule-remove/<kimlik> kuralı sil
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
    case pin(window: CGWindowID, screen: String, desktop: Int)
    case unpin(window: CGWindowID)
    case move(window: CGWindowID, screen: String, desktop: Int)
    case addRule(Rule)
    case removeRule(id: String)

    static let scheme = "deskmap"
    /// Eski uygulama adı; süresiz kabul edilir (bkz. tip belgesi).
    static let legacyScheme = "spacerouter"

    /// `url` geçerli bir komutsa onu döndürür; şema yanlışsa (ne `deskmap`
    /// ne eski `spacerouter`), komut bilinmiyorsa ya da profil adı boşsa
    /// `nil`. Komut adı büyük/küçük harfe duyarsızdır; `deskmap:reapply`
    /// (host'suz) biçimi de kabul edilir.
    static func parse(_ url: URL) -> URLCommand? {
        guard let urlScheme = url.scheme?.lowercased(),
              urlScheme == scheme || urlScheme == legacyScheme
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
        case "pin":
            return windowTarget().map { .pin(window: $0.0, screen: $0.1, desktop: $0.2) }
        case "move":
            return windowTarget().map { .move(window: $0.0, screen: $0.1, desktop: $0.2) }
        case "unpin":
            guard parts.count == 1, let window = CGWindowID(parts[0]) else { return nil }
            return .unpin(window: window)
        case "rule-add":
            guard let json = query.first(where: { $0.name == "json" })?.value,
                  let rule = try? JSONDecoder().decode(Rule.self, from: Data(json.utf8))
            else { return nil }
            return .addRule(rule)
        case "rule-remove":
            guard parts.count == 1 else { return nil }
            return .removeRule(id: parts[0])
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
        case .pin(let window, let screen, let desktop):
            guard router.windows.contains(where: { $0.id == window }) else {
                store.report(L("Window not found: %@", String(window)))
                return
            }
            router.pinSession(window, destination: Destination(screen: screen, desktop: desktop))
        case .unpin(let window):
            router.unpinSession(window)
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
        case .addDesktop(let screen):
            Task {
                if await !router.addDesktop(on: screen) {
                    store.report(L("Could not add a desktop to %@", screen))
                }
            }
        }
    }

    /// Önce tam eşleşme, sonra büyük/küçük harfe duyarsız eşleşme.
    static func profile(named name: String, in profiles: [Profile]) -> Profile? {
        profiles.first { $0.name == name }
            ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
