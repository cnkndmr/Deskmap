import AppKit
import SwiftUI

/// Pin düğmesine basılınca oluşan taslak: hangi pencere, bulunduğu
/// masaüstüne. Başlık parçası seçilince kurala dönüşür.
struct PinDraft: Equatable {
    var window: Router.WindowSnapshot
    var target: Router.Placement
    /// Taslak canlı kurulumun sekmesinde mi açıldı. Diğer kurulumun
    /// sekmesinde açılan taslağın hedefini kullanıcı seçti (pencerenin yeri
    /// değil); o kurulum sonradan canlı olsa da (monitör takılıp çıkarılınca
    /// sekme değişmez, taslak açık kalır) hedef pencereyi izlemez.
    var followsWindow = true
    /// Canlı kurulumda taslak penceresini izler (saf): pencere taslak açıkken
    /// başka masaüstüne geçtiyse (haritada sürükleme, Mission Control, masaüstü
    /// sırasının geri alınması) hedef de oraya geçer; yoksa Pin pencereyi eski
    /// masaüstüne geri çekerdi. Başlık taslağın açıldığı andaki hâliyle kalır
    /// (seçilen parçalar ona ait). Çerçeve de izlenir: taslak açıkken (ya da
    /// harita kapalıyken, son taramadan sonra) taşınan/boyutu değişen
    /// pencerenin taze ölçümü gelince panelin varsayılan düzeni ona uyar;
    /// hedef masaüstü yalnız pencere masaüstü değiştirdiyse değişir. Yeri
    /// bilinmeyen tarama (tam ekran, geçiş anı) ve diğer kurulumun taslağı
    /// (açıldığı anda ya da şimdi) taslağı değiştirmez.
    func following(_ current: Router.WindowSnapshot, isLive: Bool) -> PinDraft {
        guard followsWindow, isLive, current.id == window.id,
              let placement = current.placement else { return self }
        let moved = placement != window.placement
        let frame = current.frame ?? window.frame
        guard moved || frame != window.frame else { return self }
        var followed = self
        followed.window = Router.WindowSnapshot(
            id: window.id, pid: window.pid, appName: window.appName,
            bundleID: window.bundleID, title: window.title, placement: placement,
            frame: frame, isMinimized: window.isMinimized,
            fullscreen: window.fullscreen)
        if moved { followed.target = placement }
        return followed
    }
}

/// Haritadaki pencere satırının kaydırma kimliği (`ScrollViewReader`).
struct WindowAnchor: Hashable {
    let id: CGWindowID
}

struct RevealRequest: Equatable {
    let window: CGWindowID
    let seq: Int
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
    /// Haritada görünür yere kaydırılacak pencere satırı; `seq` aynı
    /// pencere için isteği yeniler.
    @Published var reveal: RevealRequest?
    /// Daraltılmış uygulama grupları ("ekran|masaüstü|bundleID").
    @Published var collapsed: Set<String> = []
    /// Haritada gösterilen pencereler. Sürükleme sürerken yenilenmez.
    @Published var windows: [Router.WindowSnapshot] = []
    /// Bağlı ekranlardaki gerçek masaüstü sayısı (ekran id → sayı); her
    /// taramada yenilenir. Hedefi bunun dışında kalan pin rozetle uyarılır.
    @Published var desktopCounts: [String: Int] = [:]
    /// ⌘-tıklamayla seçilen pencereler (toplu pinleme).
    @Published var selection: Set<CGWindowID> = []
    /// Son fare basışında ⌘ basılı mıydı. Tek tıklama çift tıklama süresi
    /// dolunca işlenir; o anda ⌘ bırakılmış olabilir, bu yüzden basış
    /// anında yerel izleyiciyle kaydedilir.
    private(set) var commandAtMouseDown = false
    private var mouseMonitor: Any?

    func watchCommandClicks() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.commandAtMouseDown = event.modifierFlags.contains(.command)
            return event
        }
    }

    /// Sürükleme sırasında canlı durum ve bilinen hedef çerçeveleri.
    @Published var drag: ChipDrag?
    var targets: [DropTargetFrame] = []
    /// Kaydırılan bölgelerin görünür çerçeveleri ("map", "sidebar"). Bir
    /// bölgede kaydırılıp görünmez olmuş hedef, imleç o bölgenin dışında
    /// (ör. üst çubukta) iken seçilmesin diye nokta bunlardan birinde olmalı.
    var viewports: [String: CGRect] = [:]
    let autoScroll = AutoScroller()

    func target(at point: CGPoint) -> DropTarget? {
        Self.target(at: point, targets: targets, viewports: Array(viewports.values))
    }

    /// Bırakma hedefi (saf): nokta görünür bir bölgede ve hedefin içinde.
    nonisolated static func target(at point: CGPoint, targets: [DropTargetFrame],
                                   viewports: [CGRect]) -> DropTarget? {
        guard viewports.isEmpty || viewports.contains(where: { $0.contains(point) })
        else { return nil }
        return targets.first { $0.frame.contains(point) }?.target
    }

    /// Hedef çerçeveleri değişti (kaydırma, yeniden çizim): sürükleme
    /// sürüyorsa imleç kıpırdamasa da üzerindeki hedef yeniden seçilir.
    func refreshHover() {
        guard var drag else { return }
        let hover = target(at: drag.location)
        guard hover != drag.hover else { return }
        drag.hover = hover
        self.drag = drag
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

    /// Harita açılınca öndeki pencere için açılacak panel (saf): satırına
    /// tıklanmış gibi. Geçici pinliyse onun paneli, kurala uyuyorsa kuralın
    /// paneli, pinsizse bulunduğu masaüstüne taslak; yeri bilinmeyen ya da
    /// tam ekrandaki pinsiz pencerede panel açılmaz.
    nonisolated static func openingPanel(for window: Router.WindowSnapshot,
                                         sessionPinned: Bool, ruleID: String?) -> BottomPanel? {
        if sessionPinned { return .session(window.id) }
        if let ruleID { return .rule(ruleID) }
        guard window.fullscreen == nil, let placement = window.placement else { return nil }
        return .pin(PinDraft(window: window, target: placement))
    }

    // MARK: Sürükleme sırasında odak

    /// Sürükleme başlarken öndeki uygulama; harita kapanınca odak ona döner.
    private var focusOwner: NSRunningApplication?

    /// Satır ya da çip sürüklenmeye başlayınca Deskmap öndeki uygulama olur.
    /// Menü çubuğu penceresi açıkken önceki uygulama önde kalır (pencere
    /// etkinleştirmeyen paneldir); o uygulamanın penceresi başka ekranın
    /// görünen masaüstüne taşınınca macOS odağı o pencereye verir ve harita
    /// kapanır. Taşınan pencerenin uygulaması önde değilken bu olmaz.
    func holdFocusForDrag() {
        let front = NSWorkspace.shared.frontmostApplication
        guard front != .current else { return }
        focusOwner = front
        NSRunningApplication.current.activate(options: [])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Harita kapandı: öne biz geçtiysek ve hâlâ öndeysek (kullanıcı başka
    /// uygulamaya tıklamadıysa) önceki uygulama yeniden öne alınır.
    func releaseFocus() {
        guard let owner = focusOwner else { return }
        focusOwner = nil
        if NSWorkspace.shared.frontmostApplication == .current, !owner.isTerminated {
            owner.activate()
        }
    }

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
