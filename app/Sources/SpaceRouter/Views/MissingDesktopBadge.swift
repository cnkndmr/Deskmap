import SwiftUI

/// Pinin hedef masaüstü bağlı ekranda yoksa (Mission Control'de o kadar
/// masaüstü açık değilse) router pencereyi sessizce sonuncuya kırpar. Bu
/// rozet o kırpmayı görünür kılar: "D5→3" (Türkçede "M5→3").
struct MissingDesktopBadge: View {

    let wanted: Int
    let real: Int

    var body: some View {
        Text(L("D%ld→%ld", wanted, real))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .help(L("Desktops on this display: %ld. Add desktops in Mission Control or drag the pin to another desktop.", real))
    }

    /// Rozet kararı: ekran bağlıysa (`realCount` biliniyorsa) ve hedef
    /// gerçek sayıdan büyükse router'ın kırpacağı masaüstü; yoksa nil.
    static func clamped(wanted: Int, realCount: Int?) -> Int? {
        guard let realCount, realCount >= 1, wanted > realCount else { return nil }
        return realCount
    }

    /// Hedefin ekranı için `desktopCounts`'tan karar. `desktopCounts` şu an
    /// bağlı ekranları anlatır ve router yalnızca şu anki modda kırpar; harita
    /// diğer modu gösteriyorsa (`isLive` false) rozet yok.
    static func clamped(for destination: Destination, desktopCounts: [String: Int],
                        isLive: Bool) -> Int? {
        guard isLive else { return nil }
        return clamped(wanted: destination.desktop, realCount: desktopCounts[destination.screen])
    }
}
