import AppKit
import Combine

/// Yönlendirme motoru. Pencere olaylarında (yeni pencere, başlık, odak,
/// masaüstü geçişi) ve yedek olarak düzenli aralıklarla açık pencereleri
/// tarar; kurala uyanları doğru ekranın doğru masaüstüne taşıyıp düzene
/// oturtur. Düzen, pencere gerçekten hedefe oturana kadar yeniden denenir.
///
/// Tarama arka planda çalışır; arayüz yalnızca özet durumu görür.
@MainActor
final class Router: ObservableObject {

    /// Düzenin uygulandığı çözülmüş hedef: mod + hedef (ekran, masaüstü,
    /// düzen). Hangi kuralın eşleştiği bilerek dahil değil.
    struct AppliedTarget: Equatable, Sendable {
        let mode: Mode
        let destination: Destination
    }

    struct AppliedEntry: Equatable, Sendable {
        let target: AppliedTarget
        /// Kaydı yazan taramanın yönlendirme nesli.
        let generation: UInt64
    }

    /// Düzen bu hedef için yeniden verilmeli mi (saf): pencerenin son
    /// uygulanan hedefi farklıysa ya da hiç yoksa.
    /// Düzenin ekranın kullanılabilir alanındaki hedef çerçevesi (AX
    /// koordinatları, üst kenar y = 0). Düzen oranları AX alanına göredir:
    /// pin yakalama (`WindowSnapshot.currentLayout`), elle taşıma ve burası
    /// aynı alanı kullanır. Alan önce Cocoa'dan çevrilir; oran Cocoa alanına
    /// uygulanıp sonra çevrilirse dikey eksen ters döner (y = 0 alta iner,
    /// "Üst yarı" alta, "Alt yarı" üste giderdi).
    nonisolated static func targetFrame(for layout: WindowLayout, on screen: ScreenInfo,
                                        screens: [ScreenInfo]) -> CGRect {
        layout.rect(in: targetArea(on: screen, screens: screens))
    }

    /// "Yalnız masaüstü" pininde verilecek düzen (saf): pencere hedef
    /// ekrandaysa (ya da çerçevesi bilinmiyorsa) nil, dokunulmaz; başka
    /// ekrandaysa orada kapladığı oranla hedef ekrana taşınır.
    nonisolated static func desktopOnlyLayout(frame: CGRect?, target: ScreenInfo,
                                              screens: [ScreenInfo]) -> WindowLayout? {
        guard let frame else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let source = screens.first {
            Coordinates.axRect(fromCocoa: $0.frame, screens: screens).contains(center)
        }
        guard let source, source.id != target.id else { return nil }
        return WindowLayout(frame: frame, in: targetArea(on: source, screens: screens))
    }

    /// Ekranın kullanılabilir alanı AX koordinatlarında (sol üst tabanlı).
    nonisolated static func targetArea(on screen: ScreenInfo, screens: [ScreenInfo]) -> CGRect {
        Coordinates.axRect(fromCocoa: screen.visibleFrame, screens: screens)
    }

    nonisolated static func needsLayout(applied: AppliedEntry?, target: AppliedTarget) -> Bool {
        applied?.target != target
    }

    /// Tarama sonucundaki düzen kayıtlarını sınırlara göre süzer (saf):
    /// kaydı yazan tarama, pencere (ya da hepsi) unutulduktan önce
    /// başladıysa kayıt atılır.
    nonisolated static func acceptApplied(
        _ entries: [CGWindowID: AppliedEntry], floors: [CGWindowID: UInt64], globalFloor: UInt64
    ) -> [CGWindowID: AppliedEntry] {
        entries.filter { id, entry in
            entry.generation >= max(globalFloor, floors[id] ?? 0)
        }
    }

    struct Placement: Equatable, Hashable {
        let screen: String
        let desktop: Int
    }

    /// Tam ekran bir space'in haritadaki yeri: hangi ekranda, hangi space
    /// ve kendisinden önce kaç normal masaüstü var (Mission Control sırası).
    struct FullscreenSlot: Equatable, Hashable {
        let screen: String
        let space: UInt64
        /// 0 = ilk masaüstünden önce, n = n. masaüstünden sonra.
        let afterDesktop: Int
        /// Aynı `afterDesktop` içinde soldan sağa sıra.
        let order: Int
    }

    /// Arayüzde gösterilen pencere anlık görüntüsü; her taramada yenilenir.
    struct WindowSnapshot: Identifiable, Equatable, Hashable {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let bundleID: String
        let title: String
        /// Bulunduğu ekran ve masaüstü (tam ekran ya da bilinmiyorsa nil).
        let placement: Placement?
        /// AX koordinatlarında (sol üst köşe tabanlı) çerçeve.
        let frame: CGRect?
        let isMinimized: Bool
        /// Tam ekran (ya da Split View) space'indeyse haritadaki yeri.
        var fullscreen: FullscreenSlot? = nil
        /// Gösterdiği belgenin dosya yolu (AXDocument); yoksa nil.
        var document: String? = nil
        /// Safari: araç çubuğundaki sekme grubu adı; "" = grupsuz pencere,
        /// nil = okunamadı ya da Safari değil.
        var tabGroup: String? = nil
    }

    struct Status: Equatable {
        var routedWindows = 0
        var lastAction: String?
        var lastActionAt: Date?
        /// Accessibility'ye yanıt vermediği için geçici olarak atlanan uygulamalar.
        var unresponsive: [String] = []
    }

    @Published private(set) var status = Status()

