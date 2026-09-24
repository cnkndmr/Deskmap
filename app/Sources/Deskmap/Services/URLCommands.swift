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

        switch command {
        case "reapply":      return .reapply
        case "pause":        return .pause
        case "resume":       return .resume
        case "toggle":       return .toggle
        case "next-profile", "nextprofile", "next":
            return .nextProfile
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

    static func handle(_ urls: [URL], store: Store, router: Router) {
        for url in urls { handle(url, store: store, router: router) }
    }

    static func handle(_ url: URL, store: Store, router: Router) {
        guard let command = URLCommand.parse(url) else {
            store.report(L("Unknown URL command: %@", url.absoluteString))
            return
        }
        run(command, store: store, router: router)
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
        }
    }

    /// Önce tam eşleşme, sonra büyük/küçük harfe duyarsız eşleşme.
    static func profile(named name: String, in profiles: [Profile]) -> Profile? {
        profiles.first { $0.name == name }
            ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
