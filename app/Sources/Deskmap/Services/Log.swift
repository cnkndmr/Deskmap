import os

/// Birleşik günlük (`os.Logger`). Konsol.app ya da terminalden izlenir:
///
///     log stream --predicate 'subsystem == "com.deskmap.app"' --level info
///
/// Seyrek tutulur: her taramada değil, yalnızca bir şey olduğunda yazılır
/// (taşıma, vazgeçme, backoff, ekran/uyku geçişleri). Pencere başlıkları
/// `.private` ile gizlenir; uygulama adı ve pencere numarası açıktır.
enum Log {
    private static let subsystem = "com.deskmap.app"

    /// Tarama ve yönlendirme kararları (taşıma, düzen, vazgeçme, pin ömrü).
    static let routing = Logger(subsystem: subsystem, category: "routing")
    /// SkyLight özel çağrıları (kullanılabilirlik, taşıma yolu).
    static let skylight = Logger(subsystem: subsystem, category: "skylight")
    /// Accessibility (yanıt vermeyen uygulama backoff'u, gözlemci kaydı).
    static let ax = Logger(subsystem: subsystem, category: "ax")
    /// Ekran değişimleri ve uyku/uyanma.
    static let screens = Logger(subsystem: subsystem, category: "screens")
    /// Uygulama yaşam döngüsü (ör. eski veri klasöründen göç).
    static let app = Logger(subsystem: subsystem, category: "app")
}
