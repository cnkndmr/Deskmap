import SwiftUI

/// Pin düğmesine basılınca oluşan taslak: hangi pencere, bulunduğu
/// masaüstüne. Başlık parçası seçilince kurala dönüşür.
struct PinDraft: Equatable {
    var window: Router.WindowSnapshot
    var target: Router.Placement
}

/// Haritanın altında açılan panel. Aynı anda yalnızca biri açık olur;
/// tek bir değer olduğu için biri açılınca diğeri kendiliğinden kapanır.
enum BottomPanel: Equatable {
    /// Pin düğmesi / sürükleme sonrası başlık parçası bekleyen taslak.
    case pin(PinDraft)
    /// Çipine ya da satırına tıklanan pin (kural kimliği).
    case rule(String)
    /// Satırına tıklanan oturum pinli (geçici) pencere.
    case session(CGWindowID)
    /// Aktif profil paneli (ad, kopya, dışa aktar, sil).
    case profile
}

/// Pencere içi görünüm durumu. Menü çubuğu penceresi popover, sheet veya
/// menü açılınca kapandığı için her şey aynı pencerede, satır içi gösterilir.
@MainActor
final class UIState: ObservableObject {
    /// Açık alt panel; nil = kapalı.
    @Published var panel: BottomPanel?
    /// Kural paneli bir pencere satırından açıldıysa o pencere; çipten
    /// açıldıysa nil. "Şu anki boyutu kullan" düğmesi ölçüyü bu pencereden
    /// okur; yoksa kurala uyan ilk pencereden.
    @Published var panelSourceWindowID: CGWindowID?
    /// Daraltılmış uygulama grupları ("ekran|masaüstü|bundleID").
    @Published var collapsed: Set<String> = []
    /// Haritada gösterilen pencereler. Sürükleme sürerken yenilenmez.
    @Published var windows: [Router.WindowSnapshot] = []
    /// Bağlı ekranlardaki gerçek masaüstü sayısı (ekran id → sayı); her
    /// taramada yenilenir. Hedefi bunun dışında kalan pin rozetle uyarılır.
    @Published var desktopCounts: [String: Int] = [:]

    /// Sürükleme sırasında canlı durum ve bilinen hedef çerçeveleri.
    @Published var drag: ChipDrag?
    var targets: [DropTargetFrame] = []

    func target(at point: CGPoint) -> DropTarget? {
        targets.first { $0.frame.contains(point) }?.target
    }

    // MARK: Panel kısayolları

    var pinDraft: PinDraft? {
        if case .pin(let draft) = panel { return draft }
        return nil
    }

    var selectedRuleID: String? {
        if case .rule(let id) = panel { return id }
        return nil
    }

    var selectedSessionWindowID: CGWindowID? {
        if case .session(let id) = panel { return id }
        return nil
    }

    var isProfilePanelOpen: Bool { panel == .profile }

    /// Aynı panele tekrar tıklamak kapatır, başkasına tıklamak onu açar.
    /// `from`: paneli açan pencere satırı (çipten açılıyorsa nil).
    func toggle(_ target: BottomPanel, from window: CGWindowID? = nil) {
        panel = panel == target ? nil : target
        panelSourceWindowID = panel == nil ? nil : window
    }
}

// MARK: - Alt panel çerçevesi

/// Alt panellerin ortak görünümü: üstte ayraç, geniş iç boşluk, hafif zemin.
struct BottomPanelChrome: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }
}

extension View {
    func bottomPanelChrome() -> some View { modifier(BottomPanelChrome()) }
}