    /// "Son hareketler" listesinin bir satırı: Deskmap'in bir pencereyi
    /// masaüstüne taşıdığı an.
    struct ActionLogEntry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let text: String
    }

    /// Son taşımalar, en yenisi başta (en çok `actionLogLimit`). Her taşıma
    /// için yalnız ilk deneme yazılır; tekrar denemeler listeyi doldurmaz.
    @Published private(set) var actionLog: [ActionLogEntry] = []
    nonisolated static let actionLogLimit = 50

    /// Günlüğe yeni taşımaları ekler (saf birleştirme `mergedLog`'da).
    func recordActions(_ texts: [String], at date: Date = Date()) {
        guard !texts.isEmpty else { return }
        actionLog = Self.mergedLog(actionLog, adding: texts, at: date)
    }

    /// En yeni başta, sınırda kırpılmış günlük (saf). Aynı taramadaki
    /// taşımalar sırayla eklenir: sonuncusu en üstte.
    nonisolated static func mergedLog(_ log: [ActionLogEntry], adding texts: [String],
                                      at date: Date) -> [ActionLogEntry] {
        let fresh = texts.reversed().map { ActionLogEntry(date: date, text: $0) }
        return Array((fresh + log).prefix(actionLogLimit))
    }
    /// Son taramada görülen pencereler (uygulama adı, sonra kimlik sırasında).
    @Published private(set) var windows: [WindowSnapshot] = []
    /// Oturum pinleri: pencere kimliğine (CGWindowID) bağlı, diske
    /// yazılmayan hedefler. Başlığı değişmeyen ama farklı pencereler açan
    /// uygulamalar için "sadece bu pencere" seçeneği. Pencere kapanınca
    /// (birkaç tarama boyunca görünmeyince) kendiliğinden silinir; moddan
    /// bağımsızdır, hedef ekran bağlı değilse o an uygulanmaz.
    @Published private(set) var sessionPins: [CGWindowID: Destination] = [:]
    /// Pencerelerin başlık/belge geçmişi ("bu pencere" pininin anahtarı).
    /// Belgesi oynayan uygulamalar kalıcıdır (UserDefaults).
    @Published private(set) var identity = WindowIdentity.Observations(
        volatileDocumentApps: Set(UserDefaults.standard.stringArray(
            forKey: Router.volatileDocumentAppsKey) ?? []),
        stableDocumentApps: Set(UserDefaults.standard.stringArray(
            forKey: Router.stableDocumentAppsKey) ?? []))
    nonisolated static let volatileDocumentAppsKey = "volatileDocumentApps"
    nonisolated static let stableDocumentAppsKey = "stableDocumentApps"

    private func observeIdentity(_ snapshots: [WindowSnapshot]) {
        var next = identity
        next.observe(snapshots)
        guard next != identity else { return }
        if next.volatileDocumentApps != identity.volatileDocumentApps {
            UserDefaults.standard.set(next.volatileDocumentApps.sorted(),
                                      forKey: Self.volatileDocumentAppsKey)
        }
        if next.stableDocumentApps != identity.stableDocumentApps {
            UserDefaults.standard.set(next.stableDocumentApps.sorted(),
                                      forKey: Self.stableDocumentAppsKey)
        }
        identity = next
    }
    /// Serbest hareket: pencere → iznin bittiği an. Bu süre boyunca motor
    /// pencereyi masaüstüne geri taşımaz, düzen vermez; süre bitince pin
    /// yeniden uygulanır (pencere yerine döner). Diske yazılmaz.
    @Published private(set) var freeMoves: [CGWindowID: Date] = [:]
    /// İzin verildiği andaki pin: kural kimliği (oturum pininde
    /// `Routing.sessionRuleID`), hedefi ve pencerenin o anki kimliği
    /// (uygulama + başlık). Her taramadan önce pencereyi yöneten pin,
    /// SAKLANAN başlıkla yeniden seçilir: sekme/başlık değişince izin düşmez;
    /// ama pin kalkar, taşınır, düzeni değişir, daha özgül bir pin gelir,
    /// parçaları düzenlenir ya da profil/mod değişirse izin biter ve yeni
    /// hedef süre dolmasını beklemeden uygulanır.
    struct FreeGrant: Equatable {
        var ruleID: String
        var destination: Destination
        var bundleID: String = ""
        var appName: String = ""
        var title: String = ""
        var document: String? = nil
        /// İzin verildiği kurulum; kurulum değişince (monitör takıldı ya
        /// da çıkarıldı) hedef aynı olsa da izin biter.
        var mode: Mode = .docked
    }
    private var freeTargets: [CGWindowID: FreeGrant] = [:]
    /// Bağlı ekranlardaki gerçek masaüstü sayıları; `windows`'tan bağımsız
    /// yayınlanır (pencere listesi değişmeden eklenen masaüstü de haritaya
    /// yansısın).
    @Published private(set) var desktopCounts: [String: Int] = [:]
    /// Bu oturumda denenmiş plan/silme hedefleri (başarısızlık döngüsü olmasın).
    private var plannedAttempts = PlannedAttempts()
    private static let maxPlannedCreations = 8
    /// Masaüstü taşımasının doğrulanmış durumu; devre kesici açıksa
    /// (`degraded`) taşıma durur, ekran ve düzen sürer.
    /// Doğrulanmamış macOS'ta (`MoveSupport.unverified`) kullanıcı "Yine de
    /// dene" diyene kadar taşıma bekletilir (`held`).
    @Published private(set) var moveHealth = MoveHealth(held: Router.holdsMovesAtLaunch)
    /// Yönlendirme nesli: kural, ekran, duraklatma ya da oturum pini
    /// değişince artar. Arka planda süren tarama her yan etkiden
    /// (`AX.setFrame`, `sky.move`) önce nesline bakar; eskimişse durur (P0-2).
    nonisolated let generation = RoutingGeneration()
    /// Yapılmış ama henüz doğrulanmamış taşımalar (pencere → hedef space).
    private var pendingMoves: [CGWindowID: PendingMove] = [:]
    /// Oturum pinlerinin diske yazılan kaydı (pencere yaşadığı sürece
    /// uygulama yeniden başlasa da geri yüklenir).
    private var sessionRecords: [CGWindowID: SessionPin] = [:]
    /// Oturum pini olan pencerenin pencere sunucusunda art arda kaç
    /// taramada görülmediği.
    private var sessionMisses: [CGWindowID: Int] = [:]
    /// Bu kadar ardışık taramada pencere sunucusunda da yoksa pin düşer.
    private static let sessionMissLimit = 3
    /// Oturum pinleri dosyası; pencere numarası + sahip pid ile eşlenir.
    /// Pencere numaraları ve pid'ler yeniden başlatmada değiştiği için
    /// eski kayıtlar açılışta kendiliğinden elenir.
    static let sessionFileURL = Store.directoryURL.appendingPathComponent("session-pins.json")
    /// Son görülen ekran → masaüstü kimlikleri; Deskmap kapalıyken
    /// Mission Control'de silinen masaüstü açılışta bununla yakalanır.
    static let reopenFileURL = Store.directoryURL.appendingPathComponent("reopen.json")
    /// Kural kimliği → pencere kapalıyken yeniden açmak için son görülen
    /// dosya/klasör/sayfa (bkz. `Reopen`).
    @Published private(set) var reopenTargets: [String: ReopenTarget] = [:]
    /// Pencere başına son okuma: başlık değişince ya da süre dolunca yeniden.
    private var reopenReads: [CGWindowID: (title: String, at: Date)] = [:]
    private static let reopenRefresh: TimeInterval = 60
    /// Yeniden açma okumaları ayrı kuyrukta: tarama kuyruğunu asla bekletmesin
    /// (Finder'ın Recents ağacında dakikalarca takılıp ekran değişimini
    /// işletmemişti, 08.10). Önceki tur bitmeden yenisi başlamaz.
    private let reopenQueue = DispatchQueue(label: "deskmap.reopen", qos: .background)
    private var reopenBusy = false
    static let desktopSpacesFileURL = Store.directoryURL.appendingPathComponent("desktop-spaces.json")

    /// Diske yazılan oturum pini kaydı.
    struct SessionPin: Codable, Equatable {
        var windowID: CGWindowID
        var pid: pid_t
        var bundleID: String
        var appName: String
        var title: String
        var destination: Destination
    }

    private let store: Store
    private let screens: ScreenService
    private let events: WindowEvents
    /// Pencere ekran değiştirince kullanıcı komutları (`hooks.json`).
    private let screenHooks = ScreenHooks(url: Store.directoryURL.appendingPathComponent("hooks.json"))
    /// Pencerelerin son görüldüğü ekran (ekran değişimi kancası için).
    private var screenMemory = ScreenMemory()
    private let queue = DispatchQueue(label: "deskmap.router", qos: .utility)
    // nonisolated(unsafe): ikisi de yalnızca init'te (ana aktör) doldurulur,
    // deinit'te kapatılır; `Timer` ve gözlemci belirteci Sendable olmadığı
    // için deinit erişimi başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    nonisolated(unsafe) private var sleepTokens: [NSObjectProtocol] = []
    nonisolated(unsafe) private var lockToken: NSObjectProtocol?

    /// Pencere başına düzenin en son uygulandığı çözülmüş hedef ve nesil.
    /// Düzen hedef başına bir kez verilir; kullanıcı pencereyi sonradan elle
    /// taşırsa, başka bir kural aynı hedefe çıksa da yerinden oynatılmaz.
    /// Hedef değişip geri dönerse (A→B→A) yeniden verilir (B7).
    private var applied: [CGWindowID: AppliedEntry] = [:]
    /// Pencere başına yapışkan kural bağı (docs/bug-tables.md §B): başlık
    /// değişse de pencere kapanana kadar sürer. Diske yazılmaz.
    private var bindings: [CGWindowID: Routing.Binding] = [:]
    /// Bağların verildiği profil. Bağ kural kimliğine bakar; başka profilde
    /// o kimlik yok ve bağ "pin silindi" diye pencereyi eski yerinde
    /// tutardı. Profil değişince bağlar baştan kurulur.
    private var bindingsProfileID: String?
    /// Son taramada pencerenin pininden kullanılan yer (`status.json`
    /// `place`): "1", "2" … (sıra), "fallback" (K4) ya da "untouched".
    private(set) var placeStatus: [CGWindowID: String] = [:]
    /// Tarama sürerken verilen bağlar (pin kaldırma); sonuç gelince
    /// taramanın eski bağlarının üstüne yazılır.
    private var bindingOverrides: [CGWindowID: Routing.Binding] = [:]
    /// Pencerenin ilk görüldüğü an (genel başlık beklemesi için). İlk
    /// taramada görülenler beklemez.
    private(set) var firstSeen: [CGWindowID: Date] = [:]
    private var sweptAny = false
    /// Son taramanın seçim durumu; arayüz "Neden burada?" için aynısını kullanır.
    @Published private(set) var routingContext = Routing.Context()
    /// Arayüzün seçimi için bağlam: yalnız canlı modda (öbür modda bağ yok).
    func context(for mode: Mode) -> Routing.Context? {
        mode == screens.mode ? routingContext : nil
    }
    /// Pencere başına "bu nesilden eski düzen kayıtları geçersiz" sınırı:
    /// tarama sürerken unutulan pencerenin eski kaydı sonuçla geri gelmesin.
    private var appliedFloor: [CGWindowID: UInt64] = [:]
    private var appliedGlobalFloor: UInt64 = 0
    /// (pencere, hedef) başına kaç kez düzen / masaüstü taşıması denendi;
    /// uygulama kabul etmezse belirli sayıdan sonra vazgeçilir.
    private var attempts: [String: Int] = [:]
    /// Uygulamanın gerçekten reddettiği (denemeyle görülen) boyut,
    /// "<pencere>|refused|<hedef>" anahtarıyla; sabit boyutlu ve oranlı
    /// düzende. Düzen belleği unutulsa da (yeniden uygulama) kalır: pencere
    /// zaten o boyutla doğru noktadaysa önce yanlış yere sıçratılmaz
    /// (`WindowLayout.holdsRefused`). Kapanan pencereyle budanır.
    private var refusedSizes: [String: CGSize] = [:]
    /// Masaüstü taşıması anahtarı başına son deneme zamanı; sınıra varılmış
    /// taşıma bir süre sonra yeniden tur alır (`Routing.recordMoveAttempt`).
    /// `attempts` ile birlikte budanır.
    private var lastAttempts: [String: Date] = [:]
    private var isSweeping = false
    private var sweepRequested = false
    /// Ekranlar ya da sistem uyurken tarama yapılmaz; uyanınca hemen taranır.
    private var isPaused = false
    /// Duraklamanın başladığı an (emniyet sürdürmesi için).
    private var pausedAt: Date?
    /// Uyanma bildirimi gelmezse (ör. `willSleep` sonrası uyku iptal oldu)
    /// zamanlayıcı, ana ekran uyanıksa ve duraklama bu kadar eskiyse taramayı
    /// kendisi sürdürür. Uykuya girerken bildirim sırasıyla çekişmesin diye
    /// birkaç saniye.
    nonisolated static let pauseSafetyDelay: TimeInterval = 5
    /// Tarama sürerken gelen "düzen belleğini unut" istekleri: tarama
    /// bitince sonucun üstüne uygulanır; yoksa taramanın döndürdüğü eski
    /// küme bu istekleri ezerdi (ör. "Yeniden yerleştir" düğmesi).
    private var invalidatedPrefixes: Set<String> = []
    private var invalidateAll = false
    private var followUp: Task<Void, Never>?
    /// Son tam taramanın başladığı an ve son zamanlayıcı turunda okunan
    /// pencere sunucusu imzası (`tick`).
    private var lastSweepAt = Date.distantPast
    private var lastSignature: AX.WindowServerSignature?
    /// Taramaya bağlı en yakın son tarih (`nextSweepDeadline`): bu an
    /// geldiyse zamanlayıcı turu, imza değişmese de tam tarama yapar.
    private var sweepDeadline: Date?
    /// Harita (menü çubuğu penceresi) ekranda mı; RootView bildirir.
    private var mapVisible = false
    /// Shots modu: tarama hiç yapılmaz (pencereler sabit verilir).
    private var isDemo = false
    /// Zamanlayıcı aralığı.
    /// 5 sn: turun kendisi (pencere sunucusu imzası) boşta en büyük kalemdi;
    /// pencere olayları taramayı zaten beklemeden tetikler.
    nonisolated static let tickInterval: TimeInterval = 5
    /// Hiçbir şey değişmese ve son tarih olmasa da bu kadar sürede bir tam
    /// tarama yapılır (gözlemcisi takılamamış uygulamanın başlık değişimi).
    nonisolated static let idleSweepInterval: TimeInterval = 120

    init(store: Store, screens: ScreenService) {
        self.store = store
        self.screens = screens
        // Ayrıca ayarlanmamış bütün AX öğeleri için varsayılan yanıt süresi
        // (yoksa ~6 sn; donmuş bir uygulama taramayı o kadar bekletirdi).
        // WindowEvents'ten önce: ilk gözlemci kayıt turu pencere öğelerine
        // bu süreyle sorar.
        AX.setGlobalTimeout(1.0)
        self.events = WindowEvents()
        let sky = SkyLight.shared
        Log.skylight.notice("""
            SkyLight \(sky.canRead ? "available" : "unavailable", privacy: .public); \
            desktop move path: \(sky.movePath, privacy: .public); \
            support: \(String(describing: sky.moveSupport), privacy: .public)\
            \(self.moveHealth.state == .held ? " (held until the user tries)" : "", privacy: .public)
            """)
        loadSessionPins()
        loadDesktopState()
        loadReopenTargets()
        // Arka plan uzak taraması yeni pencere bulunca bir tur (perf §3.1);
        // zamanlayıcı turu sunucu imzası değişmedikçe taramaz.
        AX.onRemoteFound = { [weak self] in
            Task { @MainActor in
                self?.countSweepReason("remote-found")
                self?.sweep()
            }
        }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Sistem zamanlayıcıları gruplayabilsin (güç tüketimi); 2 sn ± 0,5 sn yeter.
        timer.tolerance = 1
        self.timer = timer

        // Pencere olayları: art arda gelenleri tek taramada topla.
        // Başlık değişimi (terminal, tarayıcı sekmesi) sürekli gelir; yalnız
        // o uygulama için başlığa bakan bir kural varsa ya da harita açıksa
        // önemli (`titleMatters`), 1 sn toplanır. Diğer olaylar 80 ms.
        events.titleChanged
            .filter { [weak self] pid in self?.titleMatters(pid: pid) ?? false }
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.countSweepReason("event:title")
                self?.sweep()
            }
            .store(in: &cancellables)
        // Sürükleme sürerken taşınma olayı sürekli gelir; bırakınca bir tarama
        // (ekran değişimi kancası beklemeden tetiklensin).
        events.moved
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.countSweepReason("event:moved")
                self?.sweep()
            }
            .store(in: &cancellables)
        events.changed
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] name in
                self?.countSweepReason("event:\(name)")
                self?.sweep()
            }
            .store(in: &cancellables)

        // Ekranlar yatışınca plan uygulanır (§P.1); taramalar ondan sonra.
        screens.settled
            .sink { [weak self] in
                self?.handleSettled()
                self?.reapplyAll()
            }
            .store(in: &cancellables)

        // Ekran değişimi yatışmadan da süren taramanın yan etkileri durmalı;
        // ilk bildirimde son kararlı durum geçişin "önce"si olur.
        screens.$screens
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.generation.advance()
                self?.beginTransition(reason: "display")
            }
            .store(in: &cancellables)

        // Profil değişince hedef profilin planı uygulanır, silme yok (S1).
        store.$document
            .map(\.activeProfileID)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPlanNow(reason: "profile switch") }
            .store(in: &cancellables)

        // Onay bekleyen bir monitör rolü onaylandı (kart menüsü, `deskmap
        // screen-role`): o rolün planı ve kuralları şimdi uygulanır. Rol
        // ataması değiştiyse (takas) yatışma zaten geçiş başlatır; aynı kaldıysa
        // (yalnız onay) ekran bildirimi gelmez, plan buradan uygulanır.
        store.$document
            .map(\.displayRoles)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.followHeldRoles() }
            .store(in: &cancellables)
        lastHeldRoles = screens.heldRoles

        // @Published willSet'te yayar: tarama bir sonraki turda, yeni kurallar
        // yazıldıktan sonra başlasın (yoksa eski kural listesini okurdu).
        store.$document
            .map(\.rules)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reapplyAll() }
            .store(in: &cancellables)

        // Duraklat / sürdür (menü, deskmap://pause).
        store.$document
            .map(\.enabled)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.generation.advance() }
            .store(in: &cancellables)

        // Ekranlar / sistem uyurken tarama durur (pencere sunucusu ve
        // uygulamalar yanıt vermez, boşuna IPC); uyanınca hemen bir tur.
        let center = NSWorkspace.shared.notificationCenter
        // `Notification` Sendable değil; ana aktöre yalnızca adı taşınır.
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            sleepTokens.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                let reason = note.name.rawValue
                Task { @MainActor in self?.setPaused(true, reason: reason) }
            })
        }
        // Ekran kilitlenince "kilide kadar" serbest izinleri biter.
        lockToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in self?.endFreeMovesUntilLock(reason: "screen locked") }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            sleepTokens.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                let reason = note.name.rawValue
                Task { @MainActor in self?.setPaused(false, reason: reason) }
            })
        }
    }

    /// Shots modu (`--shots`): tarama yok, zamanlayıcı kurulmaz, AX/SkyLight
    /// çağrılmaz, oturum pinleri diskten okunmaz. `windows`, `sessionPins`,
    /// `status` dışarıdan sabit verilir; bunların dışındaki bütün alanlar
    /// bildirimlerindeki varsayılanı korur (boş/nil). Üretim `init()`'i
    /// değişmez.
    init(store: Store, screens: ScreenService, demoWindows: [WindowSnapshot],
         demoSessionPins: [CGWindowID: Destination] = [:], demoStatus: Status = Status()) {
        self.store = store
        self.screens = screens
        self.events = WindowEvents(demo: true)
        self.isDemo = true
        self.windows = demoWindows
        self.sessionPins = demoSessionPins
        self.status = demoStatus
    }

    /// Yalnız Shots modunda: demo pencere listesini değiştirir (demo
    /// dizisinde pencereler "taşınır"). Üretimde hiçbir şey yapmaz.
    func replaceDemoWindows(_ windows: [WindowSnapshot]) {
        guard isDemo else { return }
        self.windows = windows
    }

    /// Yalnız Shots modunda: ekran başına gerçek masaüstü sayısı (durum
    /// satırı "yerinde değil" sayabilsin). Üretimde hiçbir şey yapmaz.
    func replaceDemoDesktopCounts(_ counts: [String: Int]) {
        guard isDemo else { return }
        desktopCounts = counts
    }

    deinit {
        timer?.invalidate()
        followUp?.cancel()
        for token in sleepTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let lockToken { DistributedNotificationCenter.default().removeObserver(lockToken) }
    }

    private func setPaused(_ paused: Bool, reason: String) {
        // Uykudan önce kararlı durum yazılır; uyanınca kısa süre kaybolan
        // masaüstü silme sayılmaz (P.2).
        if paused, reason == NSWorkspace.willSleepNotification.rawValue,
           transition == nil, !screens.isSettling, desktopState != nil {
            commitSnapshot()
        }
        if !paused, reason == NSWorkspace.didWakeNotification.rawValue {
            extendQuietWindow(seconds: 10)
            lastWakeAt = Date()
        }
        guard paused != isPaused else { return }
        isPaused = paused
        generation.advance()
        pausedAt = paused ? Date() : nil
        Log.screens.notice("""
            Sweep \(paused ? "paused" : "resumed", privacy: .public) (\(reason, privacy: .public))
            """)
        if !paused { sweep() }
    }

    /// Zamanlayıcı turu (2 sn). Pencere olayları taramayı zaten kendileri
    /// tetikler; bu tur yalnızca olayın kaçırdığını yakalar. Her turda
    /// bütün uygulamalara AX ile sormak boşta sürekli CPU harcıyordu; artık
    /// önce pencere sunucusunun ucuz imzasına bakılır, tam tarama yalnızca
    /// imza değiştiyse, harita açıksa, taramaya bağlı bir son tarih
    /// geldiyse ya da `idleSweepInterval` dolduysa.
    private func tick() {
        events.refreshIfDue()
        resumeIfStuckPaused()
        expireFreeMoves(now: Date())
        completeMigrationIfOverdue(now: Date())
        guard !isPaused else { return }
        let signature = AX.windowServerSignature()
        let changed = signature == nil || signature != lastSignature
        lastSignature = signature
        let now = Date()
        if Self.shouldSweepOnTick(signatureChanged: changed, mapVisible: mapVisible,
                                  deadline: sweepDeadline, now: now,
                                  sinceLastSweep: now.timeIntervalSince(lastSweepAt)) {
            countSweepReason(changed ? "signature" : mapVisible ? "map"
                             : (sweepDeadline.map { now >= $0 } ?? false) ? "deadline" : "idle")
            sweep()
        }
        logSweepReasonsIfDue(now: now)
    }

    /// Tanı: taramaları kim tetikliyor (boşta CPU ölçümü için). Beş
    /// dakikada bir, tarama olduysa tek satır.
    private var sweepReasons: [String: Int] = [:]
    private var sweepReasonsSince = Date()

    private func countSweepReason(_ reason: String) {
        sweepReasons[reason, default: 0] += 1
    }

    private func logSweepReasonsIfDue(now: Date) {
        guard now.timeIntervalSince(sweepReasonsSince) >= 300 else { return }
        if !sweepReasons.isEmpty {
            let text = sweepReasons.sorted { $0.value > $1.value }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            Log.routing.notice("Sweeps in the last 5 min: \(text, privacy: .public)")
        }
        sweepReasons = [:]
        sweepReasonsSince = now
    }

    /// Bayrak `perf.sweepSignature` (PLAN-perf §5.4 adım 1). İmza yalnız
    /// zamanlayıcı turunda alınıyordu: Deskmap pencereyi geri taşıdıktan
    /// sonra kullanıcı onu bir sonraki turdan önce yine başka masaüstüne
    /// alırsa imza önceki turdakiyle aynı çıkıyor, tarama hiç başlamıyordu
    /// (gerçek Deskmap'te 9 turun 3'ünde 16 sn içinde dönmedi, ölçüldü 24.10).
    /// Açıkken her tarama imzayı kendi okuduğu ana çeker.
    nonisolated static var sweepSignature: Bool {
        UserDefaults.standard.bool(forKey: "perf.sweepSignature")
    }

    /// Tarama bitince karşılaştırma imzası (saf): taramanın başında okunan
    /// imza, turdan eski olsa bile alınır (eski imza en çok bir fazla tarama
    /// demek; değişim kaçmaz). Bayrak kapalıyken `swept` nil, tur imzası kalır.
    nonisolated static func signatureAfterSweep(
        tick: AX.WindowServerSignature?, swept: AX.WindowServerSignature?
    ) -> AX.WindowServerSignature? {
        swept ?? tick
    }

    /// Zamanlayıcı turunda tam tarama gerekli mi (saf).
    nonisolated static func shouldSweepOnTick(
        signatureChanged: Bool, mapVisible: Bool, deadline: Date?, now: Date,
        sinceLastSweep: TimeInterval
    ) -> Bool {
        if signatureChanged || mapVisible { return true }
        if let deadline, now >= deadline { return true }
        return sinceLastSweep >= idleSweepInterval
    }

    /// Taramaya bağlı en yakın son tarih (saf); yoksa nil. Her biri,
    /// imza değişmese de yeniden tam tarama gerektiren bir bekleyen iştir:
    /// - oturum pini düşme sayacı sürüyor (`sessionMissLimit`'e kadar her tur),
    /// - düzen denemesi sürüyor (`Routing.maxAttempts`'e kadar her tur),
    /// - masaüstü taşıması sürüyor (sınıra kadar her tur; sınırdaysa
    ///   son denemeden `Routing.moveRetryInterval` sonra),
    /// - AX geri çekilmesi bitiyor (uygulama yeniden taransın).
    /// "Her tur" = `now` (bir sonraki zamanlayıcı turu).
    nonisolated static func nextSweepDeadline(
        now: Date, pendingSessionMisses: Bool, attempts: [String: Int],
        lastAttempts: [String: Date], backoffEnd: Date?
    ) -> Date? {
        var deadlines: [Date] = []
        if pendingSessionMisses { deadlines.append(now) }
        for (key, count) in attempts where count > 0 {
            if Routing.isMoveKey(key) {
                if count >= Routing.maxMoveAttempts {
                    if let last = lastAttempts[key] {
                        deadlines.append(last.addingTimeInterval(Routing.moveRetryInterval))
                    }
                } else {
                    deadlines.append(now)
                }
            } else if count < Routing.maxAttempts {
                deadlines.append(now)
            }
        }
        if let backoffEnd { deadlines.append(backoffEnd) }
        return deadlines.min()
    }

    private func titleMatters(pid: pid_t) -> Bool {
        let app = AX.runningApps().first { $0.pid == pid }
        return Self.titleMatters(bundleID: app?.bundleID, appName: app?.name,
                                 rules: isPaused || !store.document.enabled ? [] : store.document.rules,
                                 mapVisible: mapVisible)
    }

    /// Başlık değişimi tarama gerektirir mi (saf): harita açıksa (liste
    /// tazelenmeli) ya da bu uygulama için başlık sözcüğü olan bir kural
    /// varsa. Uygulama bilinmiyorsa güvenli taraf: evet.
    nonisolated static func titleMatters(bundleID: String?, appName: String?, rules: [Rule],
                                         mapVisible: Bool) -> Bool {
        if mapVisible { return true }
        guard let bundleID, let appName else { return true }
        let lowered = appName.lowercased()
        return rules.contains { rule in
            (!rule.tokens.isEmpty || rule.path != nil)
                && (rule.bundleID.isEmpty ? rule.appName.lowercased() == lowered
                                          : rule.bundleID == bundleID)
        }
    }

    /// Harita açıldı / kapandı (RootView'in penceresinin görünürlüğü).
    /// Açıkken liste her turda tazelenir; açılınca hemen bir tur.
    func setMapVisible(_ visible: Bool) {
        guard visible != mapVisible else { return }
        mapVisible = visible
        if visible { sweep() }
    }

    /// Emniyet: uyanma bildirimi kaçtıysa duraklama sonsuza dek sürmesin.
    /// Zamanlayıcı her turda bakar; karar saf `shouldResumeFromPause`.
    private func resumeIfStuckPaused() {
        guard isPaused,
              Self.shouldResumeFromPause(
                pausedAt: pausedAt, now: Date(),
                displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0)
        else { return }
        setPaused(false, reason: "timer")
    }

    /// Duraklatılmış tarama sürdürülmeli mi (saf): ana ekran uyanık ve
    /// duraklama `pauseSafetyDelay`'den eski. Başlangıç bilinmiyorsa hayır.
    nonisolated static func shouldResumeFromPause(
        pausedAt: Date?, now: Date, displayAsleep: Bool
    ) -> Bool {
        guard let pausedAt, !displayAsleep else { return false }
        return now.timeIntervalSince(pausedAt) >= pauseSafetyDelay
    }

    /// Geçişin ya da planın sonunda: yeniden yerleştirme, çalışan işaret
    /// (`transitionRunning`) kalktıktan sonra. Hemen çağrılırsa tarama plan
    /// sürüyor diye yönlendirmeyi tutar ve ardından tarama gelmezdi: rol
    /// takasından ya da monitör onayından sonra pencere iki dakikalık tam
    /// taramaya dek yerinde kalıyordu (places.sh).
    private func reapplyAfterPlan() {
        DispatchQueue.main.async { [weak self] in self?.reapplyAll() }
    }

    /// Düzen belleğini sıfırlayıp bütün pencereleri yeniden yerleştirir.
    func reapplyAll() {
        generation.advance()
        appliedGlobalFloor = generation.current
        appliedFloor.removeAll()
        applied.removeAll()
        attempts.removeAll()
        lastAttempts.removeAll()
        if isSweeping { invalidateAll = true }
        sweep()
    }

    // MARK: - Taşıma doğrulaması

    /// Düşük moddan çıkış: devre kesici kapanır, bütün pencereler yeniden
    /// yerleştirilir (taşımalar yeniden doğrulanır).
    func retryMoves() {
        if moveHealth.state == .held {
            UserDefaults.standard.set(true, forKey: MoveSupport.allowUnverifiedKey)
            Log.skylight.notice("Desktop moves enabled by user on an unverified macOS")
        } else {
            Log.skylight.notice("Desktop moves re-enabled by user")
        }
        moveHealth.reset()
        pendingMoves = [:]
        reapplyAll()
    }

    nonisolated private static var holdsMovesAtLaunch: Bool {
        SkyLight.shared.moveSupport == .unverified
            && !UserDefaults.standard.bool(forKey: MoveSupport.allowUnverifiedKey)
    }

    /// Bir taşıma çağrısının sonucunu kaydeder: hemen doğrulandıysa ya da
    /// hata döndüyse devre kesiciye işlenir, yapıldıysa bekleyenlere eklenir.
    private func noteMove(window: CGWindowID, space: UInt64, result: SkyLight.MoveResult) {
        switch result {
        case .verified: recordMoveCheck(window: window, verified: true)
        case .noEffect: recordMoveCheck(window: window, verified: false)
        case .issued: pendingMoves[window] = PendingMove(space: space, issuedAt: Date())
        case .unavailable: break
        }
    }

    private func recordMoveCheck(window: CGWindowID, verified: Bool) {
        guard moveHealth.record(window: window, verified: verified) else { return }
        switch moveHealth.state {
        case .working:
            Log.skylight.notice("""
                Desktop move verified (path: \(SkyLight.shared.movePath, privacy: .public))
                """)
        case .degraded:
            pendingMoves = [:]
            Log.skylight.error("""
                Desktop moves could not be verified \(MoveHealth.failureLimit) times in a row; \
                reduced mode (path: \(SkyLight.shared.movePath, privacy: .public))
                """)
        case .unknown, .held:
            break
        }
    }

    // MARK: - Oturum pinleri

    /// Bu pencereyi (kimliğiyle) pencere kapanana kadar hedefte tutar.
    /// Kayıt diske yazılır; Deskmap yeniden başlarsa pencere hâlâ
    /// açıksa pin geri gelir.
    func pinSession(_ windowID: CGWindowID, destination: Destination) {
        // Adlı masaüstüne geçici pin o adı izler (yer önbellek).
        let destination = destination.nameID != nil ? destination
            : store.document.normalizedTarget(destination, mode: screens.mode, live: store.live)
        let snapshot = windows.first { $0.id == windowID }
        let previous = sessionRecords[windowID]
        sessionRecords[windowID] = SessionPin(
            windowID: windowID,
            pid: snapshot?.pid ?? previous?.pid ?? 0,
            bundleID: snapshot?.bundleID ?? previous?.bundleID ?? "",
            appName: snapshot?.appName ?? previous?.appName ?? "",
            title: snapshot?.title ?? previous?.title ?? "",
            destination: destination)
        sessionPins[windowID] = destination
        sessionMisses[windowID] = nil
        forgetApplied(for: windowID)
        saveSessionPins()
        sweep()
    }

    func unpinSession(_ windowID: CGWindowID) {
        guard sessionPins.removeValue(forKey: windowID) != nil else { return }
        // Pini kalkan pencere yerinde kalır: genel kural onu geri çekmez.
        if let window = windows.first(where: { $0.id == windowID }) {
            let binding = Routing.bindingAfterUnpin(
                rules: store.document.rules, mode: screens.mode, bundleID: window.bundleID,
                appName: window.appName, title: window.title, document: window.document)
            bindings[windowID] = binding
            bindingOverrides[windowID] = binding
        }
        sessionRecords[windowID] = nil
        sessionMisses[windowID] = nil
        forgetApplied(for: windowID)
        dropFreeMoves([windowID], reason: "unpinned")
        saveSessionPins()
    }

    // MARK: - Serbest hareket

    /// Panelde sunulan süreler (sn); sonuncusu `freeMoveUntilLock`.
    nonisolated static let freeMoveDurations: [TimeInterval] = [
        60, 5 * 60, 15 * 60, 30 * 60, 60 * 60, 2 * 3600, 5 * 3600, freeMoveUntilLock,
    ]

    /// Süre yerine "ekran kilitlenene kadar": izin `Date.distantFuture`'a
    /// kadar verilir, kilit bildirimiyle biter.
    nonisolated static let freeMoveUntilLock: TimeInterval = .infinity

    /// Bitiş anı "kilide kadar" izni mi (saf).
    nonisolated static func isUntilLock(_ until: Date) -> Bool { until == .distantFuture }

    /// Bu pencereler `duration` boyunca serbest: motor onları yerine
    /// döndürmez. Süren bir izin yeniden verilirse süre baştan başlar.
    /// Yalnız pinli (şu an bir hedefi olan) pencerelere verilir; hedef
    /// izinle birlikte saklanır.
    func allowFreeMove(_ windowIDs: [CGWindowID], for duration: TimeInterval) {
        guard duration > 0 else { return }
        let end = duration.isInfinite ? Date.distantFuture : Date().addingTimeInterval(duration)
        var granted = 0
        for id in windowIDs {
            guard let window = windows.first(where: { $0.id == id }),
                  let match = Routing.select(
                    rules: store.document.rules, sessionPins: sessionPins, mode: screens.mode,
                    windowID: id, bundleID: window.bundleID, appName: window.appName,
                    title: window.title, document: window.document, context: routingContext)
            else { continue }
            freeMoves[id] = end
            freeTargets[id] = FreeGrant(ruleID: match.ruleID, destination: match.destination,
                                        bundleID: window.bundleID, appName: window.appName,
                                        title: window.title, document: window.document,
                                        mode: screens.mode)
            // Yarım kalmış taşıma/düzen denemeleri izin boyunca donup
            // zamanlayıcıyı her turda tam taramaya zorlamasın.
            dropAttempts(for: id)
            granted += 1
        }
        guard granted > 0 else { return }
        // Süren taramanın bu pencereleri geri taşıması kesilsin; yeni tarama
        // taramaya bağlı son tarihi de yeniden hesaplar.
        generation.advance()
        Log.routing.notice("Free move: \(granted) window(s) for \(duration.isInfinite ? "until lock" : "\(Int(duration)) s", privacy: .public)")
        sweep()
    }

    /// Süren izni `duration` kadar uzatır; izni olmayan ya da süresi
    /// dolmuş pencereye yeni izin vermez.
    func extendFreeMove(_ windowIDs: [CGWindowID], by duration: TimeInterval) {
        let now = Date()
        for id in windowIDs {
            guard let until = freeMoves[id], until > now, !Self.isUntilLock(until) else { continue }
            freeMoves[id] = until.addingTimeInterval(duration)
        }
    }

    /// İzni hemen bitirir; pin yeniden uygulanır (masaüstü ve düzen).
    func endFreeMove(_ windowIDs: [CGWindowID]) {
        var ended = false
        for id in windowIDs where freeMoves.removeValue(forKey: id) != nil {
            freeTargets[id] = nil
            forgetApplied(for: id)
            ended = true
        }
        if ended { sweep() }
    }

    /// İzni düşürür (pin kalktı ya da değişti). Düzen belleği de unutulur:
    /// pin aynı hedefle geri gelirse düzen de yeniden verilir.
    private func dropFreeMoves(_ windowIDs: [CGWindowID], reason: String) {
        var dropped = 0
        for id in windowIDs where freeMoves.removeValue(forKey: id) != nil {
            freeTargets[id] = nil
            forgetApplied(for: id)
            dropped += 1
        }
        if dropped > 0 {
            Log.routing.notice("Free move ended (\(reason, privacy: .public)): \(dropped) window(s)")
        }
    }

    /// Her taramadan önce (ana aktör): izin verilen pin hâlâ aynı mı?
    private func validateFreeMoves() {
        guard !freeTargets.isEmpty else { return }
        let rules = store.document.rules
        let mode = screens.mode
        let stale = freeTargets.filter { id, grant in
            !Self.freeMoveHolds(grant, windowID: id, rules: rules,
                                sessionPins: sessionPins, mode: mode)
        }.map(\.key)
        dropFreeMoves(stale, reason: "pin changed")
    }

    /// İzin hâlâ geçerli mi (saf): izin anındaki başlıkla bugün seçilen pin
    /// (oturum pini önce) aynı kural ve aynı hedef mi?
    nonisolated static func freeMoveHolds(
        _ grant: FreeGrant, windowID: CGWindowID, rules: [Rule],
        sessionPins: [CGWindowID: Destination], mode: Mode
    ) -> Bool {
        guard mode == grant.mode, let match = Routing.select(
            rules: rules, sessionPins: sessionPins, mode: mode, windowID: windowID,
            bundleID: grant.bundleID, appName: grant.appName, title: grant.title,
            document: grant.document)
        else { return false }
        return match.ruleID == grant.ruleID && match.destination == grant.destination
    }

    /// "Kilide kadar" izinleri bitirir (kilit bildirimi ya da turda kilit
    /// görülürse); süreli izinler sürer.
    func endFreeMovesUntilLock(reason: String) {
        let ids = freeMoves.filter { Self.isUntilLock($0.value) }.map(\.key)
        guard !ids.isEmpty else { return }
        Log.routing.notice("Free move ended (\(reason, privacy: .public)): \(ids.count) window(s)")
        endFreeMove(ids)
    }

    /// Süresi dolan izinleri düşürür (zamanlayıcı turu). Bildirim kaçarsa
    /// kilitli ekran da "kilide kadar" izinleri bitirir.
    private func expireFreeMoves(now: Date) {
        if Self.screenIsLocked() { endFreeMovesUntilLock(reason: "screen locked (poll)") }
        let expired = freeMoves.filter { $0.value <= now }.map(\.key)
        guard !expired.isEmpty else { return }
        Log.routing.notice("Free move ended: \(expired.count) window(s)")
        endFreeMove(expired)
    }

    /// Kapanan pencerelerin izinleri düşer (saf).
    nonisolated static func liveFreeMoves(_ until: [CGWindowID: Date], alive: Set<CGWindowID>) -> [CGWindowID: Date] {
        until.filter { alive.contains($0.key) }
    }

    /// Şu an serbest olan pencereler (saf).
    nonisolated static func activeFreeMoves(_ until: [CGWindowID: Date], now: Date) -> Set<CGWindowID> {
        Set(until.filter { $0.value > now }.keys)
    }

    /// Birden çok iznin özeti (saf): en geç süreli bitiş sayılır, "kilide
    /// kadar" izin varsa ayrıca yazılır. Hepsi kilide kadarsa sayaç yok.
    nonisolated static func freeMoveStatus(_ until: [Date], now: Date) -> (label: String, timedRemaining: TimeInterval?) {
        let timed = until.filter { !isUntilLock($0) }.max().map { $0.timeIntervalSince(now) }
        let lock = until.contains(where: isUntilLock)
        guard let timed else { return (L("Free to move · until the screen locks"), nil) }
        let base = L("Free to move · %@ left", freeMoveRemaining(timed))
        return (lock ? base + " " + L("(some until the screen locks)") : base, timed)
    }

    /// Kalan süre metni (saf): "4:05", saat varsa "1:00:00".
    nonisolated static func freeMoveRemaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let (h, m, sec) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Masaüstü sıralaması değişince bu ekrandaki oturum pinlerinin masaüstü
    /// numaraları da kurallarla aynı haritaya göre kayar (moddan bağımsız).
    /// En az bir pin kaydıysa true döner (geri alma kaydı için).
    /// `reorderWindows`: etkin modda masaüstü sırası gerçekten değişsin
    /// diye o ekrandaki pencereler de haritaya göre taşınır. macOS space
    /// sırasını dışarıdan değiştirmeye izin vermiyor (Mission Control'de
    /// sıralama eylemi yok, SkyLight çağrısı SIP ister); içerik taşınınca
    /// masaüstüleri kullanıcı için aynı biçimde yer değiştirir. Taşıma
    /// yalnız sürüklenen iki satır da gerçek masaüstüyse yapılır; plan/pin
    /// satırlarına sürüklemede iki masaüstünün pencereleri karışırdı.
    /// Bu sıralama pencereleri gerçekten taşıyacaksa ekranın sıralı space
    /// kimlikleri (belge, adların bağlarını aynı permütasyonla çevirir);
    /// taşımayacaksa nil. `moveDesktop`'tan önce çağrılır.
    func reorderedSpaces(on screen: String, from: Int, to: Int,
                         reorderWindows: Bool) -> [UInt64]? {
        guard willReorderWindows(on: screen, from: from, to: to, reorderWindows: reorderWindows),
              let info = screens.screens.first(where: { $0.id == screen }),
              let display = SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(screens.screens))
                .first(where: { $0.displayUUID == info.uuid })
        else { return nil }
        let spaces = display.desktops.map(\.id)
        return spaces.count >= max(from, to) ? spaces : nil
    }

    private func willReorderWindows(on screen: String, from: Int, to: Int,
                                    reorderWindows: Bool) -> Bool {
        let real = desktopCounts[screen] ?? 0
        return reorderWindows && Self.canReorderWindows(from: from, to: to, realCount: real)
            && moveHealth.movesAllowed && SkyLight.shared.canMove
    }

    @discardableResult
    func moveDesktop(on screen: String, from: Int, to: Int, count: Int,
                     reorderWindows: Bool = false) -> Bool {
        guard let mapping = Document.desktopMapping(from: from, to: to, count: count)
        else { return false }
        let reorders = willReorderWindows(on: screen, from: from, to: to,
                                          reorderWindows: reorderWindows)
        if reorders { reorderWindowsOnDesktops(screen: screen, mapping: mapping) }
        var changed = reorders
        for (id, record) in sessionRecords
        where record.destination.screen == screen {
            guard let updated = mapping[record.destination.desktop],
                  updated != record.destination.desktop else { continue }
            var next = record
            next.destination.desktop = updated
            sessionRecords[id] = next
            sessionPins[id] = next.destination
            forgetApplied(for: id)
            changed = true
        }
        if changed {
            saveSessionPins()
            sweep()
        }
        return changed
    }

    /// Bir masaüstünü başka ekrana taşır: oturum pinleri
    /// `Document.acrossPlacement`'a göre yeniden yazılır; `moveWindows`
    /// (etkin mod) ise iki ekrandaki pencereler de yeni yerlerine taşınır.
    /// Hedefte gerekli gerçek masaüstü yoksa o pencereler yerinde kalır
    /// (çağıran önce `addDesktop` ile açar). Tam ekran ve "All Desktops"
    /// pencereleri taşınmaz.
    @discardableResult
    func moveDesktopAcross(from fromScreen: String, desktop from: Int,
                           to toScreen: String, at to: Int, moveWindows: Bool = false) -> Bool {
        guard fromScreen != toScreen else { return false }
        let moves = moveWindows && moveHealth.movesAllowed && SkyLight.shared.canMove
        if moves { moveWindowsAcross(from: fromScreen, desktop: from, to: toScreen, at: to) }
        var changed = moves
        for (id, record) in sessionRecords {
            guard let next = Document.acrossPlacement(
                screen: record.destination.screen, desktop: record.destination.desktop,
                from: fromScreen, desktop: from, to: toScreen, at: to) else { continue }
            var updated = record
            updated.destination.screen = next.screen
            updated.destination.desktop = next.desktop
            sessionRecords[id] = updated
            sessionPins[id] = updated.destination
            forgetApplied(for: id)
            changed = true
        }
        if changed {
            saveSessionPins()
            sweep()
        }
        return changed
    }

    /// İki ekrandaki pencereleri taşımaya göre yeni masaüstülerine götürür.
    /// Her pencerenin yeri SkyLight'tan taze okunur ve bir kez taşınır
    /// (sıra önemsiz: her pencere doğrudan son yerine gider).
    private func moveWindowsAcross(from fromScreen: String, desktop from: Int,
                                   to toScreen: String, at to: Int) {
        let connected = screens.screens
        let ids = [fromScreen, toScreen]
        let candidates = windows.filter { ids.contains($0.placement?.screen ?? "") }.map(\.id)
        guard !candidates.isEmpty else { return }
        queue.async { [self] in
            let sky = SkyLight.shared
            guard sky.canRead, sky.canMove else { return }
            let displays = sky.displaySpaces(mainUUID: Self.primaryUUID(connected))
            var desktopsOf: [String: [UInt64]] = [:]
            for id in ids {
                guard let screen = connected.first(where: { $0.id == id }),
                      let display = displays.first(where: { $0.displayUUID == screen.uuid })
                // Bağlı olmayan hedef: kaynak yine sıkışır (pinlerle aynı hizada kalsın).
                else { continue }
                desktopsOf[id] = display.desktops.map(\.id)
            }
            var moved = 0
            var crossing: [(CGWindowID, Placement)] = []
            for window in candidates {
                guard let current = sky.spaces(of: window), current.count == 1,
                      let screen = ids.first(where: { desktopsOf[$0]?.contains(current[0]) == true }),
                      let index = desktopsOf[screen]?.firstIndex(of: current[0]),
                      let next = Document.acrossPlacement(
                        screen: screen, desktop: index + 1,
                        from: fromScreen, desktop: from, to: toScreen, at: to),
                      let desktops = desktopsOf[next.screen], next.desktop <= desktops.count
                else { continue }
                if next.screen == screen {
                    sky.move(window: window, to: desktops[next.desktop - 1])
                    moved += 1
                } else {
                    // Ekran değişiyor: çerçeve de hedef ekrana oranlanmalı.
                    crossing.append((window, Placement(screen: next.screen, desktop: next.desktop)))
                }
            }
            let handOff = crossing
            // Kaynakta sona kalan masaüstü boşalır (içerikler bir sola kaydı).
            let vacated = (desktopsOf[fromScreen]?.count ?? 0) >= from
                ? desktopsOf[fromScreen]?.last : nil
            Task { @MainActor [weak self] in
                for (window, placement) in handOff { self?.moveWindow(window, to: placement) }
                if let vacated { self?.removeVacated(space: vacated, on: fromScreen) }
            }
            Log.routing.notice("Desktop move \(fromScreen, privacy: .public) → \(toScreen, privacy: .public): moved \(moved) window(s), \(handOff.count) to the other display")
            Task { @MainActor [weak self] in self?.scheduleFollowUp(after: 300) }
        }
    }

    /// 15b: ekranlar arası taşımada içeriğin eski → yeni space haritası
    /// (R5), taze okumayla; hedefte gerekli masaüstüleri açıldıktan sonra.
    func acrossSpaceMap(from fromScreen: String, desktop from: Int,
                        to toScreen: String, at to: Int) -> [UInt64: UInt64]? {
        let spaces = Self.spaces(readLiveDisplays())
        guard spaces[fromScreen] != nil, spaces[toScreen] != nil else { return nil }
        return Self.acrossSpaceMap(spaces: spaces, from: fromScreen, desktop: from, to: toScreen, at: to)
    }

    /// Saf hâli: her masaüstünün içeriği `acrossPlacement`'ın verdiği yere.
    nonisolated static func acrossSpaceMap(spaces: [String: [UInt64]], from fromScreen: String,
                                           desktop from: Int, to toScreen: String,
                                           at to: Int) -> [UInt64: UInt64] {
        var map: [UInt64: UInt64] = [:]
        for screen in [fromScreen, toScreen] {
            for (index, space) in (spaces[screen] ?? []).enumerated() {
                guard let next = Document.acrossPlacement(
                        screen: screen, desktop: index + 1, from: fromScreen, desktop: from,
                        to: toScreen, at: to),
                      let list = spaces[next.screen], next.desktop <= list.count else { continue }
                map[space] = list[next.desktop - 1]
            }
        }
        return map
    }

    /// D2: ekranlar arası taşımadan sonra kaynakta boş kalan son masaüstü
    /// (hiçbir profilde adlı değilse, hemen önce boşluğu denetlenerek) silinir.
    private func removeVacated(space: UInt64, on screenID: String) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !self.desktopOpInFlight, self.transition == nil else { return }
            let current = self.readLiveDisplays()
            guard let display = current.first(where: { $0.role == screenID }),
                  display.spaces.count > 1, let index = display.spaces.firstIndex(of: space),
                  !self.store.document.namedSpacesInAnyProfile.contains(space),
                  Self.spaceIsEmpty(space) == true else { return }
            self.desktopOpInFlight = true
            defer { self.desktopOpInFlight = false }
            if await self.removeDesktopNow(on: screenID, desktop: index + 1, expected: space) {
                Log.app.notice("Emptied desktop \(index + 1) on \(screenID, privacy: .public) removed after moving its desktop to another display")
                self.ownRemovals.insert(space)
                self.commitSnapshot()
            }
            self.scheduleFollowUp(after: 300)
        }
    }

    /// Pencereler yalnız iki uç da gerçek masaüstüyse taşınır (saf).
    nonisolated static func canReorderWindows(from: Int, to: Int, realCount: Int) -> Bool {
        from >= 1 && to >= 1 && max(from, to) <= realCount
    }

    /// Ekrandaki pencereleri masaüstü haritasına göre taşır (eski sıra →
    /// yeni sıra). Pencerenin şu anki masaüstü kuyrukta SkyLight'tan taze
    /// okunur (son taramanın anlık görüntüsü eski olabilir: hızlı ikinci
    /// sürükleme ya da ⌘Z). Yalnız tek space'teki pencereler; "All
    /// Desktops" pencereleri ve gerçekte olmayan masaüstüler atlanır.
    private func reorderWindowsOnDesktops(screen screenID: String, mapping: [Int: Int]) {
        let connected = screens.screens
        let candidates = windows.filter { $0.placement?.screen == screenID }.map(\.id)
        guard !candidates.isEmpty else { return }
        queue.async { [self] in
            let sky = SkyLight.shared
            guard sky.canRead, sky.canMove,
                  let target = connected.first(where: { $0.id == screenID }),
                  let display = sky.displaySpaces(mainUUID: Self.primaryUUID(connected))
                    .first(where: { $0.displayUUID == target.uuid })
            else { return }
            let desktops = display.desktops.map(\.id)
            var moved = 0
            for id in candidates {
                guard let current = sky.spaces(of: id), current.count == 1,
                      let index = desktops.firstIndex(of: current[0]),
                      let desktop = mapping[index + 1], desktop != index + 1,
                      desktop <= desktops.count else { continue }
                sky.move(window: id, to: desktops[desktop - 1])
                moved += 1
            }
            Log.routing.notice("Desktop reorder on \(screenID, privacy: .public): moved \(moved) window(s)")
            Task { @MainActor [weak self] in self?.scheduleFollowUp(after: 300) }
        }
    }

    /// Açılışta: kayıtlı oturum pinlerinden penceresi hâlâ (aynı pid ile)
    /// pencere sunucusunda olanlar geri yüklenir, kalanı atılır.
    private func loadSessionPins() {
        guard let data = try? Data(contentsOf: Self.sessionFileURL),
              let records = try? JSONDecoder().decode([SessionPin].self, from: data)
        else { return }
        let live = AX.liveWindowIDs()
        var restored: [CGWindowID: SessionPin] = [:]
        for record in records where live[record.windowID] == record.pid {
            restored[record.windowID] = record
        }
        sessionRecords = restored
        sessionPins = restored.mapValues(\.destination)
        if restored.count != records.count { saveSessionPins() }
    }

    private func saveSessionPins() {
        // Shots modu gerçek kullanıcının dosyasına yazmasın.
        guard !isDemo else { return }
        do {
            try FileManager.default.createDirectory(
                at: Store.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let records = sessionRecords.values.sorted { $0.windowID < $1.windowID }
            try encoder.encode(records).write(to: Self.sessionFileURL, options: .atomic)
        } catch {
            store.report(L("Could not write session-pins.json: %@", error.localizedDescription))
        }
    }

    /// Bir pencerenin düzen belleğini sıfırlar; hedefi değişince yeniden
    /// yerleştirilsin.
    private func forgetApplied(for windowID: CGWindowID) {
        generation.advance()
        appliedFloor[windowID] = generation.current
        applied[windowID] = nil
        dropAttempts(for: windowID)
    }

    /// Pencerenin taşıma/düzen deneme sayaçlarını siler.
    private func dropAttempts(for windowID: CGWindowID) {
        let prefix = "\(windowID)|"
        attempts = attempts.filter { !$0.key.hasPrefix(prefix) }
        lastAttempts = lastAttempts.filter { !$0.key.hasPrefix(prefix) }
        if isSweeping { invalidatedPrefixes.insert(prefix) }
    }

    /// Kısa bir süre sonra yeniden tara (masaüstü taşıması yerleşsin diye).
    private func scheduleFollowUp(after milliseconds: UInt64) {
        followUp?.cancel()
        followUp = Task { [weak self] in
            try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.sweep()
        }
    }

    // MARK: - Masaüstü ekleme

    /// Mission Control işlemi sürüyor: ekleme/silme/plan yürütme tek tek
    /// yapılır (aynı anda iki işlem Mission Control'ü açıp kapatır, sıra
    /// kayabilir).
    private var desktopOpInFlight = false

    private func displayInfo(_ screenID: String) -> (uuid: String, id: CGDirectDisplayID)? {
        guard let info = screens.screens.first(where: { $0.id == screenID }),
              let screen = NSScreen.screens.first(where: { ScreenInfo.uuid(of: $0) == info.uuid }),
              let displayID = ScreenInfo.displayID(of: screen)
        else { return nil }
        return (info.uuid, displayID)
    }

    /// Bağlı bir ekrana Mission Control üzerinden masaüstü ekler, sonra
    /// haritanın masaüstü sayısı tazelensin diye yeniden tarar. Başka bir
    /// masaüstü işlemi sürüyorsa false.
    func addDesktop(on screenID: String) async -> Bool {
        guard !desktopOpInFlight else { return false }
        desktopOpInFlight = true
        defer { desktopOpInFlight = false }
        return await addDesktopNow(on: screenID)
    }

    private func addDesktopNow(on screenID: String) async -> Bool {
        guard !Self.desktopChangesDisabled, let display = displayInfo(screenID) else { return false }
        let added = await MissionControl.addDesktop(
            displayID: display.id, displayUUID: display.uuid,
            mainUUID: Self.primaryUUID(screens.screens))
        scheduleFollowUp(after: 300)
        return added
    }

    /// Masaüstünü pinlere dokunmadan siler.
    private func removeDesktopNow(on screenID: String, desktop: Int,
                                  expected: UInt64? = nil) async -> Bool {
        guard !Self.desktopChangesDisabled, let display = displayInfo(screenID) else { return false }
        return await MissionControl.removeDesktop(
            displayID: display.id, displayUUID: display.uuid,
            mainUUID: Self.primaryUUID(screens.screens), desktop: desktop, expectedSpace: expected)
    }

    /// Etkin moddaki bağlı ekranın masaüstünü siler; başarılıysa masaüstünün
    /// pinleri ve adı hayalete geçer (dışarıda silinmiş gibi), bu ekranın
    /// bütün modlardaki (laptop ekranının masaüstüleri iki modda ortak) ve
    /// bütün profillerdeki sonraki pinleri ile oturum pinleri kayar.
    func removeDesktop(on screenID: String, desktop: Int) async -> Bool {
        guard !desktopOpInFlight else { return false }
        desktopOpInFlight = true
        defer { desktopOpInFlight = false }
        let space = currentSpace(on: screenID, desktop: desktop)
        let removed = await removeDesktopNow(on: screenID, desktop: desktop)
        if removed {
            // Mission Control'de silmeyle aynı (B 14 → 8/9): adı ve pinleri
            // hayalete geçer (satırdan geri getirilebilir), sonrakiler kayar.
            let ghost = store.recordDeletion(space: space, role: screenID, desktop: desktop, mode: screens.mode)
            Log.app.notice("Desktop \(desktop) on \(screenID, privacy: .public) removed in Deskmap\(ghost == nil ? "" : "; name or pins kept on a deleted-desktop row", privacy: .public)")
            shiftSessionPins(screen: screenID, removed: desktop)
            if let space { ownRemovals.insert(space) }
            if transition == nil { commitSnapshot() }
        }
        scheduleFollowUp(after: 300)
        return removed
    }

    private func shiftSessionPins(screen screenID: String, removed desktop: Int) {
        var changed = false
        for (id, record) in sessionRecords where record.destination.screen == screenID {
            let updated = Document.removalMapping(desktop: record.destination.desktop,
                                                  removed: desktop)
            guard updated != record.destination.desktop else { continue }
            var next = record
            next.destination.desktop = updated
            sessionRecords[id] = next
            sessionPins[id] = next.destination
            forgetApplied(for: id)
            changed = true
        }
        if changed { saveSessionPins() }
    }

    func realDesktopCount(on screenID: String) -> Int? {
        guard let info = screens.screens.first(where: { $0.id == screenID }) else { return nil }
        return liveDesktopCount(uuid: info.uuid)
    }

    // MARK: - Yeniden açma hedefleri

    /// Başlık parçalı (belirli pencere) kalıcı pinlere uyan açık
    /// pencerelerin dosya/klasör/sayfa adresi arka planda okunur; başlık
    /// değişince ya da dakikada bir. Değişen adres `reopen.json`'a yazılır.
    private func captureReopenTargets(_ snapshots: [WindowSnapshot]) {
        guard !isDemo else { return }
        let now = Date()
        let rules = store.document.rules, mode = screens.mode
        var jobs: [(window: CGWindowID, pid: pid_t, bundleID: String, title: String, rule: String)] = []
        for window in snapshots where !window.isMinimized && window.fullscreen == nil {
            guard let match = Routing.select(
                    rules: rules, sessionPins: [:], mode: mode, windowID: window.id,
                    bundleID: window.bundleID, appName: window.appName, title: window.title, document: window.document),
                  let rule = match.rule, !rule.isAppWide else { continue }
            if let last = reopenReads[window.id], last.title == window.title,
               now.timeIntervalSince(last.at) < Self.reopenRefresh { continue }
            reopenReads[window.id] = (window.title, now)
            jobs.append((window.id, window.pid, window.bundleID, window.title, rule.id))
        }
        let alive = Set(snapshots.map(\.id))
        reopenReads = reopenReads.filter { alive.contains($0.key) }
        guard !jobs.isEmpty, !reopenBusy else { return }
        reopenBusy = true
        reopenQueue.async { [weak self, jobs] in
            var found: [String: URL] = [:]
            for job in jobs {
                guard let element = AX.element(pid: job.pid, windowID: job.window),
                      let url = Reopen.capture(element, bundleID: job.bundleID, title: job.title)
                else { continue }
                found[job.rule] = url
            }
            DispatchQueue.main.async { [weak self, found] in
                self?.reopenBusy = false
                if !found.isEmpty { self?.storeReopenTargets(found) }
            }
        }
    }

    private func storeReopenTargets(_ found: [String: URL]) {
        let ruleIDs = Set(store.document.profiles.flatMap(\.rules).map(\.id))
            .union(store.document.rules.map(\.id))
        var next = reopenTargets.filter { ruleIDs.contains($0.key) }
        for (rule, url) in found where next[rule]?.url != url.absoluteString {
            next[rule] = ReopenTarget(url: url.absoluteString, seenAt: Date())
        }
        guard next != reopenTargets else { return }
        reopenTargets = next
        do {
            try FileManager.default.createDirectory(
                at: Store.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(next).write(to: Self.reopenFileURL, options: .atomic)
        } catch {
            Log.app.error("reopen.json not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadReopenTargets() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.reopenFileURL),
              let saved = try? decoder.decode([String: ReopenTarget].self, from: data)
        else { return }
        reopenTargets = saved
    }

    // MARK: - Masaüstü durumu ve plan uygulaması (şema 6)

    /// Plan uygulamasının alt çubuktaki durumu.
    struct PlanStatus: Equatable {
        var message: String
        var failed: Bool
        var at: Date
    }

    /// Son kararlı fiziksel durum (`desktop-state.json`); bütün profillerde ortak.
    private(set) var desktopState: DesktopStateFile?
    /// Süren geçiş: ilk ekran bildiriminden plan uygulanıp kaydedilene dek
    /// (çökmede dosyada kalır, sonraki açılış sürdürür).
    private var transition: DesktopStateFile.Transition?
    private var transitionRunning = false
    /// Deskmap'in kendi sildiği space'ler (kaydı işlendi; silme sayılmaz).
    private var ownRemovals: Set<UInt64> = []
    /// Uyanmadan ya da plan kaydından sonra bu ana dek kaybolan masaüstü
    /// silme sayılmaz, geçiş olur (P.2).
    private var quietUntil: Date?
    /// Onay bekleyen masaüstü değişikliği (iki taramada aynı görülmeli).
    struct PendingChange: Equatable {
        var displays: [DesktopStateFile.Display]
        var since: Date
    }
    private var pendingChange: PendingChange?
    /// Tablo E: son uyanma (geri alma bundan 60 sn sonraya dek yok, E3.4).
    private var lastWakeAt: Date?
    /// Kayıtlı durum canlı durumla en az bir kez karşılaştırıldı ya da
    /// kaydedildi: bundan sonraki fark Deskmap çalışırken oldu (E1.6).
    private var liveSeen = false
    /// Onay bekleyen fark Deskmap açılmadan önce olmuştu (SE2: kart).
    private var catchUpDiff = false
    /// Geri almanın açtığı space → zamanı (SE3).
    private var recentReverts: [UInt64: Date] = [:]
    /// Ekran değiştiren masaüstü onay ya da geri alma bekliyor: bu ana dek
    /// yönlendirme bekler (E2.9; sayı pinli pencereler gidip gelmesin).
    private var revertHoldUntil: Date?
    /// Tablo E kartı.
    @Published private(set) var revertOffer: RevertOffer?

    struct RevertOffer: Equatable {
        enum Kind: Equatable {
            /// "Geri al" düğmesi (Sor ayarı ya da Deskmap kapalıyken, SE2).
            case ask
            /// Geri alındı; "Böyle kalsın" düğmesi (E4.4).
            case reverted
            /// Bilgi (kısmen, yapılamadı, taşıma kapalı).
            case info
        }
        var kind: Kind
        var message: String
        /// `ask`: geri alınacaklar; `reverted`: "Böyle kalsın"ın ters taşımaları.
        var crossings: [DesktopRevert.Crossing]
        var failed: Bool
        var at: Date
    }
    nonisolated static let changeConfirmDelay: TimeInterval = 1.5
    /// Açılıştan beri kararlı bir tarama pencere içeriğini okudu (ad geçişi
    /// ve geçiş kanıtı bu okumaya dayanır).
    private var sweptOnce = false
    /// Son taramanın tek masaüstündeki pencereleri.
    private var lastContents: [UInt64: [DesktopStateFile.WindowRef]] = [:]
    private var lastWindowSpaces: [CGWindowID: UInt64] = [:]
    private var stateWriteTask: Task<Void, Never>?
    private let launchedAt = Date()
    /// Aynı geçişte en çok bu kadar uygulama turu (sınır aşılınca yeni tur).
    private var applyPasses = 0
    /// Bekleyen artık temizliği (P1) ve son temizlik denemesi.
    private var cleanupTask: Task<Void, Never>?
    private var lastCleanupAt: Date?
    /// Kararlı taramada iki temizlik denemesi arasında en az bu kadar.
    nonisolated static let cleanupThrottle: TimeInterval = 20
    @Published private(set) var planStatus: PlanStatus?

    /// Geçiş başlangıcından bu kadar sonra ad geçişi kanıtsız da tamamlanır.
    nonisolated static let migrationDeadline: TimeInterval = 30

    private func loadDesktopState() {
        let directory = Store.directoryURL
        if let saved = DesktopStateFile.read(directory: directory) {
            desktopState = saved
            // Çökme: yarım kalan uygulama kayıtlı "önce" durumundan yeniden (B 21).
            if let pending = saved.transition { transition = pending }
        } else if let legacy = DesktopStateFile.readLegacy(directory: directory) {
            desktopState = legacy
        }
    }

    /// Bağlı ekranların canlı masaüstü sırası (taze SkyLight okuması).
    private func readLiveDisplays() -> [DesktopStateFile.Display] {
        let connected = screens.screens
        let read = SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(connected))
        var result: [DesktopStateFile.Display] = []
        for display in read {
            guard let screen = connected.first(where: { $0.uuid == display.displayUUID }) else { continue }
            result.append(.init(role: screen.id, uuid: screen.uuid, spaces: display.desktops.map(\.id)))
        }
        return result.sorted { $0.role < $1.role }
    }

    private static func spaces(_ displays: [DesktopStateFile.Display]) -> [String: [UInt64]] {
        Dictionary(displays.map { ($0.role, $0.spaces) }, uniquingKeysWith: { a, _ in a })
    }

    /// Pencere sunucusundaki bütün normal pencerelerin tek (normal) space'i
    /// ve space başına içerik. Plan uygulamasından hemen önce, kuyrukta.
    nonisolated static func readWindowSpaces() -> (contents: [UInt64: [DesktopStateFile.WindowRef]],
                                                   windowSpaces: [CGWindowID: UInt64]) {
        let sky = SkyLight.shared
        guard sky.canRead,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return ([:], [:]) }
        var contents: [UInt64: [DesktopStateFile.WindowRef]] = [:]
        var windowSpaces: [CGWindowID: UInt64] = [:]
        var bundles: [pid_t: String] = [:]
        for entry in list {
            guard let (id, pid) = AX.liveEntry(from: entry),
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let spaces = sky.spaces(of: id), spaces.count == 1,
                  sky.type(of: spaces[0]) == 0 else { continue }
            if bundles[pid] == nil {
                bundles[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            }
            windowSpaces[id] = spaces[0]
            contents[spaces[0], default: []].append(.init(id: id, pid: pid, bundleID: bundles[pid] ?? ""))
        }
        return (contents, windowSpaces)
    }

    /// Space boş mu (C1): pencere sunucusundaki (küçültülmüş ve ekran dışı
    /// dahil) katman 0 pencerelerinden hiçbiri yalnız bu space'te değil.
    /// Okunamazsa nil (bilinmiyor = boş değil).
    nonisolated static func spaceIsEmpty(_ space: UInt64) -> Bool? {
        let sky = SkyLight.shared
        guard sky.canRead,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let windows: [[UInt64]?] = list.compactMap { entry in
            guard let (id, _) = AX.liveEntry(from: entry),
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            return .some(sky.spaces(of: id))
        }
        return PlanApply.isEmpty(space, windowSpaces: windows)
    }


    /// Kararlı durumu kaydeder: taze ekran okuması, son içerik, park kayıtları.
    private func commitSnapshot(parked: [PlanApply.Parked]? = nil) {
        let displays = readLiveDisplays()
        guard !displays.isEmpty else { return }
        let live = Set(displays.flatMap(\.spaces))
        var state = DesktopStateFile(
            savedAt: Date(), bootTime: DesktopStateFile.currentBootTime(), mode: screens.mode,
            displays: displays,
            contents: DesktopStateFile.encodeContents(lastContents.filter { live.contains($0.key) }),
            parked: parked ?? desktopState?.parked ?? [], transition: nil)
        state.parked = DesktopStateFile.prunedParked(state.parked, alive: nil, now: Date())
        desktopState = state
        store.setLive(LiveDesktops(mode: screens.mode, spaces: Self.spaces(displays)))
        writeDesktopState()
        liveSeen = true
    }

    private func writeDesktopState() {
        stateWriteTask?.cancel()
        stateWriteTask = nil
        guard !isDemo, var state = desktopState else { return }
        state.transition = transition
        do {
            try state.write(directory: Store.directoryURL)
        } catch {
            Log.app.error("desktop-state.json not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// İçerik değişti: 5 sn sonra yazılır (kararlı tarama başına değil).
    private func scheduleStateWrite() {
        guard stateWriteTask == nil else { return }
        stateWriteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.writeDesktopState()
        }
    }

    /// Ekran bildirimi (ya da uyanma, kapalıyken değişen ekranlar): kayıtlı
    /// kararlı durum "önce" olur, yazım durur.
    private func beginTransition(reason: String) {
        guard transition == nil, !isDemo, let base = desktopState else { return }
        transition = DesktopStateFile.Transition(
            id: UUID().uuidString, startedAt: Date(), reason: reason, from: base.displays,
            fromContents: base.contents, fromMode: base.mode)
        applyPasses = 0
        Log.screens.notice("Desktop transition started (\(reason, privacy: .public)); before: \(base.displays.map { "\($0.role)=\($0.spaces.count)" }.joined(separator: " "), privacy: .public)")
        writeDesktopState()
    }

    /// Kararlı taramanın sonu: canlı masaüstü listesini izler. Ekran kümesi
    /// değiştiyse (bildirim kaçtı, kapalıyken takıldı) geçiş; aynıysa ve
    /// masaüstüleri değiştiyse Mission Control işlemleri (B 8–12). Her
    /// değişiklik iki taramada aynı görünmeden işlenmez: ekran bildirimi
    /// gelmeden macOS'un yarım düzenlediği liste silme sayılmasın.
    private func followDesktops() {
        guard !isDemo, !screens.isSettling, !desktopOpInFlight, !transitionRunning,
              SkyLight.shared.canRead else { return }
        // SkyLight ile NSScreen aynı ekranları görmüyor: ekranlar değişiyor,
        // bildirim yolda. Hiçbir şey yapılmaz.
        guard let displays = readLiveDisplaysIfSettled() else {
            pendingChange = nil
            return
        }
        guard !displays.isEmpty else { return }
        let mode = screens.mode
        let spaces = Self.spaces(displays)
        store.setLive(LiveDesktops(mode: mode, spaces: spaces))
        if store.migrationPending {
            completeMigration(requireEvidence: true)
            return
        }
        if let saved = desktopState,
           !DesktopStateFile.sameBoot(saved.bootTime, DesktopStateFile.currentBootTime()) {
            // Yeniden başlatıldı: pencere kimlikleri (belki space'ler de)
            // yenilenmiş; kanıt yok, adlar plandaki yerlerine (R4), silme ve
            // taşıma yok, yarım kalmış geçiş bırakılır.
            Log.app.notice("Restart detected; desktop names bound by plan position")
            transition = nil
            pendingChange = nil
            if !store.isReadOnly { store.bindByPlan(live: LiveDesktops(mode: mode, spaces: spaces)) }
            commitSnapshot()
            return
        }
        if transition != nil {
            Task { await runTransition() }
            return
        }
        guard let saved = desktopState else {
            commitSnapshot()
            return
        }
        let displaysChanged = !saved.sameDisplays(as: displays) || saved.mode != mode
        guard displaysChanged || saved.spaces != spaces else {
            pendingChange = nil
            liveSeen = true
            revertHoldUntil = nil
            let live = Set(spaces.values.joined())
            let contents = DesktopStateFile.encodeContents(lastContents.filter { live.contains($0.key) })
            if contents != saved.contents {
                desktopState?.contents = contents
                desktopState?.savedAt = Date()
                scheduleStateWrite()
            }
            cleanupIfNeeded(spaces: spaces, mode: mode)
            return
        }
        if !liveSeen { catchUpDiff = true }
        // Tablo E: ekran değiştiren masaüstü onay beklerken yönlendirme
        // bekler (E2.9); karar `handleCrossings`'te.
        let crossings = displaysChanged ? [] : DesktopRevert.crossings(before: saved.spaces, after: spaces)
        if !crossings.isEmpty, store.document.missionControlMoves != .leave {
            revertHoldUntil = Date().addingTimeInterval(10)
        }
        let check = Self.confirmChange(pending: pendingChange, observed: displays, now: Date())
        pendingChange = check.pending
        guard check.confirmed else {
            scheduleFollowUp(after: UInt64(Self.changeConfirmDelay * 1000) + 100)
            return
        }
        let catchUp = catchUpDiff
        catchUpDiff = false
        if store.isReadOnly {
            commitSnapshot()
            return
        }
        if displaysChanged {
            beginTransition(reason: "catch-up")
            Task { await runTransition() }
            return
        }
        if let until = quietUntil, Date() < until {
            // Uyanma ya da plan kaydından hemen sonra: kaybolan masaüstü
            // silme değil, geçiş (P.2).
            beginTransition(reason: "settle")
            Task { await runTransition() }
            return
        }
        let deletions = store.followMissionControl(before: saved.spaces, after: spaces, mode: mode,
                                                   ownRemovals: ownRemovals)
        for deletion in deletions {
            if deletion.ghost {
                Log.app.notice("Desktop \(deletion.desktop) on \(deletion.role, privacy: .public) (space \(deletion.space)) was removed outside Deskmap; its name or pins kept on a deleted-desktop row")
            } else {
                Log.app.notice("Desktop \(deletion.desktop) on \(deletion.role, privacy: .public) (space \(deletion.space)) was removed outside Deskmap; unnamed and without pins, later numbers shifted (no deleted-desktop row)")
            }
            shiftSessionPins(screen: deletion.role, removed: deletion.desktop)
        }
        ownRemovals = ownRemovals.filter { space in spaces.values.contains { $0.contains(space) } }
        commitSnapshot()
        handleCrossings(crossings, catchUp: catchUp)
    }

    /// Masaüstü değişikliği onayı (saf): aynı liste en az `changeConfirmDelay`
    /// arayla iki kez görülmeli; farklı liste bekleyeni yeniler.
    nonisolated static func confirmChange(pending: PendingChange?, observed: [DesktopStateFile.Display],
                                          now: Date) -> (confirmed: Bool, pending: PendingChange?) {
        if let pending, pending.displays == observed {
            if now.timeIntervalSince(pending.since) >= changeConfirmDelay { return (true, nil) }
            return (false, pending)
        }
        return (false, PendingChange(displays: observed, since: now))
    }

    /// SkyLight'ın ekranları NSScreen'inkilerle aynıysa canlı masaüstü sırası;
    /// değilse (ekran değişiyor, bildirim gelmedi) nil. Uyuşmazlık 10 sn'den
    /// uzun sürerse (ekran düzeni SkyLight'a öyle görünüyor) yine okunur.
    private func readLiveDisplaysIfSettled() -> [DesktopStateFile.Display]? {
        let connected = screens.screens
        let read = SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(connected))
        if Self.displaysAgree(sky: read.map(\.displayUUID), connected: connected.map(\.uuid),
                              separateSpaces: NSScreen.screensHaveSeparateSpaces) {
            displaysDisagreeSince = nil
        } else {
            let now = Date()
            let since = displaysDisagreeSince ?? now
            displaysDisagreeSince = since
            if now.timeIntervalSince(since) < 10 {
                scheduleFollowUp(after: 2000)
                return nil
            }
        }
        return readLiveDisplays()
    }
    private var displaysDisagreeSince: Date?

    /// SkyLight ile NSScreen aynı ekran kümesini görüyor mu (saf). Ayrı
    /// Spaces kapalıyken SkyLight tek ("Main") ekran bildirir.
    nonisolated static func displaysAgree(sky: [String], connected: [String], separateSpaces: Bool) -> Bool {
        let skySet = Set(sky), connectedSet = Set(connected)
        guard !skySet.isEmpty, skySet.isSubset(of: connectedSet) else { return false }
        return separateSpaces ? skySet == connectedSet : true
    }

    /// Bu ana dek kaybolan masaüstü silme sayılmaz, geçiş olur (P.2).
    private func extendQuietWindow(seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        if quietUntil.map({ $0 < until }) ?? true { quietUntil = until }
    }

    /// Plan yürütülürken ya da geçiş bekleyip yürütülmeyi beklerken (en çok
    /// 60 sn; takılan geçiş yönlendirmeyi sonsuza dek durdurmasın).
    private func planHoldsRouting(now: Date) -> Bool {
        if transitionRunning { return true }
        if let until = revertHoldUntil, now < until { return true }
        guard let transition else { return false }
        return now.timeIntervalSince(transition.startedAt) < 60
    }

    /// Son bakılan onay bekleyen roller (onaylanınca plan uygulanır).
    private var lastHeldRoles: Set<String> = []

    private func followHeldRoles() {
        let held = screens.heldRoles
        let released = lastHeldRoles.subtracting(held)
        lastHeldRoles = held
        guard !released.isEmpty, !screens.isSettling else { return }
        Log.screens.notice("Monitor role confirmed: \(released.sorted().joined(separator: ", "), privacy: .public); applying its plan")
        applyPlanNow(reason: "monitor role confirmed")
        reapplyAll()
    }

    /// Ekranlar yatıştı: geçiş planı uygular.
    private func handleSettled() {
        lastHeldRoles = screens.heldRoles
        if transition == nil { beginTransition(reason: "display") }
        Task { await runTransition() }
    }

    /// §A.8 aşama 2: canlı kanıtla ad geçişi (pencere taşımaz).
    private func completeMigration(requireEvidence: Bool) {
        // Açılışta ilk tarama bitmeden (pencere listesi boş) geçiş
        // kanıtsız kalırdı: eski bağlara düşer, yanlış ad yanlış masaüstüne.
        guard !requireEvidence || sweptOnce else { return }
        let live = store.live
        let evidence = live.map { live in
            MigrationEvidence(live: live, windows: windows.compactMap { window in
                lastWindowSpaces[window.id].map {
                    MigrationEvidence.Window(id: window.id, space: $0, bundleID: window.bundleID,
                                             appName: window.appName, title: window.title,
                                             document: window.document)
                }
            })
        }
        guard store.completeMigration(evidence: evidence) else { return }
        if let report = store.migrationReport, report.emptyCount > 0 {
            Log.app.notice("Desktop names upgraded; \(report.emptyCount) empty desktop(s) beyond the plan kept")
        }
        transition = nil
        commitSnapshot()
        reapplyAll()
    }

    /// Kanıtlı geçişi bekleyen ad geçişi süre sınırını aştıysa (ekranlar hiç
    /// yatışmadı) eldeki kanıtla tamamlanır.
    private func completeMigrationIfOverdue(now: Date) {
        guard store.migrationPending,
              now.timeIntervalSince(launchedAt) >= Self.migrationDeadline else { return }
        Log.app.notice("Desktop names upgrade: no stable sweep within \(Int(Self.migrationDeadline)) s; upgrading with the evidence at hand")
        if store.live == nil, SkyLight.shared.canRead {
            let displays = readLiveDisplays()
            if !displays.isEmpty {
                store.setLive(LiveDesktops(mode: screens.mode, spaces: Self.spaces(displays)))
            }
        }
        completeMigration(requireEvidence: false)
    }

    /// Kurala ya da oturum pinine uyan pencereler (etkin kurulumda).
    private func ruledWindows(mode: Mode) -> Set<CGWindowID> {
        let rules = store.document.rules, sessions = sessionPins
        return Set(windows.filter { window in
            Routing.select(rules: rules, sessionPins: sessions, mode: mode, windowID: window.id,
                           bundleID: window.bundleID, appName: window.appName, title: window.title,
                           document: window.document) != nil
        }.map(\.id))
    }

    /// Geçişi uygular (§P.1): ardıllar (R2, bütün profiller), park, plan,
    /// yürütme, kayıt. Ekran yeniden değişirse yarıda kalır: yapılan
    /// taşımaların bağları kaydedilir, geçiş kaydı durur, sonraki yatışmada
    /// aynı "önce" durumundan yeniden hesaplanır.
    private func runTransition() async {
        guard let current = transition, !transitionRunning, !screens.isSettling,
              !desktopOpInFlight, sweptOnce else { return }
        // Ad geçişi bekliyor: kanıtlı ilk kararlı taramada (followDesktops) yapılır.
        guard !store.migrationPending else { return }
        transitionRunning = true
        defer { transitionRunning = false }
        let mode = screens.mode
        let displays = readLiveDisplays()
        guard SkyLight.shared.canRead, !displays.isEmpty else {
            transition = nil
            commitSnapshot()
            return
        }
        let live = LiveDesktops(mode: mode, spaces: Self.spaces(displays))
        store.setLive(live)
        // Salt okunur (geçiş geri alındı ya da yeni sürümün dosyası): plan
        // uygulanmaz, yalnız fiziksel durum kaydedilir.
        guard !store.isReadOnly else {
            transition = nil
            commitSnapshot()
            return
        }
        let fresh = await withCheckedContinuation { continuation in
            Self.planQueue(router: queue).async { continuation.resume(returning: Self.readWindowSpaces()) }
        }
        guard transition?.id == current.id else { return }
        resumeJournal(current, windowSpaces: fresh.windowSpaces)
        let fromSpaces = Self.spaces(current.from)
        let snapshot = Succession.Snapshot(spaces: fromSpaces,
                                           contents: DesktopStateFile.windowIDs(current.fromContents))
        let namedBefore = Set(store.document.names.compactMap(\.space))
        let evacuation = store.resolveSuccession(snapshot: snapshot, live: live,
                                                 windowSpaces: fresh.windowSpaces,
                                                 carried: current.evacuation ?? [:])
        let extras = PlanApply.transitionExtras(
            from: current.from, fromContents: current.fromContents, fromMode: current.fromMode,
            mode: mode, live: displays, windowSpaces: fresh.windowSpaces, namedBefore: namedBefore,
            ruled: ruledWindows(mode: mode), parked: desktopState?.parked ?? [], now: Date())
        var parked = extras.parked
        let pending = Self.pendingQueue(store.document.pendingRemovals, mode: mode).all
        var otherNamed = Set<UInt64>()
        for profile in store.document.profiles where profile.id != store.document.activeProfileID {
            otherNamed.formUnion(profile.names.compactMap(\.space))
        }
        var refs: [CGWindowID: DesktopStateFile.WindowRef] = [:]
        for list in fresh.contents.values { for ref in list { refs[ref.id] = ref } }
        let input = PlanApply.Input(
            mode: mode, live: live.spaces, contents: fresh.contents.mapValues { $0.map(\.id) },
            names: store.document.names, plans: store.document.plans[mode], evacuation: evacuation,
            arriving: extras.arriving,
            parked: mode == .docked ? parked.filter { live.spaces[$0.role] != nil } : [],
            leftovers: extras.leftovers.union(current.leftovers ?? []),
            newSpaces: extras.newSpaces, compactBeyondPlan: true, otherNamed: otherNamed,
            pending: pending, pinned: pinnedDesktops(mode: mode),
            allowRemovals: true, allowMoves: moveHealth.movesAllowed && SkyLight.shared.canMove)
        let held = screens.heldRoles
        if !held.isEmpty {
            Log.screens.notice("Plan held for unconfirmed monitor role(s): \(held.sorted().joined(separator: ", "), privacy: .public)")
        }
        let plan = PlanApply.compute(PlanApply.holding(input, roles: held))
        logPlan(plan, live: live.spaces, mode: mode, reason: current.reason)
        if !input.allowMoves {
            planStatus = PlanStatus(message: L("Plan could not be applied: moving windows is off"),
                                    failed: true, at: Date())
        }
        let outcome = await execute(plan, expected: live.spaces, refs: refs,
                                    windowSpaces: fresh.windowSpaces, allowRemovals: true)
        let leftovers = PlanExecutor.leftovers(of: plan, input: input, outcome: outcome)
        if outcome.aborted {
            // Yapılan taşımaların bağları kaydedilir (yoksa yeniden hesapta
            // adın içeriği "adsız" sayılıp başka yere taşınırdı). Bu turun
            // artıkları kaydedilir: yeniden başlayan geçiş onları da siler
            // (ilk turun boşalttığı masaüstü artık "boşaltılan" görünmez).
            store.commitPlan(rebinds: outcome.rebinds, spaceMap: outcome.spaceMap)
            transition?.leftovers = leftovers.sorted()
            // Tahliye kümesi de kalıcı: resolveSuccession adın yerleşmemiş
            // hâlini yazdı, yeniden başlayan geçiş pencereleri bununla bulur.
            transition?.evacuation = evacuation.isEmpty ? nil : evacuation
            clearJournal()
            writeDesktopState()
            Log.screens.notice("Desktop transition interrupted (\(outcome.abortReason ?? "", privacy: .public)); it restarts from the saved state when displays settle")
            return
        }
        store.commitPlan(rebinds: outcome.rebinds, spaceMap: outcome.spaceMap)
        // Yerine dönen ya da artık rolü bağlı park kayıtları düşer.
        let movedBack = Set(plan.moves.map(\.window))
        if mode == .docked {
            parked.removeAll { movedBack.contains($0.window) || live.spaces[$0.role] != nil }
        }
        transition = nil
        commitSnapshot(parked: parked)
        // Kayıttan hemen sonra macOS'un geç gelen değişiklikleri silme
        // sayılmaz (P.2: commit + 3 sn).
        extendQuietWindow(seconds: 3)
        report(outcome, plan: plan, mode: mode, reason: current.reason)
        scheduleCleanup(reason: "after transition", delay: 5)
        if plan.truncated, applyPasses < 2 {
            applyPasses += 1
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.applyCurrentPlan(reason: "continuation", allowRemovals: true)
            }
        }
        reapplyAfterPlan()
    }

    /// Plan kararlarını ve özetini günlüğe yazar (gerçek denemede neden
    /// masaüstü açıldığı/kaldığı görülebilsin).
    private func logPlan(_ plan: PlanApply.Output, live: [String: [UInt64]], mode: Mode, reason: String) {
        let lists = live.keys.sorted().map { "\($0)=[\(live[$0]!.map(String.init).joined(separator: ","))]" }
            .joined(separator: " ")
        let creates = plan.creates.keys.sorted().map { "\($0)+\(plan.creates[$0]!)" }.joined(separator: " ")
        Log.app.notice("Plan (\(mode.rawValue, privacy: .public), \(reason, privacy: .public)): live \(lists, privacy: .public); create \(creates.isEmpty ? "none" : creates, privacy: .public); \(plan.moves.count) moves; remove \(plan.removals.map(String.init).joined(separator: ","), privacy: .public)")
        for decision in plan.decisions {
            Log.app.notice("Plan decision: \(decision, privacy: .public)")
        }
    }

    /// Artık temizliği (P1) `delay` sn sonra: planın ötesindeki boş, adsız,
    /// pinsiz masaüstüleri silinir. Geçişten sonra (yönlendirme pencereleri
    /// yerine aldıktan sonra) ve kararlı taramada (açılıştan önce kalan ya da
    /// yönlendirmeyle sonradan boşalan artıklar için) çağrılır.
    private func scheduleCleanup(reason: String, delay: TimeInterval) {
        guard !isDemo, !Self.desktopChangesDisabled else { return }
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.runCleanup(reason: reason, attempt: 0)
        }
    }

    /// Kararlı taramanın sonu: planın ötesinde boş görünen adsız masaüstü
    /// varsa (son taramaya göre) temizlik planlanır. Silmeden önce yeniden
    /// ve canlı denetlenir (C1).
    private func cleanupIfNeeded(spaces: [String: [UInt64]], mode: Mode) {
        guard cleanupTask == nil, transition == nil, !transitionRunning, !store.migrationPending,
              !store.isReadOnly, store.document.enabled, !isPaused else { return }
        if let last = lastCleanupAt, Date().timeIntervalSince(last) < Self.cleanupThrottle { return }
        let contents = lastContents.mapValues { $0.map(\.id) }
        let removable = PlanApply.cleanupRemovals(
            live: PlanApply.holding(live: spaces, roles: screens.heldRoles), contents: contents, plans: store.document.plans[mode], named: allNamedSpaces(),
            pending: Self.pendingQueue(store.document.pendingRemovals, mode: mode).all,
            pinned: pinnedDesktops(mode: mode))
        guard !removable.isEmpty else { return }
        lastCleanupAt = Date()
        scheduleCleanup(reason: "stable", delay: 0)
    }

    /// Hiçbir profilde adlı olan space'ler.
    private func allNamedSpaces() -> Set<UInt64> {
        var named = Set<UInt64>()
        for profile in store.document.profiles { named.formUnion(profile.names.compactMap(\.space)) }
        named.formUnion(store.document.names.compactMap(\.space))
        return named
    }

    /// Etkin kurulumun numara pinleri (kural ve oturum pini): rol → en büyük
    /// masaüstü sırası. O sıraya dek masaüstü silinmez.
    private func pinnedDesktops(mode: Mode) -> [String: Int] {
        var result: [String: Int] = [:]
        let destinations = store.document.rules.flatMap { $0.places(mode) } + Array(sessionPins.values)
        for destination in destinations where destination.nameID == nil {
            result[destination.screen] = max(result[destination.screen] ?? 0, destination.desktop)
        }
        return result
    }

    private func runCleanup(reason: String, attempt: Int) async {
        cleanupTask = nil
        lastCleanupAt = Date()
        guard !isDemo, !store.migrationPending, !store.isReadOnly, store.document.enabled else {
            Log.app.notice("Leftover cleanup (\(reason, privacy: .public)) skipped: upgrade pending, read-only or disabled")
            return
        }
        if transition != nil || transitionRunning || screens.isSettling || desktopOpInFlight || isPaused
            || !SkyLight.shared.canRead {
            guard attempt < 5 else {
                Log.app.notice("Leftover cleanup (\(reason, privacy: .public)) gave up: busy (transition, settling, desktop operation or paused)")
                return
            }
            cleanupTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.runCleanup(reason: reason, attempt: attempt + 1)
            }
            return
        }
        transitionRunning = true
        defer { transitionRunning = false }
        let mode = screens.mode
        let displays = readLiveDisplays()
        guard !displays.isEmpty else { return }
        let live = LiveDesktops(mode: mode, spaces: Self.spaces(displays))
        let fresh = await withCheckedContinuation { continuation in
            Self.planQueue(router: queue).async { continuation.resume(returning: Self.readWindowSpaces()) }
        }
        guard transition == nil, !screens.isSettling, Self.spaces(readLiveDisplays()) == live.spaces else {
            Log.app.notice("Leftover cleanup (\(reason, privacy: .public)) skipped: desktops changed while reading")
            return
        }
        let decisions = PlanApply.cleanupPlan(
            live: PlanApply.holding(live: live.spaces, roles: screens.heldRoles), contents: fresh.contents.mapValues { $0.map(\.id) },
            plans: store.document.plans[mode], named: allNamedSpaces(),
            pending: Self.pendingQueue(store.document.pendingRemovals, mode: mode).all,
            pinned: pinnedDesktops(mode: mode))
        let plans = store.document.plans[mode]
        let counts = live.spaces.keys.sorted().map { "\($0) \(live.spaces[$0]!.count)/\(plans[$0]?.count ?? 0)" }
            .joined(separator: ", ")
        for decision in decisions {
            Log.app.notice("Leftover cleanup (\(reason, privacy: .public)): \(decision.text, privacy: .public)")
        }
        var plan = PlanApply.Output()
        plan.removals = decisions.filter { $0.kept == nil }.map(\.space)
        guard !plan.removals.isEmpty else {
            Log.app.notice("Leftover cleanup (\(mode.rawValue, privacy: .public), \(reason, privacy: .public)): nothing to remove; desktops/plan: \(counts, privacy: .public)")
            return
        }
        let outcome = await execute(plan, expected: live.spaces, refs: [:],
                                    windowSpaces: fresh.windowSpaces, allowRemovals: true)
        commitSnapshot()
        extendQuietWindow(seconds: 3)
        Log.app.notice("Leftover cleanup (\(mode.rawValue, privacy: .public), \(reason, privacy: .public)): removed \(outcome.removed) of \(plan.removals.count) empty desktop(s) beyond the plan; before: \(counts, privacy: .public)")
        // 13.10: kısmi temizlikten sonra kalanlar için yeniden planla. Yalnız
        // ilerleme olduysa (en az bir silme): sonlu, döngüye girmez; her tur
        // boşluğu yeniden ve canlı denetler (C1).
        if !outcome.aborted, outcome.removed > 0, outcome.removed < plan.removals.count {
            Log.app.notice("Leftover cleanup (\(reason, privacy: .public)): \(plan.removals.count - outcome.removed) left; rescheduling")
            scheduleCleanup(reason: "follow-up", delay: 1)
        }
    }

    /// Çökmeden kalan günlük (C6, B 21): taşımalar yapılmışsa bağlar ve
    /// taşıma haritası şimdi kaydedilir (yoksa adın içeriği adsız sayılıp
    /// yeniden taşınırdı); günlük temizlenir.
    private func resumeJournal(_ current: DesktopStateFile.Transition,
                               windowSpaces: [CGWindowID: UInt64]) {
        guard !current.moves.isEmpty else { return }
        let moves = current.moves.map { PlanExecutor.ResolvedMove(window: $0.window, space: $0.space) }
        if PlanExecutor.journalDone(moves, windowSpaces: windowSpaces) {
            var map: [UInt64: UInt64] = [:]
            for (key, value) in current.spaceMap ?? [:] { if let space = UInt64(key) { map[space] = value } }
            store.commitPlan(rebinds: current.rebinds ?? [:], spaceMap: map)
            Log.screens.notice("Desktop transition resumed: \(moves.count) journaled moves were done; bindings committed")
        }
        clearJournal()
    }

    private func clearJournal() {
        guard transition != nil else { return }
        transition?.moves = []
        transition?.rebinds = nil
        transition?.spaceMap = nil
        writeDesktopState()
    }

    /// Etkin profilin planını şimdi uygular, masaüstü silmeden (S1: profil
    /// değişimi, "laptop düzenini kopyala", yedek geri yükleme).
    func applyPlanNow(reason: String) {
        guard !isDemo else { return }
        Task { await applyCurrentPlan(reason: reason, allowRemovals: false) }
    }

    private func applyCurrentPlan(reason: String, allowRemovals: Bool) async {
        guard transition == nil, !transitionRunning, !store.migrationPending, !store.isReadOnly,
              !screens.isSettling, !desktopOpInFlight, SkyLight.shared.canRead else { return }
        transitionRunning = true
        defer { transitionRunning = false }
        let mode = screens.mode
        let displays = readLiveDisplays()
        guard !displays.isEmpty else { return }
        let live = LiveDesktops(mode: mode, spaces: Self.spaces(displays))
        store.setLive(live)
        let fresh = await withCheckedContinuation { continuation in
            Self.planQueue(router: queue).async { continuation.resume(returning: Self.readWindowSpaces()) }
        }
        var refs: [CGWindowID: DesktopStateFile.WindowRef] = [:]
        for list in fresh.contents.values { for ref in list { refs[ref.id] = ref } }
        var otherNamed = Set<UInt64>()
        for profile in store.document.profiles where profile.id != store.document.activeProfileID {
            otherNamed.formUnion(profile.names.compactMap(\.space))
        }
        let input = PlanApply.Input(
            mode: mode, live: live.spaces, contents: fresh.contents.mapValues { $0.map(\.id) },
            names: store.document.names, plans: store.document.plans[mode],
            otherNamed: otherNamed,
            pending: Self.pendingQueue(store.document.pendingRemovals, mode: mode).all,
            pinned: pinnedDesktops(mode: mode),
            allowRemovals: allowRemovals,
            allowMoves: moveHealth.movesAllowed && SkyLight.shared.canMove)
        let plan = PlanApply.compute(PlanApply.holding(input, roles: screens.heldRoles))
        guard !plan.isEmpty else { return }
        logPlan(plan, live: live.spaces, mode: mode, reason: reason)
        let outcome = await execute(plan, expected: live.spaces, refs: refs,
                                    windowSpaces: fresh.windowSpaces, allowRemovals: allowRemovals)
        store.commitPlan(rebinds: outcome.rebinds, spaceMap: outcome.spaceMap)
        commitSnapshot()
        extendQuietWindow(seconds: 3)
        guard !outcome.aborted else {
            Log.app.notice("Plan application (\(reason, privacy: .public)) interrupted: \(outcome.abortReason ?? "", privacy: .public)")
            reapplyAfterPlan()
            return
        }
        report(outcome, plan: plan, mode: mode, reason: reason)
        reapplyAfterPlan()
    }

    /// Planı yürütür (§P.1 adım 5) gerçek Mission Control ve SkyLight ile;
    /// mantık `PlanExecutor.run`'da (testli). Her adımdan önce: ekran
    /// değiştiyse, duraklatıldıysa ya da 30 sn geçtiyse durur; durduktan
    /// sonra hiçbir şey silinmez.
    private func execute(_ plan: PlanApply.Output, expected: [String: [UInt64]],
                         refs: [CGWindowID: DesktopStateFile.WindowRef],
                         windowSpaces: [CGWindowID: UInt64],
                         allowRemovals: Bool) async -> PlanExecutor.Outcome {
        guard !plan.isEmpty, !Self.desktopChangesDisabled else { return PlanExecutor.Outcome() }
        desktopOpInFlight = true
        defer { desktopOpInFlight = false }
        return await PlanExecutor.run(plan, expected: expected, windowSpaces: windowSpaces,
                                      allowRemovals: allowRemovals, world: planWorld(refs: refs))
    }

    /// Yürütücünün gerçek dünyası: Mission Control, SkyLight; ekran değişince,
    /// duraklatılınca ya da 30 sn sonra durur.
    private func planWorld(refs: [CGWindowID: DesktopStateFile.WindowRef]) -> PlanExecutor.World {
        let startScreens = screens.screens
        let deadline = Date().addingTimeInterval(30)
        let pids = refs.mapValues(\.pid)
        return PlanExecutor.World(
            liveSpaces: { [unowned self] in Self.spaces(self.readLiveDisplays()) },
            addDesktop: { [unowned self] role in await self.addDesktopNow(on: role) },
            move: { [unowned self] moves in
                let connected = self.screens.screens
                let batch = moves.map { (window: $0.window, space: $0.space) }
                return await withCheckedContinuation { continuation in
                    self.queue.async {
                        continuation.resume(returning: Self.performMoves(batch, pids: pids,
                                                                         screens: connected))
                    }
                }
            },
            isEmpty: { space in Self.spaceIsEmpty(space) },
            removeDesktop: { [unowned self] role, desktop, space in
                let removed = await self.removeDesktopNow(on: role, desktop: desktop, expected: space)
                if removed { self.ownRemovals.insert(space) }
                return removed
            },
            shouldAbort: { [unowned self] in
                self.screens.screens != startScreens || self.screens.isSettling || self.isPaused
                    || !self.store.document.enabled || Date() > deadline || !AXIsProcessTrusted()
            },
            journal: { [unowned self] moves, rebinds, spaceMap in
                guard self.transition != nil else { return }
                self.transition?.moves = moves.map { .init(window: $0.window, space: $0.space) }
                self.transition?.rebinds = rebinds
                self.transition?.spaceMap = Dictionary(uniqueKeysWithValues: spaceMap.map { (String($0.key), $0.value) })
                self.writeDesktopState()
            })
    }

    /// Pencereleri hedef space'lerine taşır: önce hepsi, sonra 200 ms sonra
    /// doğrulama, olmayanlar yeniden (en çok 3 tur). Ekran değişen pencere
    /// hedef ekrana aynı oranlarla yerleştirilir. Taşınamayanları döndürür.
    nonisolated static func performMoves(_ moves: [(window: CGWindowID, space: UInt64)],
                                         pids: [CGWindowID: pid_t],
                                         screens connected: [ScreenInfo]) -> [CGWindowID] {
        let sky = SkyLight.shared
        guard sky.canMove else { return moves.map(\.window) }
        let displays = sky.displaySpaces(mainUUID: primaryUUID(connected))
        func screen(of space: UInt64) -> ScreenInfo? {
            guard let display = displays.first(where: { $0.spaces.contains { $0.id == space } }) else { return nil }
            return connected.first { $0.uuid == display.displayUUID }
        }
        var remaining = moves.filter { sky.spaces(of: $0.window) != [$0.space] }
        for move in remaining {
            if let pid = pids[move.window], let target = screen(of: move.space) {
                refit(window: move.window, pid: pid, to: target, screens: connected)
            }
        }
        for _ in 0..<3 where !remaining.isEmpty {
            for move in remaining { _ = sky.move(window: move.window, to: move.space) }
            usleep(200_000)
            remaining = remaining.filter { sky.spaces(of: $0.window) != [$0.space] }
        }
        return remaining.map(\.window)
    }

    // MARK: - perf §4.1 A1 ve §4.2 B5

    /// Bayrak `perf.transitionOwnQueue` (A1): geçişin pencere-masaüstü okuması
    /// (`readWindowSpaces`, AX yok) tarama kuyruğunda settle taramasının
    /// arkasında beklemez (düzenekte S→P 3574 → 38 ms).
    nonisolated static var transitionOwnQueue: Bool {
        UserDefaults.standard.bool(forKey: "perf.transitionOwnQueue")
    }
    nonisolated static let planReadQueue = DispatchQueue(label: "deskmap.spaces", qos: .userInitiated)
    /// Plan okumasının kuyruğu: bayrak kapalıyken bugünkü gibi tarama kuyruğu.
    nonisolated static func planQueue(router: DispatchQueue, ownQueue: Bool = transitionOwnQueue) -> DispatchQueue {
        ownQueue ? planReadQueue : router
    }

    /// Pencere başka ekrandaysa çerçevesi hedef ekranda aynı oranlara
    /// taşınır (görünmeyen pencereye AX çerçeve işlemez; o zaman dokunulmaz).
    nonisolated private static func refit(window id: CGWindowID, pid: pid_t, to target: ScreenInfo,
                                          screens connected: [ScreenInfo]) {
        guard let element = AX.element(pid: pid, windowID: id) else { return }
        AXUIElementSetMessagingTimeout(element, 1.0)
        let window = AXWindow(id: id, pid: pid, appName: "", bundleID: "", title: "", element: element)
        guard let frame = AX.frame(of: window),
              let source = connected.first(where: { screen in
                  Coordinates.axRect(fromCocoa: screen.frame, screens: connected)
                      .contains(CGPoint(x: frame.midX, y: frame.midY))
              }), source.id != target.id else { return }
        let sourceArea = Coordinates.axRect(fromCocoa: source.visibleFrame, screens: connected)
        let targetArea = Coordinates.axRect(fromCocoa: target.visibleFrame, screens: connected)
        AX.setFrame(WindowLayout(frame: frame, in: sourceArea).rect(in: targetArea), of: window)
    }

    /// Günlük satırı ve alt çubuk durumu.
    private func report(_ outcome: PlanExecutor.Outcome, plan: PlanApply.Output, mode: Mode, reason: String) {
        let failed = outcome.failedMoves.count + outcome.failedCreates.count
        Log.app.notice("Plan applied (\(mode.rawValue, privacy: .public), \(reason, privacy: .public)): moved \(plan.movedNames) named desktops (\(outcome.moved) windows), created \(outcome.created), removed \(outcome.removed), failed \(failed)")
        if !outcome.failedCreates.isEmpty {
            let role = outcome.failedCreates[0]
            let name = screens.screens.first { $0.id == role }?.name ?? role
            planStatus = PlanStatus(message: L("Could not add a desktop to %@", name), failed: true, at: Date())
            return
        }
        if !outcome.failedMoves.isEmpty {
            let apps = Set(outcome.failedMoves.compactMap { id in windows.first { $0.id == id }?.appName })
                .sorted().joined(separator: ", ")
            planStatus = PlanStatus(
                message: L("%ld windows could not be moved: %@", outcome.failedMoves.count, apps),
                failed: true, at: Date())
            return
        }
        guard plan.movedNames > 0 || outcome.created > 0 || outcome.removed > 0 else { return }
        let text: String
        switch reason {
        case "display", "catch-up", "wake":
            text = mode == .undocked
                ? L("Monitor removed: %ld named desktops placed, %ld added, %ld empty removed",
                    plan.movedNames, outcome.created, outcome.removed)
                : L("Monitor connected: %ld named desktops placed, %ld added, %ld empty removed",
                    plan.movedNames, outcome.created, outcome.removed)
        default:
            text = L("Plan applied: %ld named desktops placed, %ld desktops added",
                     plan.movedNames, outcome.created)
        }
        planStatus = PlanStatus(message: text, failed: false, at: Date())
    }

    func dismissPlanStatus() { planStatus = nil }

    // MARK: - Tablo E: Mission Control'de ekran değiştiren masaüstü

    /// Onaylanmış farkta ekran değiştiren masaüstüleri (izleme bitti,
    /// durum kaydedildi): ayara ve koşullara göre geri al, sor ya da bırak.
    private func handleCrossings(_ crossings: [DesktopRevert.Crossing], catchUp: Bool) {
        guard !crossings.isEmpty else {
            revertHoldUntil = nil
            return
        }
        let now = Date()
        recentReverts = recentReverts.filter { now.timeIntervalSince($0.value) < DesktopRevert.repeatWindow }
        let context = DesktopRevert.Context(
            setting: store.document.missionControlMoves, observedLive: !catchUp,
            movesAllowed: moveHealth.movesAllowed && SkyLight.shared.canMove,
            readOnly: store.isReadOnly, heldRoles: screens.heldRoles,
            lastScreenChange: screens.lastChangeAt, lastWake: lastWakeAt,
            recentReverts: recentReverts, now: now)
        var reverts: [DesktopRevert.Crossing] = [], asks: [DesktopRevert.Crossing] = []
        var blocked: [DesktopRevert.Crossing] = []
        for crossing in crossings {
            let decision = DesktopRevert.decide(crossing, context)
            Log.app.notice("Desktop \(crossing.fromDesktop) on \(crossing.from, privacy: .public) (space \(crossing.space)) moved to desktop \(crossing.toDesktop) on \(crossing.to, privacy: .public) in Mission Control\(catchUp ? " while Deskmap was not running" : "", privacy: .public); \(String(describing: decision), privacy: .public)")
            switch decision {
            case .revert: reverts.append(crossing)
            case .ask: asks.append(crossing)
            case .blocked: blocked.append(crossing)
            case .leave: break
            }
        }
        if let first = blocked.first {
            revertOffer = RevertOffer(
                kind: .info,
                message: L("“%@” stays on %@: desktop moves are off, so it could not be moved back",
                           desktopLabel(first, newSpace: first.space), screenName(first.to)),
                crossings: [], failed: true, at: now)
        }
        if !asks.isEmpty {
            let message = asks.count == 1
                ? L("“%@” was moved from %@ to %@ in Mission Control",
                    desktopLabel(asks[0], newSpace: asks[0].space), screenName(asks[0].from), screenName(asks[0].to))
                : L("%ld desktops were moved to another display in Mission Control", asks.count)
            revertOffer = RevertOffer(kind: .ask, message: message, crossings: asks, failed: false, at: now)
        }
        guard !reverts.isEmpty else {
            revertHoldUntil = nil
            return
        }
        Task { await runReverts(reverts, keeping: false) }
    }

    /// Kart: "Geri al" (SE2, Sor ayarı).
    func acceptRevertOffer() {
        guard let offer = revertOffer, offer.kind == .ask else { return }
        revertOffer = nil
        Task { await runReverts(offer.crossings, keeping: false) }
    }

    /// Kart: "Böyle kalsın" (E4.4): geri alınanı kullanıcının bıraktığı
    /// yere, aynı pin kaydırmasız yolla.
    func keepRevertedDesktops() {
        guard let offer = revertOffer, offer.kind == .reverted else { return }
        revertOffer = nil
        Task { await runReverts(offer.crossings, keeping: true) }
    }

    func dismissRevertOffer() { revertOffer = nil }

    /// Geri almayı (ya da "Böyle kalsın"ı) yürütür; bitene dek yönlendirme
    /// bekler. Mission Control kullanıcıda açıksa kapanması beklenir (E1.2):
    /// açıkken açma isteği onu kapatırdı.
    private func runReverts(_ list: [DesktopRevert.Crossing], keeping: Bool) async {
        guard transition == nil, !transitionRunning, !desktopOpInFlight, !screens.isSettling,
              !store.isReadOnly, SkyLight.shared.canRead else {
            revertHoldUntil = nil
            if !keeping {
                revertOffer = RevertOffer(kind: .ask, message: L("A desktop was moved to another display in Mission Control"),
                                          crossings: list, failed: false, at: Date())
            }
            return
        }
        transitionRunning = true
        defer {
            transitionRunning = false
            revertHoldUntil = nil
        }
        for _ in 0..<150 where MissionControl.isOpen {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard !MissionControl.isOpen else {
            Log.app.notice("Revert: Mission Control stayed open; offering it on a card instead")
            revertOffer = RevertOffer(kind: .ask, message: L("A desktop was moved to another display in Mission Control"),
                                      crossings: list, failed: false, at: Date())
            return
        }
        let mode = screens.mode
        var done: [DesktopRevert.Crossing] = []
        var message: String?
        var failed = false
        for crossing in list {
            let live = Self.spaces(readLiveDisplays())
            guard let index = live[crossing.to]?.firstIndex(of: crossing.space) else {
                Log.app.notice("Revert: space \(crossing.space) is no longer on \(crossing.to, privacy: .public); left alone")
                continue
            }
            var current = crossing
            current.toDesktop = index + 1
            let label = desktopLabel(current, newSpace: current.space)
            let fresh = await withCheckedContinuation { continuation in
                Self.planQueue(router: queue).async { continuation.resume(returning: Self.readWindowSpaces()) }
            }
            var refs: [CGWindowID: DesktopStateFile.WindowRef] = [:]
            for refsOnSpace in fresh.contents.values { for ref in refsOnSpace { refs[ref.id] = ref } }
            desktopOpInFlight = true
            let outcome = await DesktopRevert.run(
                current, contents: fresh.contents.mapValues { $0.map(\.id) },
                windowSpaces: fresh.windowSpaces, world: planWorld(refs: refs))
            desktopOpInFlight = false
            let result = outcome.map { DesktopRevert.result($0, crossing: current) } ?? .failed
            switch result {
            case .reverted(let newSpace), .partial(let newSpace, _):
                store.commitRevert(spaceMap: outcome?.spaceMap ?? [:], from: current.to,
                                   desktop: current.toDesktop, to: current.from, at: current.fromDesktop,
                                   mode: mode)
                if !keeping { recentReverts[newSpace] = Date() }
                done.append(DesktopRevert.reverse(current, newSpace: newSpace))
                if case .partial(_, let stayed) = result {
                    failed = true
                    message = L("“%@” moved back to %@; %ld windows stayed on %@, so that desktop was kept",
                                label, screenName(current.from), stayed, screenName(current.to))
                }
                Log.app.notice("Revert: space \(current.space) on \(current.to, privacy: .public) → desktop \(current.fromDesktop) on \(current.from, privacy: .public) (space \(newSpace))\(keeping ? " (kept where the user put it)" : "", privacy: .public); \(String(describing: result), privacy: .public)")
            case .failed:
                failed = true
                message = L("Could not move “%@” back to %@; it stays on %@",
                            label, screenName(current.from), screenName(current.to))
                Log.app.error("Revert: space \(current.space) could not be moved back (\(outcome?.abortReason ?? "no plan", privacy: .public)); it stays on \(current.to, privacy: .public)")
            }
            commitSnapshot()
        }
        if let message {
            revertOffer = RevertOffer(kind: .info, message: message, crossings: [], failed: failed, at: Date())
        } else if !done.isEmpty {
            let first = done[0]
            if keeping {
                revertOffer = RevertOffer(kind: .info,
                                          message: L("“%@” stays on %@", desktopLabel(first, newSpace: first.space),
                                                     screenName(first.from)),
                                          crossings: [], failed: false, at: Date())
            } else {
                revertOffer = RevertOffer(
                    kind: .reverted,
                    message: done.count == 1
                        ? L("“%@” moved back to %@", desktopLabel(first, newSpace: first.space), screenName(first.to))
                        : L("%ld desktops moved back to their displays", done.count),
                    crossings: done, failed: false, at: Date())
            }
        }
        reapplyAll()
        scheduleFollowUp(after: 300)
    }

    /// Kart metni: adlı masaüstünün adı, değilse "Masaüstü N" (eski sırası).
    private func desktopLabel(_ crossing: DesktopRevert.Crossing, newSpace: UInt64) -> String {
        store.document.nameRecord(space: newSpace)?.name ?? L("Desktop %ld", crossing.fromDesktop)
    }

    private func screenName(_ role: String) -> String {
        screens.screens.first { $0.id == role }?.name ?? role
    }

    /// "Yeniden dene": planı şimdi uygular (silme yok).
    func retryPlan() {
        planStatus = nil
        applyPlanNow(reason: "retry")
    }

    /// M1: geçiş raporundaki plan ötesi boş masaüstüleri (her biri hemen
    /// önce yeniden boşluk denetlenerek) silinir.
    func removeEmptyDesktops(_ spaces: [UInt64]) async -> Int {
        guard !desktopOpInFlight else { return 0 }
        desktopOpInFlight = true
        defer { desktopOpInFlight = false }
        var removed = 0
        for space in spaces.reversed() {
            let current = readLiveDisplays()
            guard let display = current.first(where: { $0.spaces.contains(space) }),
                  display.spaces.count > 1, let index = display.spaces.firstIndex(of: space),
                  !store.document.namedSpacesInAnyProfile.contains(space),
                  Self.spaceIsEmpty(space) == true else { continue }
            if await removeDesktopNow(on: display.role, desktop: index + 1, expected: space) {
                removed += 1
                ownRemovals.insert(space)
            }
        }
        if removed > 0 { commitSnapshot() }
        scheduleFollowUp(after: 300)
        return removed
    }

    /// Bekleyen silmeler (saf): `all` bütün kurulumların kimlikleri, `active`
    /// yalnız `mode` kurulumununkiler, `unresolved` kimliği bilinmeyen silmesi
    /// olan ekranlar.
    nonisolated static func pendingQueue(_ pending: [String: [PendingRemoval]], mode: Mode)
        -> (all: Set<UInt64>, active: Set<UInt64>, unresolved: Set<String>) {
        var all = Set<UInt64>(), active = Set<UInt64>(), unresolved = Set<String>()
        for (key, list) in pending where !list.isEmpty {
            let parts = Document.splitNameKey(key)
            for removal in list {
                if let space = removal.space {
                    all.insert(space)
                    if parts?.mode == mode { active.insert(space) }
                } else {
                    unresolved.insert(parts?.screen ?? key)
                }
            }
        }
        return (all, active, unresolved)
    }

    /// Ekran kilitli mi: kilitliyken macOS erişilebilirlikten pencere
    /// vermez (liste boş gelir); kilitlenmeden önceki içerik korunmalı.
    nonisolated static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    /// Ekranın `desktop`. masaüstünün şu anki kimliği (SkyLight'tan taze).
    func currentSpace(on screenID: String, desktop: Int) -> UInt64? {
        guard let info = screens.screens.first(where: { $0.id == screenID }),
              let display = SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(screens.screens))
                .first(where: { $0.displayUUID == info.uuid }),
              desktop >= 1, desktop <= display.desktops.count
        else { return nil }
        return display.desktops[desktop - 1].id
    }

    /// Bekleyen silmenin şu anki masaüstü sırası (saf): kimlik varsa
    /// yalnız kimlikle (bulunamazsa nil, sıraya düşülmez); yoksa sıra.
    nonisolated static func pendingIndex(_ removal: PendingRemoval, desktops: [UInt64]) -> Int? {
        if let space = removal.space {
            return desktops.firstIndex(of: space).map { $0 + 1 }
        }
        return removal.desktop <= desktops.count ? removal.desktop : nil
    }

    /// Ekranın bu andaki gerçek masaüstü sayısı (SkyLight'tan taze).
    private func liveDesktopCount(uuid: String) -> Int? {
        SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(screens.screens))
            .first { $0.displayUUID == uuid }?.desktops.count
    }

    /// Eski sürümlerin sıraya aldığı gerçek masaüstü silmelerini (etkin
    /// kurulumunkiler) yapar. Başarılı ya da artık olmayan girdi kuyruktan
    /// düşer; silinen masaüstünün kaydı Mission Control'deki silme gibidir
    /// (sıraya alan kurulumun numaraları zaten kaymıştı: yalnız öbürleri
    /// kayar). Başarısız girdi ve sonrakiler kuyrukta kalır, bildirilir, bu
    /// oturumda aynı kuyruk bir kez denenir.
    private func runPendingRemovals() {
        guard !desktopOpInFlight, !screens.isSettling, transition == nil, !transitionRunning,
              !desktopCounts.isEmpty else { return }
        let mode = screens.mode
        for screen in screens.screens {
            let removals = store.document.pendingRemovals(mode: mode, screen: screen.id)
            guard !removals.isEmpty else { continue }
            let key = "remove|\(mode.rawValue)|\(screen.id)|\(removals.count)"
            guard plannedAttempts.begin(key) else { continue }
            desktopOpInFlight = true
            let uuid = screen.uuid, screenID = screen.id
            Log.app.notice("Removing \(removals.count) desktop(s) queued for \(screenID, privacy: .public)")
            Task { [weak self] in
                guard let self else { return }
                var outcome = PlannedAttempts.Outcome.done
                defer {
                    self.plannedAttempts.finish(key, outcome)
                    self.desktopOpInFlight = false
                    self.commitSnapshot()
                    self.scheduleFollowUp(after: 300)
                }
                for removal in removals {
                    guard self.screens.mode == mode, !self.screens.isSettling else {
                        outcome = .interrupted
                        return
                    }
                    let desktops = SkyLight.shared
                        .displaySpaces(mainUUID: Self.primaryUUID(self.screens.screens))
                        .first { $0.displayUUID == uuid }?.desktops.map(\.id) ?? []
                    guard desktops.count > 1,
                          let index = Self.pendingIndex(removal, desktops: desktops) else {
                        Log.app.notice("Queued removal skipped on \(screenID, privacy: .public): desktop not found")
                        self.store.dropFirstPendingRemoval(mode: mode, screen: screenID)
                        continue
                    }
                    let removedSpace = desktops[index - 1]
                    guard await self.removeDesktopNow(on: screenID, desktop: index,
                                                      expected: removedSpace) else {
                        guard self.screens.mode == mode, !self.screens.isSettling else {
                            outcome = .interrupted
                            return
                        }
                        self.store.report(L("Could not remove desktop %ld on %@", index, screenID))
                        outcome = .failed
                        return
                    }
                    self.store.dropFirstPendingRemoval(mode: mode, screen: screenID)
                    self.store.recordDeletion(space: removedSpace, role: screenID, desktop: index,
                                              mode: mode,
                                              shiftModes: Mode.allCases.filter { $0 != mode })
                    self.shiftSessionPins(screen: screenID, removed: index)
                    self.ownRemovals.insert(removedSpace)
                }
            }
            return
        }
    }

    // MARK: - Elle taşıma

    /// Pinsiz bir pencereyi tek seferlik hedef masaüstüne taşır; kural
    /// yazılmaz. Ekran değişiyorsa ve pencere görünürse çerçeve önce hedef
    /// ekranda aynı oranlara taşınır (görünmeyen pencereye AX çerçeve
    /// uygulanmadığından o durumda yalnızca masaüstü değişir).
    func moveWindow(_ windowID: CGWindowID, to placement: Placement) {
        let connected = screens.screens
        // Son taramadaki pid ile AX öğesi doğrudan üretilir; bütün
        // uygulamaları yeniden taramak yalnızca bu yol tutmazsa gerekir.
        let snapshot = windows.first { $0.id == windowID }
        // Tam ekran uygulamanın penceresine dokunulmaz (README kuralı).
        if snapshot?.fullscreen != nil { return }
        let movesAllowed = moveHealth.movesAllowed
        let token = generation.token()
        queue.async { [weak self] in
            let sky = SkyLight.shared
            guard sky.canRead, sky.canMove, movesAllowed,
                  let target = connected.first(where: { $0.id == placement.screen }),
                  let display = sky.displaySpaces(mainUUID: Self.primaryUUID(connected))
                    .first(where: { $0.displayUUID == target.uuid }),
                  !display.desktops.isEmpty
            else { return }
            let desktops = display.desktops
            let index = min(placement.desktop, desktops.count)
            let space = desktops[index - 1]

            var window: AXWindow?
            var frame: CGRect?
            if let snapshot, let element = AX.element(pid: snapshot.pid, windowID: windowID) {
                AXUIElementSetMessagingTimeout(element, 1.0)
                let direct = AXWindow(
                    id: windowID, pid: snapshot.pid, appName: snapshot.appName,
                    bundleID: snapshot.bundleID, title: snapshot.title, element: element)
                if let directFrame = AX.frame(of: direct) {
                    window = direct
                    frame = directFrame
                }
            }
            if frame == nil, let scanned = AX.allWindows().first(where: { $0.id == windowID }) {
                window = scanned
                frame = AX.frame(of: scanned)
            }

            if let window, let frame,
               let source = connected.first(where: { screen in
                   Coordinates.axRect(fromCocoa: screen.frame, screens: connected)
                       .contains(CGPoint(x: frame.midX, y: frame.midY))
               }),
               source.id != target.id {
                let sourceArea = Coordinates.axRect(fromCocoa: source.visibleFrame, screens: connected)
                let targetArea = Coordinates.axRect(fromCocoa: target.visibleFrame, screens: connected)
                let layout = WindowLayout(frame: frame, in: sourceArea)
                guard token.isCurrent else {
                    Log.routing.notice("Manual move dropped: routing changed (window \(windowID))")
                    return
                }
                AX.setFrame(layout.rect(in: targetArea), of: window)
                // Uygulama boyutu reddettiyse (en küçük boyutu hedeften
                // büyük) pencere hedef ekranın sağından/altından taşar;
                // pinsiz pencereye tarama düzen vermez, burada içeri çekilir.
                if let after = AX.frame(of: window),
                   let pulled = layout.overflowFix(for: after, in: targetArea) {
                    guard token.isCurrent else {
                        Log.routing.notice("Manual move dropped: routing changed (window \(windowID))")
                        return
                    }
                    AX.setFrame(pulled, of: window)
                }
            }

            let appName = window?.appName ?? snapshot?.appName ?? "?"
            Log.routing.info("""
                Manual move: \(appName, privacy: .public) [\(windowID)] → \
                \(target.name, privacy: .public) · Desktop \(index)
                """)
            guard token.isCurrent else {
                Log.routing.notice("Manual move dropped: routing changed (window \(windowID))")
                return
            }
            let result = sky.move(window: windowID, to: space.id)
            if result == .unavailable || result == .noEffect {
                Log.routing.error("Manual move failed (\(String(describing: result), privacy: .public), window \(windowID))")
            }
            Task { @MainActor in
                self?.noteMove(window: windowID, space: space.id, result: result)
                self?.scheduleFollowUp(after: 200)
            }
        }
    }

    // MARK: - Tarama

    /// Taramanın seçim girdileri: yönlendirme kapalıyken (duraklama yok,
    /// ama kurallar kapalı, ekranlar yatışıyor ya da plan yürütülüyor)
    /// kural ve oturum pini verilmez.
    private func routingInputs() -> (routing: Bool, rules: [Rule],
                                     sessionPins: [CGWindowID: Destination]) {
        let routing = store.document.enabled && !screens.isSettling && !planHoldsRouting(now: Date())
        return (routing, routing ? store.document.rules : [], routing ? sessionPins : [:])
    }

    /// Bir taramanın seçim sonucu (§B).
    struct Selection: Equatable {
        /// Pencere → geçerli hedef; hedefi olmayan pencere yok.
        var matches: [CGWindowID: Routing.Match] = [:]
        /// Bağları güncellenmiş seçim durumu.
        var context = Routing.Context()
        var firstSeen: [CGWindowID: Date] = [:]
        /// En erken bekleme bitişine kalan süre (sn); bekleyen yoksa nil.
        var heldUntil: TimeInterval?
    }

    /// Taramanın seçim adımı (saf): yapışkan bağlar, genel başlıklı yeni
    /// pencereler ve tam başlık sahipleriyle her pencere için arayüzle aynı
    /// seçim (oturum pini, yoksa bağlı kural, yoksa bu modda hedefi olan en
    /// özgül eşleşen kural). `initial`: ilk tarama; o an açık pencereler
    /// beklemez.
    nonisolated static func select(
        windows: [WindowSnapshot], rules: [Rule], sessionPins: [CGWindowID: Destination],
        mode: Mode, bindings: [CGWindowID: Routing.Binding], firstSeen: [CGWindowID: Date],
        initial: Bool, now: Date
    ) -> Selection {
        var selection = Selection()
        var context = Routing.Context(bindings: bindings)
        for window in windows {
            let seen = firstSeen[window.id] ?? (initial ? .distantPast : now)
            selection.firstSeen[window.id] = seen
            if Routing.isHeld(title: window.title, appName: window.appName, firstSeen: seen, now: now,
                              titleRules: Routing.hasTitleRule(rules, bundleID: window.bundleID,
                                                               appName: window.appName)) {
                context.held.insert(window.id)
                // Bekleme bitince bir tarama daha (başlık değişmese de).
                let due = seen.addingTimeInterval(Routing.genericTitleGrace).timeIntervalSince(now)
                selection.heldUntil = min(selection.heldUntil ?? due, due)
            }
        }
        context.exactOwned = Routing.exactOwners(
            rules: rules,
            windows: windows.filter { !context.held.contains($0.id) }
                .map { ($0.bundleID, $0.appName, $0.title) })
        for window in windows {
            let resolved = Routing.resolve(
                rules: rules, sessionPins: sessionPins, mode: mode, windowID: window.id,
                bundleID: window.bundleID, appName: window.appName, title: window.title,
                document: window.document, context: context)
            context.bindings[window.id] = resolved.binding
            selection.matches[window.id] = resolved.match
        }
        selection.context = context
        return selection
    }

    /// Taramanın seçim durumunu Router'a işler: bağlar, tarama sürerken
    /// verilen bağlar (pin kaldırma), ilk görülme anları ve arayüzün bağlamı.
    /// `live`: yaşayan pencereler (boşsa budama yok).
    private func acceptSelection(_ swept: Routing.Context, firstSeen sweptFirstSeen: [CGWindowID: Date],
                                 routing: Bool, profileID: String, live: Set<CGWindowID>) {
        // Yönlendirme kapalıyken (duraklama, yatışma) kural listesi boş
        // geçer: bağlar o taramadan alınmaz, yoksa hepsi düşerdi.
        var bindings = (routing ? swept.bindings : bindings(for: profileID))
            .merging(bindingOverrides) { $1 }
        bindingsProfileID = profileID
        bindingOverrides = [:]
        // Listede olmayan ama yaşayan (ör. geçici olarak masaüstüsüz)
        // pencereler ilk görülme anını korur, dönünce yeniden beklemez.
        var firstSeen = self.firstSeen.merging(sweptFirstSeen) { old, _ in old }
        if !live.isEmpty {
            bindings = Routing.prunedBindings(bindings, alive: live)
            firstSeen = firstSeen.filter { live.contains($0.key) }
        }
        self.bindings = bindings
        self.firstSeen = firstSeen
        sweptAny = true
        var context = swept
        context.bindings = bindings
        if context != routingContext { routingContext = context }
    }

    /// `profileID` profiline ait bağlar; başka profilin bağları boş sayılır.
    private func bindings(for profileID: String) -> [CGWindowID: Routing.Binding] {
        profileID == bindingsProfileID ? bindings : [:]
    }

    /// Taramanın seçim adımını AX/SkyLight olmadan yürütür: `sweep` ile aynı
    /// girdiler, aynı `select` ve aynı birleştirme; pencereler dışarıdan
    /// verilir ve hiçbiri taşınmaz. Testler gerçek Router'ı bununla sürer.
    @discardableResult
    func sweepSelection(windows: [WindowSnapshot], now: Date = Date()) -> [CGWindowID: Routing.Match] {
        let (routing, rules, sessionPins) = routingInputs()
        let profileID = store.document.activeProfileID
        let selection = Self.select(
            windows: windows, rules: rules, sessionPins: sessionPins, mode: screens.mode,
            bindings: bindings(for: profileID), firstSeen: firstSeen, initial: !sweptAny, now: now)
        if windows != self.windows { self.windows = windows }
        acceptSelection(selection.context, firstSeen: selection.firstSeen,
                        routing: routing, profileID: profileID, live: Set(windows.map(\.id)))
        return selection.matches
    }

    func sweep() {
        guard !isDemo, AXIsProcessTrusted(), !isPaused else { return }
        if isSweeping {
            // Tarama sürerken gelen olay kaybolmasın; bitince bir tur daha.
            sweepRequested = true
            PerfStats.shared.count("sweepCoalesced")
            return
        }

        // Duraklatılmışken kural uygulanmaz ama pencereler yine listelenir.
        // Ekran değişimi yatışırken de öyle: yarım düzenlenmiş ekranlara
        // göre taşıma yapılmaz; yatışınca `settled` → `reapplyAll`.
        // Özgüllük sıralamasını `Routing.select` yapar.
        // Plan uygulanırken yönlendirme durur: adların bağları kaydedilmeden
        // kural pencerelerini eski yerlerine geri taşımasın (§P.1 adım 6).
        let (routing, rules, sessionPins) = routingInputs()
        // Duraklatılmışken de geçici pinli pencereler listelenir ve yaşam
        // denetimi sürer.
        let sessionIDs = Set(self.sessionPins.keys)
        // Ekranlar yatışırken mod geçici olabilir; izin yatışınca
        // (`settled` → `reapplyAll`) kalıcı moda göre denetlenir.
        // Duraklatılmışken de denetlenir (pin/mod değişimi kaçmasın).
        if !screens.isSettling { validateFreeMoves() }
        let free = Self.activeFreeMoves(freeMoves, now: Date())
        let mode = screens.mode
        let connected = screens.screens
        let applied = self.applied
        let attempts = self.attempts
        let refusedSizes = self.refusedSizes
        let lastAttempts = self.lastAttempts
        let movesAllowed = moveHealth.movesAllowed
        // Ad hedefleri: adın bağlı space'i (geçiş beklerken tutulur).
        let nameSpaces = Dictionary(store.document.names.compactMap { name in
            name.space.map { (name.id, $0) } }, uniquingKeysWith: { a, _ in a })
        let holdNames = store.migrationPending || store.upgradeUndone
        let heldRoles = screens.heldRoles
        let profileID = store.document.activeProfileID
        let bindings = bindings(for: profileID)
        let firstSeen = self.firstSeen
        let initial = !sweptAny
        let token = generation.token()
        isSweeping = true
        sweepRequested = false
        lastSweepAt = Date()
        let perfRequested = PerfStats.now()

        queue.async { [weak self] in
            PerfStats.shared.add("queueWait", PerfStats.ms(since: perfRequested))
            let perfRoute = PerfStats.now()
            let perfState = PerfStats.signposter.beginInterval("route")
            defer { PerfStats.signposter.endInterval("route", perfState) }
            let outcome = Self.route(rules: rules, sessionPins: sessionPins,
                                     sessionIDs: sessionIDs, free: free,
                                     mode: mode, screens: connected,
                                     applied: applied, attempts: attempts,
                                     refusedSizes: refusedSizes,
                                     lastAttempts: lastAttempts, movesAllowed: movesAllowed,
                                     nameSpaces: nameSpaces, holdNames: holdNames,
                                     heldRoles: heldRoles,
                                     bindings: bindings, firstSeen: firstSeen, initial: initial,
                                     token: token)
            PerfStats.shared.add("route", PerfStats.ms(since: perfRoute))
            let perfHop = PerfStats.now()
            Task { @MainActor in
                guard let self else { return }
                PerfStats.shared.add("mainHop", PerfStats.ms(since: perfHop))
                let perfMerge = PerfStats.now()
                defer { PerfStats.shared.add("mainMerge", PerfStats.ms(since: perfMerge)) }
                self.isSweeping = false
                var applied = Self.acceptApplied(
                    outcome.applied, floors: self.appliedFloor,
                    globalFloor: self.appliedGlobalFloor)
                var attempts = outcome.attempts
                var lastAttempts = outcome.lastAttempts
                if self.invalidateAll {
                    attempts = [:]
                    lastAttempts = [:]
                } else if !self.invalidatedPrefixes.isEmpty {
                    let prefixes = self.invalidatedPrefixes
                    attempts = attempts.filter { entry in
                        !prefixes.contains { entry.key.hasPrefix($0) } }
                    lastAttempts = lastAttempts.filter { entry in
                        !prefixes.contains { entry.key.hasPrefix($0) } }
                }
                self.invalidateAll = false
                self.invalidatedPrefixes = []
                // Kapanmış pencerelerin düzen/deneme kayıtları birikmesin.
                let live = outcome.liveWindows
                if !live.isEmpty {
                    func isLive(_ key: String) -> Bool {
                        guard let end = key.firstIndex(of: "|"),
                              let id = CGWindowID(key[..<end]) else { return true }
                        return live[id] != nil
                    }
                    applied = applied.filter { live[$0.key] != nil }
                    let freeMoves = Self.liveFreeMoves(self.freeMoves, alive: Set(live.keys))
                    if freeMoves != self.freeMoves { self.freeMoves = freeMoves }
                    self.freeTargets = self.freeTargets.filter { live[$0.key] != nil }
                    self.appliedFloor = self.appliedFloor.filter { live[$0.key] != nil }
                    attempts = attempts.filter { isLive($0.key) }
                    lastAttempts = lastAttempts.filter { isLive($0.key) }
                    self.refusedSizes = self.refusedSizes.filter { isLive($0.key) }
                }
                self.refusedSizes.merge(outcome.refusedSizes) { $1 }
                self.acceptSelection(outcome.context, firstSeen: outcome.firstSeen,
                                     routing: routing, profileID: profileID, live: Set(live.keys))
                self.placeStatus = Self.placeStatus(choices: outcome.placeChoices,
                                                    unplaced: outcome.unplaced)
                self.applied = applied
                self.attempts = attempts
                self.lastAttempts = lastAttempts
                self.screenHooks.fire(self.screenMemory.update(
                    windows: outcome.snapshots, screens: connected,
                    settling: self.screens.isSettling))
                self.captureReopenTargets(outcome.snapshots)
                // Masaüstü içeriği (kararlı durum ve ad geçişi için); ekranlar
                // yatışmışken, aynı kurulumda ve ekran kilitli değilken.
                if !self.screens.isSettling, mode == self.screens.mode,
                   connected == self.screens.screens, !Self.screenIsLocked() {
                    self.lastContents = outcome.contents
                    self.lastWindowSpaces = outcome.windowSpaces
                    self.sweptOnce = true
                }
                if outcome.snapshots != self.windows {
                    Self.logFullscreenChange(from: self.windows, to: outcome.snapshots)
                    self.windows = outcome.snapshots
                }
                self.observeIdentity(outcome.snapshots)
                self.lastSignature = Self.signatureAfterSweep(
                    tick: self.lastSignature, swept: outcome.signature)
                self.expireSessionPins(live: outcome.liveWindows)
                // Önceki taşımaların doğrulaması, sonra bu taramanın taşımaları.
                let check = PendingMove.verify(pending: self.pendingMoves,
                                               observed: outcome.observedSpaces, now: Date())
                self.pendingMoves = check.remaining
                for result in check.results {
                    self.recordMoveCheck(window: result.window, verified: result.verified)
                }
                for move in outcome.moves where self.moveHealth.movesAllowed {
                    self.noteMove(window: move.window, space: move.space, result: move.result)
                }
                if outcome.desktopCounts != self.desktopCounts {
                    self.desktopCounts = outcome.desktopCounts
                }
                self.followDesktops()
                self.runPendingRemovals()
                self.sweepDeadline = Self.nextSweepDeadline(
                    now: Date(), pendingSessionMisses: !self.sessionMisses.isEmpty,
                    attempts: self.attempts, lastAttempts: self.lastAttempts,
                    backoffEnd: AX.nextBackoffEnd())
                if outcome.stale {
                    Log.routing.info("Sweep cut short: routing changed while it ran")
                }
                if outcome.needsFollowUp || outcome.stale || self.sweepRequested {
                    self.scheduleFollowUp(after: outcome.needsFollowUp ? 200 : 20)
                } else if let held = outcome.heldUntil {
                    self.scheduleFollowUp(after: UInt64(max(0.05, held + 0.05) * 1000))
                }
                var status = self.status
                status.routedWindows = outcome.routed
                status.unresponsive = outcome.unresponsive
                if let action = outcome.lastAction {
                    status.lastAction = action
                    status.lastActionAt = Date()
                }
                if status != self.status { self.status = status }
                self.recordActions(outcome.actions)
            }
        }
    }

    private struct Outcome {
        var applied: [CGWindowID: AppliedEntry]
        var attempts: [String: Int]
        /// Bu taramada reddi görülen boyutlar (`refusedSizes`'a eklenir).
        var refusedSizes: [String: CGSize] = [:]
        var lastAttempts: [String: Date]
        var snapshots: [WindowSnapshot] = []
        /// Pencere sunucusunun bildiği pencere numaraları → pid (oturum
        /// pinlerinin yaşayıp yaşamadığı buradan anlaşılır).
        var liveWindows: [CGWindowID: pid_t] = [:]
        var unresponsive: [String] = []
        /// Bağlı ekranlardaki gerçek masaüstü sayıları.
        var desktopCounts: [String: Int] = [:]
        /// Tarama sürerken yönlendirme nesli değişti; yan etkiler kesildi.
        var stale = false
        /// Space durumu bilinmediği için yönlendirilmeyen pencere sayısı.
        var unknownSpaces = 0
        /// Bu taramada okunan pencere space'leri (taşıma doğrulaması için).
        var observedSpaces: [CGWindowID: [UInt64]] = [:]
        /// Tek normal masaüstündeki pencereler: pencere → space ve space → içerik.
        var windowSpaces: [CGWindowID: UInt64] = [:]
        var contents: [UInt64: [DesktopStateFile.WindowRef]] = [:]
        /// Bu taramada yapılan masaüstü taşımaları ve sonuçları.
        var moves: [(window: CGWindowID, space: UInt64, result: SkyLight.MoveResult)] = []
        /// Taramanın başında okunan sunucu imzası (`perf.sweepSignature`).
        var signature: AX.WindowServerSignature?
        var routed = 0
        var lastAction: String?
        /// Bu taramada başlatılan taşımalar ("Son hareketler" için; yalnız
        /// ilk deneme).
        var actions: [String] = []
        /// Bir pencere taşındı ya da düzeni henüz oturmadı; kısa süre sonra
        /// yeniden dene.
        var needsFollowUp = false
        /// Taramanın seçim durumu (bağlar güncel) ve ilk görülme anları.
        var context = Routing.Context()
        var firstSeen: [CGWindowID: Date] = [:]
        /// En erken bekleme bitişine kalan süre (sn); bekleyen yoksa nil.
        var heldUntil: TimeInterval?
        /// Pencerenin pininden kullanılan yer (sıra ya da yedek).
        var placeChoices: [CGWindowID: Routing.PlaceChoice] = [:]
        /// Pini olan ama bu taramada yeri bulunmayan (dokunulmayan) pencereler.
        var unplaced: Set<CGWindowID> = []
    }

    /// Bir pencerenin taramada bir kez okunan durumu; anlık görüntü,
    /// yerleşim ve yönlendirme aynı okumayı kullanır (pencere başına
    /// space, çerçeve ve simge durumu için tekrar IPC yapılmaz).
    struct WindowState {
        /// Bulunduğu space kimlikleri (SkyLight yoksa boş).
        let spaces: [UInt64]
        /// Space'lerden biri normal masaüstü değil (tam ekran uygulama).
        let isFullscreen: Bool
        let frame: CGRect?
        let isMinimized: Bool
        /// Space üyeliği ve türleri okunabildi. false ise pencerenin nerede
        /// olduğu bilinmiyor: yalnız listelenir, taşınmaz, düzen verilmez.
        var spacesKnown: Bool = true
    }

    /// Pencere yönlendirilebilir mi (saf): SkyLight okuması varken space
    /// durumu bilinmiyorsa (okuma hatası, boş üyelik, türü bilinmeyen
    /// space) hayır; yanlış masaüstüne taşıma ya da görünmeyen pencereye
    /// düzen vermek yerine hiçbir şey yapılmaz (P0-3). SkyLight hiç yoksa
    /// yalnız ekran ve düzen uygulanır, eski davranış.
    nonisolated static func canRoute(_ state: WindowState, spacesReadable: Bool) -> Bool {
        !spacesReadable || state.spacesKnown
    }

    /// Space listesi okunabildi ama boş: pencere hiçbir masaüstünde değil
    /// (sunucuda duran ama gösterilmeyen yardımcı pencere). Gizli (⌘H) ve
    /// küçültülmüş pencereler space'lerini korur (ölçüldü, 25.09.2026), bu
    /// yüzden elenmez. Oturum pini olan pencere elenmez. Okunamayan (nil)
    /// liste "bilinmiyor" sayılır, elenmez.
    nonisolated static func isSpaceless(_ read: [UInt64]?, pinned: Bool) -> Bool {
        !pinned && read?.isEmpty == true
    }

    /// Okunan space listesi ve türlerinden pencere durumu (saf).
    nonisolated static func spaceState(
        spaces read: [UInt64]?, type: (UInt64) -> Int?
    ) -> (spaces: [UInt64], isFullscreen: Bool, known: Bool) {
        guard let read, !read.isEmpty else { return ([], false, false) }
        let types = read.map(type)
        let known = !types.contains { $0 == nil }
        return (read, types.contains { $0 != nil && $0 != 0 }, known)
    }

    /// Düzen deneme sınırları `Routing.maxAttempts` / `Routing.quickAttempts`;
    /// masaüstü taşıması `Routing.maxMoveAttempts` / `Routing.moveRetryInterval`.
    nonisolated private static func route(
        rules: [Rule], sessionPins: [CGWindowID: Destination], sessionIDs: Set<CGWindowID>,
        free: Set<CGWindowID>, mode: Mode, screens: [ScreenInfo], applied: [CGWindowID: AppliedEntry],
        attempts: [String: Int], refusedSizes: [String: CGSize],
        lastAttempts: [String: Date], movesAllowed: Bool,
        nameSpaces: [String: UInt64] = [:], holdNames: Bool = false,
        heldRoles: Set<String> = [],
        bindings: [CGWindowID: Routing.Binding] = [:], firstSeen: [CGWindowID: Date] = [:],
        initial: Bool = false,
        token: RoutingGeneration.Token
    ) -> Outcome {
        var outcome = Outcome(applied: applied, attempts: attempts, lastAttempts: lastAttempts)
        let sky = SkyLight.shared
        let displays = sky.displaySpaces(mainUUID: Self.primaryUUID(screens))
        let visibleSpaces = Set(displays.map(\.current))
        // Space türleri ekran listesinden; listede olmayan kimlik için IPC.
        let spaceTypes = SkyLight.spaceTypes(of: displays)
        outcome.desktopCounts = Self.desktopCounts(displays: displays, screens: screens)
        func spaceType(_ id: UInt64) -> Int? { spaceTypes[id] ?? sky.type(of: id) }
        // Pencere sunucusu taramada bir kez okunur: 2. aşama listeleme ve
        // yaşam denetimi aynı sonuçtan türer.
        // Zamanlayıcı turu imzayı taramanın gördüğüyle karşılaştırsın (§5.4).
        if sweepSignature { outcome.signature = AX.windowServerSignature() }
        let perfList = PerfStats.now()
        let server = AX.windowServerList()
        PerfStats.shared.add("windowList", PerfStats.ms(since: perfList))
        let perfAll = PerfStats.now()
        let windows = AX.allWindows(alwaysInclude: sessionIDs, server: server)
        PerfStats.shared.add("allWindows", PerfStats.ms(since: perfAll))
        outcome.unresponsive = AX.unresponsiveApps()
        // Oturum pinlerinin yaşam denetimi ve kapalı pencere kayıtlarının
        // budanması için.
        outcome.liveWindows = Self.liveWindows(
            server: server.live, ax: windows.map { ($0.id, $0.pid) })

        // Pencere başına durum bir kez okunur.
        var states: [CGWindowID: WindowState] = [:]
        var spaceless: Set<CGWindowID> = []
        /// Pencerenin belge yolu (AXDocument): "bu pencere" pininin anahtarı.
        var documents: [CGWindowID: String] = [:]
        var tabGroups: [CGWindowID: String] = [:]
        for window in windows {
            let read = sky.canRead ? sky.spaces(of: window.id) : nil
            outcome.observedSpaces[window.id] = read ?? []
            if Self.isSpaceless(read, pinned: sessionIDs.contains(window.id)) {
                spaceless.insert(window.id)
                continue
            }
            let space = Self.spaceState(spaces: read, type: spaceType)
            if space.known, !space.isFullscreen, space.spaces.count == 1 {
                outcome.windowSpaces[window.id] = space.spaces[0]
                outcome.contents[space.spaces[0], default: []].append(
                    .init(id: window.id, pid: window.pid, bundleID: window.bundleID))
            }
            states[window.id] = WindowState(
                spaces: space.spaces,
                isFullscreen: space.isFullscreen,
                frame: AX.frame(of: window),
                isMinimized: AX.isMinimized(window),
                spacesKnown: space.known)
            documents[window.id] = AX.document(of: window)
            if window.bundleID == "com.apple.Safari" { tabGroups[window.id] = AX.safariTabGroup(of: window) }
        }
        func windowState(_ window: AXWindow) -> WindowState {
            states[window.id] ?? WindowState(spaces: [], isFullscreen: false,
                                             frame: nil, isMinimized: false, spacesKnown: false)
        }

        // Hiçbir masaüstünde olmayan pencereler (ör. cmux'un 64 pt'lik
        // görünmez yardımcı penceresi) haritaya ve yönlendirmeye girmez;
        // eskiden "Desktop 1"e düşüp orada hayalet pencere gibi görünüyordu.
        let listed = windows.filter { !spaceless.contains($0.id) }
        outcome.snapshots = listed.map { window in
            let state = windowState(window)
            return WindowSnapshot(
                id: window.id, pid: window.pid, appName: window.appName, bundleID: window.bundleID,
                title: window.title,
                placement: Self.placement(of: state, displays: displays, screens: screens),
                frame: state.frame,
                isMinimized: state.isMinimized,
                fullscreen: Self.fullscreenSlot(of: state, displays: displays, screens: screens),
                document: documents[window.id],
                tabGroup: tabGroups[window.id])
        }.sorted {
            let a = $0.appName.localizedCaseInsensitiveCompare($1.appName)
            return a == .orderedSame ? $0.id < $1.id : a == .orderedAscending
        }

        let now = Date()
        let selection = Self.select(
            windows: outcome.snapshots, rules: rules, sessionPins: sessionPins, mode: mode,
            bindings: bindings, firstSeen: firstSeen, initial: initial, now: now)
        outcome.firstSeen = selection.firstSeen
        outcome.heldUntil = selection.heldUntil
        outcome.context = selection.context
        windowLoop: for window in listed {
            guard let match = selection.matches[window.id] else { continue }
            // Serbest hareket izni olan pencereye dokunulmaz (izin geçerliliği
            // taramadan önce ana aktörde denetlenir: `validateFreeMoves`).
            if free.contains(window.id) { continue }
            // Ad hedefi: adın bağlı olduğu masaüstü, nerede olursa (A.3).
            // Ad yerleşmemişse ya da masaüstü bağlı değilse pencere tutulur.
            // Sıralı yerler (K3): listede bağlı ilk yer, yoksa rol sırasıyla
            // yedek (K4); oturum pininin tek yeri var.
            guard let resolved = Self.resolvePlaces(match.rule?.places(mode) ?? [match.destination],
                                                    nameSpaces: nameSpaces,
                                                    holdNames: holdNames, displays: displays,
                                                    screens: screens, heldRoles: heldRoles)
            else {
                outcome.unplaced.insert(window.id)
                continue
            }
            let destination = resolved.destination
            outcome.placeChoices[window.id] = resolved.choice

            // Onay bekleyen rolün ekranına kural uygulanmaz (A3/A4): düzen
            // kullanıcı monitörü seçene dek bekler.
            guard !heldRoles.contains(destination.screen),
                  let screen = screens.first(where: { $0.id == destination.screen })
            else { continue }

            let state = windowState(window)
            guard Self.canRoute(state, spacesReadable: sky.canRead) else {
                // Yalnız listelenir; bir sonraki taramada yeniden bakılır.
                outcome.unknownSpaces += 1
                continue
            }

            outcome.routed += 1
            // Anahtarlar çözülmüş hedefe bağlı, kurala değil (B7).
            let appliedTarget = AppliedTarget(mode: mode, destination: destination)
            let key = "\(window.id)|\(mode.rawValue)|\(destination.hashValue)"

            let moved = destination.layout.isDesktopOnly
                ? Self.desktopOnlyLayout(frame: state.frame, target: screen, screens: screens) : nil
            let layout = moved ?? destination.layout
            let targetFrame = Self.targetFrame(for: layout, on: screen, screens: screens)
            // Red, reddedildiği hedef boyutuna bağlı: ekran alanı değişince
            // (çözünürlük) eski kayıt yeni boyutu engellemesin.
            let refusedKey = "\(window.id)|refused|\(destination.hashValue)|"
                + "\(Int(targetFrame.width))x\(Int(targetFrame.height))"
            var needsLayout = Self.needsLayout(applied: outcome.applied[window.id],
                                               target: appliedTarget) && !state.isMinimized
            // Yalnız masaüstü: hedef ekrandaki pencerenin çerçevesine dokunulmaz.
            if layout.isDesktopOnly, moved == nil { needsLayout = false }

            // Hedef masaüstü ve pencerenin şu anki space durumu.
            var target: SkyLight.Space?
            var onTarget = true
            var isVisible = true
            var desktopLabel = ""
            if sky.canRead,
               let display = displays.first(where: { $0.displayUUID == screen.uuid }),
               !display.desktops.isEmpty {
                let desktops = display.desktops
                let index = Self.desktopIndex(destination.desktop, count: desktops.count)
                let space = desktops[index - 1]
                let current = state.spaces
                // Tam ekran uygulamaya ait pencerelere dokunulmaz.
                if state.isFullscreen { continue }
                target = space
                onTarget = current.contains(space.id)
                isVisible = current.contains(where: visibleSpaces.contains)
                desktopLabel = L("%@ · Desktop %ld",
                                 DisplayRoles.displayName(role: screen.id, name: screen.name), index)
            }

            // 1. Düzen — pencere yalnızca GÖRÜNÜRKEN uygulanır. Görünmeyen
            // bir masaüstündeki pencereye verilen çerçeve uygulama
            // tarafından işlenmez; düzen "beklemede" kalır ve kullanıcı o
            // masaüstüne geçince (activeSpaceDidChange taraması) verilir.
            // Eski "hop" (pencereyi önce görünen masaüstüne uğratma)
            // kaldırıldı: bulunduğun masaüstünde yabancı pencere beliriyor,
            // Dock'tan uygulamaya geçişte macOS yanlış Space'e gidiyordu.
            if !isVisible { needsLayout = false }

            var placed = false
            if needsLayout {
                let area = Self.targetArea(on: screen, screens: screens)
                if let frame = state.frame, Coordinates.close(frame, targetFrame) {
                    placed = true
                } else if let frame = state.frame,
                          let refused = refusedSizes[refusedKey],
                          layout.holdsRefused(frame, refused: refused, in: area) {
                    // Bu hedefin boyutunu daha önce reddetmiş pencere zaten o
                    // boyutla doğru noktada: yeniden uygulamada önce yanlış
                    // yere sıçratılmaz. Yalnız denemeyle görülmüş red sayılır
                    // (büyütülmüş ya da ekranı dolduran pencere küçültülür).
                    // Oranlı düzende köşesi hedefte duran pencere yeniden
                    // denenir (sıçramaz; en küçük boyutu düşmüş olabilir).
                    placed = true
                } else {
                    guard token.isCurrent else { outcome.stale = true; break windowLoop }
                    AX.setFrame(targetFrame, of: window)
                    // Uygulama çerçeveyi kabul etti mi? Bu okuma gerekli.
                    if let after = AX.frame(of: window) {
                        if Coordinates.close(after, targetFrame) {
                            placed = true
                        } else if let tries = outcome.attempts[key], tries >= 1,
                                  layout.refusesSize(after.size, in: area) || tries >= 2 {
                            // Uygulama boyutu ikinci denemede de reddetti (en
                            // küçük boyut vb.; ilk okuma gecikmeli AX olabilir);
                            // gerçek boyutla hizala (sabit boyut aynı noktaya,
                            // oranlı düzen ekranın içine), konum tutunca
                            // yerleşmiş say (boyut için sonsuz deneme olmasın).
                            let anchored = layout.reanchored(
                                actualSize: after.size, in: area)
                            if !Coordinates.close(after, anchored) {
                                AX.setFrame(anchored, of: window)
                            }
                            if let again = AX.frame(of: window),
                               Coordinates.close(again.origin, anchored.origin) {
                                placed = true
                                outcome.refusedSizes[refusedKey] = again.size
                            }
                        }
                    }
                }

                let previousAttempts = outcome.attempts[key] ?? 0
                var done: Set<String> = []
                if Routing.recordLayoutAttempt(
                    key: key, placed: placed,
                    applied: &done, attempts: &outcome.attempts) {
                    outcome.needsFollowUp = true
                }
                if done.contains(key) {
                    outcome.applied[window.id] = AppliedEntry(
                        target: appliedTarget, generation: token.value)
                }
                if !placed, previousAttempts + 1 >= Routing.maxAttempts {
                    Log.routing.notice("""
                        Layout given up: \(window.appName, privacy: .public) [\(window.id)] \
                        '\(window.title, privacy: .private)' did not take layout \
                        \(layout.label, privacy: .public) in \(Routing.maxAttempts) attempts
                        """)
                }
            }

            // 2. Masaüstü — çerçeve verildikten sonra; aynı ekrandaki
            // masaüstüler arası taşıma çerçeveyi korur.
            let moveKey = "\(window.id)|move|\(mode.rawValue)|\(destination.hashValue)"
            if movesAllowed, sky.canMove, let target, !onTarget {
                if let count = Routing.recordMoveAttempt(
                    key: moveKey, now: now,
                    attempts: &outcome.attempts, lastAttempts: &outcome.lastAttempts) {
                    guard token.isCurrent else { outcome.stale = true; break windowLoop }
                    let result = sky.move(window: window.id, to: target.id)
                    outcome.moves.append((window.id, target.id, result))
                    Log.routing.info("""
                        \(window.appName, privacy: .public) [\(window.id)] \
                        '\(window.title, privacy: .private)' → \(desktopLabel, privacy: .public) \
                        (attempt \(count)/\(Routing.maxMoveAttempts))
                        """)
                    if result == .unavailable || result == .noEffect {
                        Log.routing.error("""
                            Desktop move failed (\(String(describing: result), privacy: .public)); \
                            window \(window.id)
                            """)
                    }
                    if count == Routing.maxMoveAttempts {
                        Log.routing.notice("""
                            Last move attempt: \(window.appName, privacy: .public) [\(window.id)]; \
                            if it does not stick, next round in \(Int(Routing.moveRetryInterval)) s
                            """)
                    }
                    if count <= Routing.quickAttempts { outcome.needsFollowUp = true }
                    outcome.lastAction = "\(window.appName) → \(desktopLabel)"
                    if count == 1 {
                        let name = window.title.isEmpty || window.title == window.appName
                            ? window.appName : "\(window.appName) (\(window.title))"
                        outcome.actions.append("\(name) → \(desktopLabel)")
                    }
                }
            } else if onTarget {
                outcome.attempts[moveKey] = nil
                outcome.lastAttempts[moveKey] = nil
            }
        }
        return outcome
    }

    /// Pencere sunucusunda artık olmayan (kapanmış) pencerelerin oturum
    /// pinlerini birkaç tarama sonra düşürür. AX listesinde görünmemek
    /// yeterli değildir: başka masaüstündeki pencere AX'te eksik çıkabilir
    /// ama sunucuda durur; pin de durur. Sunucu hiç pencere döndürmediyse
    /// (geçici hata) hiçbir pin düşürülmez.
    private func expireSessionPins(live: [CGWindowID: pid_t]) {
        guard !sessionPins.isEmpty, !live.isEmpty else { return }
        var expired: [CGWindowID] = []
        for id in sessionPins.keys {
            let alive = live[id] != nil
                && (sessionRecords[id].map { $0.pid == 0 || $0.pid == live[id] } ?? true)
            if alive {
                sessionMisses[id] = nil
            } else {
                let misses = (sessionMisses[id] ?? 0) + 1
                sessionMisses[id] = misses
                if misses >= Self.sessionMissLimit { expired.append(id) }
            }
        }
        for id in expired {
            let record = sessionRecords[id]
            Log.routing.notice("""
                Session pin dropped: \(record?.appName ?? "?", privacy: .public) [\(id)] \
                '\(record?.title ?? "", privacy: .private)' is no longer in the window server
                """)
            sessionPins[id] = nil
            sessionRecords[id] = nil
            sessionMisses[id] = nil
            forgetApplied(for: id)
        }
        if !expired.isEmpty { saveSessionPins() }
    }

    // MARK: - Yardımcılar

    /// Yaşayan pencereler (saf): pencere sunucusu listesi esas alınır;
    /// sunucu listesi AX listesinden önce okunduğu için AX'in gördüğü (yani
    /// yaşayan) ama sunucuda henüz olmayan pencereler eklenir. Sunucu boş
    /// döndürdüyse (geçici hata) sonuç da boş kalır: çağıranlar boş listeyi
    /// "bilgi yok" sayıp budama ve pin düşürmeyi atlar; AX pencereleriyle
    /// doldurulsaydı o koruma boşa çıkardı.
    nonisolated static func liveWindows(
        server: [CGWindowID: pid_t], ax: [(id: CGWindowID, pid: pid_t)]
    ) -> [CGWindowID: pid_t] {
        guard !server.isEmpty else { return [:] }
        var live = server
        for window in ax where live[window.id] == nil { live[window.id] = window.pid }
        return live
    }

    nonisolated static func primaryUUID(_ screens: [ScreenInfo]) -> String? {
        (screens.first { $0.frame.origin == .zero } ?? screens.first)?.uuid
    }

    /// Pencerenin şu an bulunduğu ekran ve masaüstü sırası. Tam ekran
    /// (ya da başka özel) bir space'teyse nil. Saf: taramada bir kez
    /// okunan `WindowState` ile çalışır, IPC yapmaz.
    nonisolated static func placement(
        of state: WindowState, displays: [SkyLight.DisplaySpaces], screens: [ScreenInfo]
    ) -> Placement? {
        let spaces = state.spaces
        if !spaces.isEmpty {
            if state.isFullscreen { return nil }
            for display in displays {
                guard let screen = screens.first(where: { $0.uuid == display.displayUUID })
                else { continue }
                // Birden çok masaüstündeki (ör. "All Desktops") pencere,
                // o ekranda görünen masaüstünde gösterilir; ilk sıradakinde değil.
                let desktops = display.desktops
                let index = desktops.firstIndex { $0.id == display.current && spaces.contains($0.id) }
                    ?? desktops.firstIndex { spaces.contains($0.id) }
                if let index {
                    return Placement(screen: screen.id, desktop: index + 1)
                }
            }
            // Space'ler okundu ama bilinen hiçbir masaüstüne denk gelmiyor:
            // tahmin yok ("Desktop 1"de hayalet göstermektense haritada gösterme).
            return nil
        }
        // Space bilgisi yoksa pencere çerçevesinden ekranı bul.
        if let frame = state.frame {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            for screen in screens {
                let axFrame = Coordinates.axRect(fromCocoa: screen.frame, screens: screens)
                if axFrame.contains(center) {
                    return Placement(screen: screen.id, desktop: 1)
                }
            }
        }
        return screens.first.map { Placement(screen: $0.id, desktop: 1) }
    }

    /// Hedef masaüstünün ekrandaki sırası (saf): ekranda o kadar masaüstü
    /// yoksa son masaüstü (D1.10).
    nonisolated static func desktopIndex(_ desktop: Int, count: Int) -> Int {
        min(max(desktop, 1), count)
    }

    /// Yalnız uçtan uca test (`scripts/hooktest/places.sh`,
    /// `DESKMAP_TEST_NO_DESKTOP_CHANGES=1`): masaüstü planı ve artık
    /// temizliği hiçbir masaüstü açmaz, silmez, pencere taşımaz. Test boş bir
    /// veri klasörüyle çalışır; plansız belge kullanıcının boş masaüstlerini
    /// artık sayıp silebilirdi. Yalnız pin yönlendirmesi çalışır.
    nonisolated static let desktopChangesDisabled =
        ProcessInfo.processInfo.environment["DESKMAP_TEST_NO_DESKTOP_CHANGES"] == "1"

    /// `status.json` için yer durumu (saf).
    nonisolated static func placeStatus(choices: [CGWindowID: Routing.PlaceChoice],
                                        unplaced: Set<CGWindowID>) -> [CGWindowID: String] {
        var result: [CGWindowID: String] = [:]
        for (id, choice) in choices {
            switch choice {
            case .place(let index): result[id] = String(index + 1)
            case .fallback: result[id] = "fallback"
            }
        }
        for id in unplaced where result[id] == nil { result[id] = "untouched" }
        return result
    }

    /// Pinin sıralı yerlerinden bu taramada kullanılanı (saf,
    /// `Routing.resolvePlace`): ad hedefi adın space'inin canlı yeri;
    /// bağlı ekranda yer yoksa rol sırasıyla yedek (K4). nil: pencere
    /// taşınmaz.
    nonisolated static func resolvePlaces(_ places: [Destination], nameSpaces: [String: UInt64],
                                          holdNames: Bool, displays: [SkyLight.DisplaySpaces],
                                          screens: [ScreenInfo],
                                          heldRoles: Set<String> = []) -> Routing.ResolvedPlace? {
        Routing.resolvePlace(places, connected: screens.map(\.id), held: heldRoles,
                             holdNames: holdNames) { nameID in
            guard let space = nameSpaces[nameID],
                  let place = place(of: space, displays: displays, screens: screens) else { return nil }
            return (place.screen, place.desktop)
        }
    }

    /// Bir space'in bağlı ekrandaki yeri (normal masaüstüyse); saf.
    nonisolated static func place(of space: UInt64, displays: [SkyLight.DisplaySpaces],
                                  screens: [ScreenInfo]) -> Placement? {
        for display in displays {
            guard let screen = screens.first(where: { $0.uuid == display.displayUUID }),
                  let index = display.desktops.firstIndex(where: { $0.id == space }) else { continue }
            return Placement(screen: screen.id, desktop: index + 1)
        }
        return nil
    }

    /// Tam ekran space kümesi değiştiyse günlüğe yazar (başlık yok; uygulama
    /// adı, ekran ve haritadaki yer). Haritadaki mor satırların kaynağı.
    private static func logFullscreenChange(from old: [WindowSnapshot], to new: [WindowSnapshot]) {
        func slots(_ windows: [WindowSnapshot]) -> [String] {
            windows.compactMap { window in
                window.fullscreen.map {
                    "\(window.appName)#\(window.id)@\($0.screen)/after\($0.afterDesktop)/space\($0.space)"
                }
            }.sorted()
        }
        let before = slots(old), after = slots(new)
        guard before != after else { return }
        let text = after.isEmpty ? "none" : after.joined(separator: ", ")
        Log.routing.notice("fullscreen spaces: \(text, privacy: .public)")
    }

    /// Tam ekran space'teki pencerenin haritadaki yeri; normal masaüstündeyse
    /// ya da space hiçbir bağlı ekranın listesinde yoksa nil. Saf.
    nonisolated static func fullscreenSlot(
        of state: WindowState, displays: [SkyLight.DisplaySpaces], screens: [ScreenInfo]
    ) -> FullscreenSlot? {
        guard state.isFullscreen else { return nil }
        for display in displays {
            guard let screen = screens.first(where: { $0.uuid == display.displayUUID })
            else { continue }
            var desktopsBefore = 0
            for (order, space) in display.spaces.enumerated() {
                if space.isUserSpace { desktopsBefore += 1; continue }
                if state.spaces.contains(space.id) {
                    return FullscreenSlot(screen: screen.id, space: space.id,
                                          afterDesktop: desktopsBefore, order: order)
                }
            }
        }
        return nil
    }

    /// Bağlı ekranlardaki gerçek masaüstü sayıları.
    nonisolated static func desktopCounts(screens: [ScreenInfo]) -> [String: Int] {
        desktopCounts(displays: SkyLight.shared.displaySpaces(mainUUID: primaryUUID(screens)),
                      screens: screens)
    }

    /// Okunmuş ekran listesinden ekran başına sıralı masaüstü kimlikleri (saf).
    nonisolated static func desktopSpaces(
        displays: [SkyLight.DisplaySpaces], screens: [ScreenInfo]
    ) -> [String: [UInt64]] {
        var result: [String: [UInt64]] = [:]
        for display in displays {
            if let screen = screens.first(where: { $0.uuid == display.displayUUID }) {
                result[screen.id] = display.desktops.map(\.id)
            }
        }
        return result
    }

    /// Okunmuş ekran listesinden masaüstü sayıları (saf).
    nonisolated static func desktopCounts(
        displays: [SkyLight.DisplaySpaces], screens: [ScreenInfo]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for display in displays {
            if let screen = screens.first(where: { $0.uuid == display.displayUUID }) {
                counts[screen.id] = display.desktops.count
            }
        }
        return counts
    }
}
