import SwiftUI

/// Haritadaki bırakma hedefleri.
enum DropTarget: Hashable {
    case desktop(screen: String, desktop: Int)
    case tray
}

struct DropTargetFrame: Equatable {
    let target: DropTarget
    let frame: CGRect
}

/// Alt görünümler kendi çerçevelerini harita koordinat uzayında bildirir.
struct DropTargetPreference: PreferenceKey {
    static let defaultValue: [DropTargetFrame] = []
    static func reduce(value: inout [DropTargetFrame], nextValue: () -> [DropTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

/// Çip sürükleme durumu. Sistem sürükle-bırak yerine kendi jestimizi
/// kullanıyoruz: menü çubuğu penceresinde daha güvenilir ve tıklama ile
/// çakışmıyor.
struct ChipDrag: Equatable {
    var item: DragItem
    var location: CGPoint
    var hover: DropTarget?
}

/// Sürüklenen şey: pinli bir kural çipi ya da canlı bir pencere satırı.
enum DragItem: Equatable {
    case rule(String)
    case window(CGWindowID)
    /// Bir masaüstü satırı; üstündeki pinlerle birlikte sıralanır.
    case desktop(screen: String, desktop: Int)
}

extension View {
    /// Görünümü bırakma hedefi olarak kaydeder.
    func dropTarget(_ target: DropTarget) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DropTargetPreference.self,
                    value: [DropTargetFrame(
                        target: target,
                        frame: geometry.frame(in: .named(MapSpace.name)))])
            })
    }
}

enum MapSpace {
    static let name = "deskmap.map"
}
