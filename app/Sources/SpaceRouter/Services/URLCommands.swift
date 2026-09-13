import Foundation

/// `spacerouter://` URL şemasıyla gelen otomasyon komutları (Shortcuts
/// "Open URLs", Raycast, Hammerspoon `hs.urlevent`, terminalde `open`).
///
///     spacerouter://reapply              pinli pencereleri şimdi yerleştir
///     spacerouter://pause                yönlendirmeyi duraklat
///     spacerouter://resume               yönlendirmeyi sürdür
///     spacerouter://toggle               duraklat / sürdür
///     spacerouter://profile/<ad>         adı verilen profile geç
///     spacerouter://profile?name=<ad>    aynı; "/" içeren adlar için
///     spacerouter://next-profile         sıradaki profile geç (döner)
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

    static let scheme = "spacerouter"

    /// `url` geçerli bir komutsa onu döndürür; şema yanlışsa, komut
    /// bilinmiyorsa ya da profil adı boşsa `nil`. Komut adı büyük/küçük
    /// harfe duyarsızdır; `spacerouter:reapply` (host'suz) biçimi de kabul
    /// edilir.
    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        // `spacerouter://profile/Ofis`: host "profile", yol ["Ofis"].
        // `spacerouter:profile/Ofis`:   host yok, yol ["profile", "Ofis"].
        // `pathComponents` yüzde kodlamasını çözer.
        var parts = url.pathComponents.filter { $0 != "/" }
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
/// ya da profil çökmez; alt çubukta Türkçe bir hata gösterilir.
@MainActor
enum URLCommands {

    static func handle(_ urls: [URL], store: Store, router: Router) {
        for url in urls { handle(url, store: store, router: router) }
    }

    static func handle(_ url: URL, store: Store, router: Router) {
        guard let command = URLCommand.parse(url) else {
            store.report("Bilinmeyen URL komutu: \(url.absoluteString)")
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
                store.report("Profil bulunamadı: \(name)")
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
