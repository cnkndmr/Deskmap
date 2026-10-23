import Foundation
import os

/// Birleşik günlük (`os.Logger`). Konsol.app ya da terminalden izlenir:
///
///     log stream --predicate 'subsystem == "com.deskmap.app"' --level info
///
/// Seyrek tutulur: her taramada değil, yalnızca bir şey olduğunda yazılır
/// (taşıma, vazgeçme, backoff, ekran/uyku geçişleri). Pencere başlıkları
/// `.private` ile gizlenir; uygulama adı ve pencere numarası açıktır.
enum Log {
    /// Testler ayrı alt sistemde: gerçek uygulamanın günlüğü
    /// (`subsystem == "com.deskmap.app"`) test satırlarıyla karışmasın.
    private static let subsystem = isTesting ? "com.deskmap.app.tests" : "com.deskmap.app"

    /// Süreç bir test koşucusu mu (swift test / Xcode). Testler gerçek
    /// Application Support'a hiç dokunmasın diye `Store.directoryURL` de buna bakar.
    static let isTesting: Bool = {
        let env = ProcessInfo.processInfo.environment
        let name = ProcessInfo.processInfo.processName
        return name == "swiftpm-testing-helper" || name == "xctest" || name.hasSuffix("PackageTests")
            || env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
    }()

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
    /// M0: tarama hattı süre özeti (PerfStats, 5 dk'da bir).
    static let perf = Logger(subsystem: subsystem, category: "perf")
}
