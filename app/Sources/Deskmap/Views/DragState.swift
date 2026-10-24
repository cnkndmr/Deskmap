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
    /// Sürükleme "Kurulumlar arasında farklı" kutusundan başladı: kutuya
    /// geri bırakmak hiçbir şey yapmaz (pin kaldırılmaz).
    var fromTray = false
}

/// Sürüklenen şey: pinli bir kural çipi ya da canlı bir pencere satırı.
enum DragItem: Equatable {
    case rule(String)
    case window(CGWindowID)
    /// Bir masaüstü satırı; üstündeki pinlerle birlikte sıralanır.
    case desktop(screen: String, desktop: Int)
    /// Bir masaüstündeki uygulama grubunun tamamı (başlıktan sürüklenir).
    case group(screen: String, desktop: Int, app: String, name: String)
    /// Bir pin grubunun tamamı (kutu başlığından sürüklenir); bırakılan
    /// masaüstüne grubun bu moddaki bütün üyeleri gider.
    case pinGroup(screen: String, desktop: Int, id: String, name: String)

    /// Sürüklenen pin grubunun kimliği (başka bir şeyse nil). Dağınık grubun
    /// hangi kutusundan tutulursa tutulsun bütün üyeler gider; soluklaştırma
    /// bunu kullanır, yer bilgisini değil.
    var pinGroupID: String? {
        if case .pinGroup(_, _, let id, _) = self { return id }
        return nil
    }
}

extension View {
    /// Görünümü bırakma hedefi olarak kaydeder. `enabled` false ise
    /// kaydetmez (aynı hedefi taşıyan ikinci kart, ör. rolü onay bekleyen
    /// monitörde olan soluk kart).
    func dropTarget(_ target: DropTarget, enabled: Bool = true) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: DropTargetPreference.self,
                    value: enabled ? [DropTargetFrame(
                        target: target,
                        frame: geometry.frame(in: .named(MapSpace.name)))] : [])
            })
    }
}

enum MapSpace {
    static let name = "deskmap.map"
}
