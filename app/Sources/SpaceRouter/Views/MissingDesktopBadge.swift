import SwiftUI

/// Pinin hedef masaüstü bağlı ekranda yoksa (Mission Control'de o kadar
/// masaüstü açık değilse) router pencereyi sessizce sonuncuya kırpar. Bu
/// rozet o kırpmayı görünür kılar: "M5→3".
struct MissingDesktopBadge: View {

    let wanted: Int
    let real: Int

    var body: some View {
        Text("M\(wanted)→\(real)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .help("Bu ekranda yalnızca \(real) masaüstü var; Mission Control'de masaüstü "
                  + "ekleyin ya da pini başka masaüstüne sürükleyin")
    }

    /// Rozet kararı: ekran bağlıysa (`realCount` biliniyorsa) ve hedef
    /// gerçek sayıdan büyükse router'ın kırpacağı masaüstü; yoksa nil.
    static func clamped(wanted: Int, realCount: Int?) -> Int? {
        guard let realCount, realCount >= 1, wanted > realCount else { return nil }
        return realCount
    }

    /// Hedefin ekranı için `desktopCounts`'tan karar.
    static func clamped(for destination: Destination, desktopCounts: [String: Int]) -> Int? {
        clamped(wanted: destination.desktop, realCount: desktopCounts[destination.screen])
    }
}
