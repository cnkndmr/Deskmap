import Foundation

/// Menü çubuğu simgesinin üç durumu (saf karar).
enum AppHealth: Equatable {
    /// Kurallar uygulanıyor, dikkat gerektiren bir şey yok.
    case ready
    /// Kullanıcı duraklattı.
    case paused
    /// İzin yok, zorunlu bir macOS ayarı kapalı ya da düşük mod: kullanıcının
    /// bakması gerekiyor. Duraklatmadan önce gelir (sorun gizlenmesin).
    case needsAttention

    static func state(enabled: Bool, trusted: Bool, requiredSettingsOK: Bool,
                      movesDegraded: Bool) -> AppHealth {
        if !trusted || !requiredSettingsOK || movesDegraded { return .needsAttention }
        return enabled ? .ready : .paused
    }

    /// Simgenin erişilebilirlik etiketi ve ipucu.
    var label: String {
        switch self {
        case .ready: return L("Deskmap: Ready")
        case .paused: return L("Deskmap: Paused")
        case .needsAttention: return L("Deskmap: Needs attention")
        }
    }
}
