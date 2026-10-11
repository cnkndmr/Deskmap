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
    /// Açık alt panel; nil = kapalı. Bir panel açılınca ⌘-seçim düşer:
    /// seçim varken ayrıntı sütunu toplu pinleme çubuğunu gösterir, açılan
    /// panel görünmezdi (⌘-tıklama önce paneli kapatır, sonra seçer).
    @Published var panel: BottomPanel? {
        didSet { if panel != nil, !selection.isEmpty { selection = [] } }
    }
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
    /// Ayrıntı sütununda "Gelişmiş" bölümü açık mı; paneller arasında korunur.
    @Published var showAdvanced = false
    /// Haritada masaüstü önizlemeleri (Görsel) açık mı; kullanıcı tercihi,
    /// kalıcı (Shots modunda yazılmaz).
    @Published var visualMap: Bool = UserDefaults.standard.object(forKey: "visualMap") as? Bool ?? true {
        didSet {
            if persistsPreferences { UserDefaults.standard.set(visualMap, forKey: "visualMap") }
        }
    }
    /// false: tercihler diske yazılmaz (Shots modu).
    var persistsPreferences = true
    /// Haritada pencere arama metni; boşsa arama yok.
    @Published var search = ""

    /// Pencere aramaya uyuyor mu (saf): uygulama adı ya da başlıkta geçen,
    /// büyük/küçük harf ve aksan duyarsız. Boş sorgu her şeye uyar.
    nonisolated static func matches(query: String, appName: String, title: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return appName.range(of: q, options: options) != nil
            || title.range(of: q, options: options) != nil
    }

    /// Arama sürerken bu öğe soluk mu (uymuyor), vurgulu mu (uyuyor)?
    func searchLook(appName: String, title: String) -> (dimmed: Bool, highlighted: Bool) {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return (false, false) }
        let hit = Self.matches(query: search, appName: appName, title: title)
        return (!hit, hit)
    }
    /// Son fare basışında ⌘ basılı mıydı; basış anında yerel izleyiciyle
    /// kaydedilir (dokunma işlendiğinde ⌘ bırakılmış olabilir).
    private(set) var commandAtMouseDown = false
    /// Son fare basışının tıklama sayısı (1 tek, 2 çift tıklamanın ikincisi).
    private(set) var clickCountAtMouseDown = 1
    private var mouseMonitor: Any?

    func watchCommandClicks() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.commandAtMouseDown = event.modifierFlags.contains(.command)
            self?.clickCountAtMouseDown = event.clickCount
            return event
        }
    }

    /// İlk tıklamadan önceki panel ve seçim; çift tıklamanın ikincisi geri yükler.
    private var beforeClick: (panel: BottomPanel?, source: CGWindowID?, selection: Set<CGWindowID>)?

    /// Satır ve çip tıklaması. Tek tıklama hemen işlenir (çift tıklama
    /// süresini beklemez); çift tıklamanın ikinci basışı ilk tıklamanın
    /// panel/seçim değişikliğini geri alır, sonra çift tıklama işini yapar.
    /// Üçüncü ve sonraki basışlar yok sayılır.
    func handleClick(single: () -> Void, double: () -> Void) {
        handleClick(count: clickCountAtMouseDown, single: single, double: double)
    }

    func handleClick(count: Int, single: () -> Void, double: () -> Void) {
        switch count {
        case 1:
            beforeClick = (panel, panelSourceWindowID, selection)
            single()
        case 2:
            if let before = beforeClick {
                panel = before.panel
                panelSourceWindowID = before.source
                selection = before.selection
            }
            beforeClick = nil
            double()
        default:
            break
        }
    }

    /// Daraltılmış grup anahtarlarını masaüstü yeniden numaralanınca taşır
    /// (saf): `map` (ekran, masaüstü) için yeni yeri verir, nil = anahtar
    /// düşer. Biçimi bozuk anahtar olduğu gibi kalır.
    nonisolated static func remapCollapsed(
        _ keys: Set<String>, _ map: (String, Int) -> (screen: String, desktop: Int)?
    ) -> Set<String> {
        Set(keys.compactMap { key in
            let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let desktop = Int(parts[1]) else { return key }
            guard let next = map(String(parts[0]), desktop) else { return nil }
            return "\(next.screen)|\(next.desktop)|\(parts[2])"
        })
    }

    func remapCollapsed(_ map: (String, Int) -> (screen: String, desktop: Int)?) {
        let next = Self.remapCollapsed(collapsed, map)
        if next != collapsed { collapsed = next }
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
