import AppKit
import SwiftUI

/// Sürüklerken haritayı kaydırır: imleç harita görünür alanının üst ya da
/// alt kenarına (ya da ötesine) yaklaşınca harita o yöne kayar; kenara ne
/// kadar yakınsa o kadar hızlı. SwiftUI `ScrollView` programla piksel
/// kaydırma sunmadığı için alttaki `NSScrollView` doğrudan sürülür.
@MainActor
final class AutoScroller {

    /// Kenar bandının yüksekliği (pt) ve bant içindeki en yüksek hız
    /// (pt / tur, 60 Hz).
    nonisolated static let edge: CGFloat = 56
    nonisolated static let maxSpeed: CGFloat = 16

    weak var scrollView: NSScrollView?
    /// Her kaydırma adımından sonra (bırakma hedefi yeniden seçilsin).
    var onScroll: (() -> Void)?

    private var timer: Timer?
    private var velocity: CGFloat = 0

    /// İmleç konumu (harita koordinat uzayında) ve haritanın görünür alanı.
    /// Sürükleme yoksa `point` nil: kaydırma durur.
    func update(point: CGPoint?, viewport: CGRect) {
        velocity = point.map { Self.velocity(for: $0, in: viewport) } ?? 0
        if velocity == 0 {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.step() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Kaydırma hızı (saf): yukarı negatif, aşağı pozitif; imleç haritanın
    /// yatay aralığı dışındaysa (ör. kenar çubuğunda) ya da kenar bandında
    /// değilse sıfır. Görünür alanın dışına taşan imleç en yüksek hızı alır.
    nonisolated static func velocity(for point: CGPoint, in viewport: CGRect) -> CGFloat {
        guard viewport.height > edge * 2, point.x >= viewport.minX, point.x <= viewport.maxX
        else { return 0 }
        let top = viewport.minY + edge - point.y
        if top > 0 { return -maxSpeed * min(top / edge, 1) }
        let bottom = point.y - (viewport.maxY - edge)
        if bottom > 0 { return maxSpeed * min(bottom / edge, 1) }
        return 0
    }

    private func step() {
        guard velocity != 0, let scrollView, let document = scrollView.documentView else {
            timer?.invalidate()
            timer = nil
            return
        }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        let limit = max(document.frame.height - clip.bounds.height, 0)
        // SwiftUI belge görünümü çevrik (y aşağı artar); değilse yön terstir.
        let delta = document.isFlipped ? velocity : -velocity
        let next = min(max(origin.y + delta, 0), limit)
        guard next != origin.y else { return }
        origin.y = next
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        onScroll?()
    }
}

/// ScrollView içeriğine konur; kendisini saran `NSScrollView`'u bildirir.
struct EnclosingScrollViewReader: NSViewRepresentable {

    let found: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView { Probe(found: found) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        let found: (NSScrollView) -> Void
        init(found: @escaping (NSScrollView) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scrollView = enclosingScrollView { found(scrollView) }
        }
    }
}

/// Kaydırılan bölgelerin görünür çerçeveleri (harita koordinat uzayında).
struct ViewportPreference: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Bu görünümün çerçevesini görünür alan olarak bildirir.
    func reportsViewport(_ key: String) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ViewportPreference.self,
                    value: [key: geometry.frame(in: .named(MapSpace.name))])
            })
    }
}
