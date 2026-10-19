import Foundation

/// Masaüstü taşımasının bu macOS sürümünde beklenen durumu (saf, PLAN K4).
///
/// Taşıma yolu var olsa bile bazı sürümlerde çağrı sessizce başarı döndürüp
/// pencereyi taşımayabilir. Doğrulanmamış sürümlerde taşıma kapalı başlar;
/// kullanıcı "Yine de dene" derse açılır ve devre kesici (`MoveHealth`) izler.
enum MoveSupport: Equatable {
    /// Taşıma yolu bu sürümde çalışması beklenen yol.
    case supported
    /// Taşıma yolu var ama bu sürümde doğrulanmadı (Sequoia 15.x,
    /// Tahoe 26.0–26.3).
    case unverified
    /// Bu macOS'ta taşıma yolu yok.
    case unavailable

    static func classify(major: Int, minor: Int, hasMovePath: Bool) -> MoveSupport {
        guard hasMovePath else { return .unavailable }
        if major == 15 || (major == 26 && minor < 4) { return .unverified }
        return .supported
    }

    static func classify(_ version: OperatingSystemVersion, hasMovePath: Bool) -> MoveSupport {
        classify(major: version.majorVersion, minor: version.minorVersion,
                 hasMovePath: hasMovePath)
    }

    /// Kartta gösterilen sürüm: "15.3", "26.1.2".
    static func versionLabel(_ version: OperatingSystemVersion) -> String {
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion == 0 ? base : base + ".\(version.patchVersion)"
    }

    /// Kullanıcı doğrulanmamış sürümde taşımayı bir kez açtıysa kalıcı.
    static let allowUnverifiedKey = "AllowUnverifiedDesktopMoves"
}
