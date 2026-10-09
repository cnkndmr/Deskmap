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
            forKey: Router.volatileDocumentAppsKey) ?? []))
    nonisolated static let volatileDocumentAppsKey = "volatileDocumentApps"

    private func observeIdentity(_ snapshots: [WindowSnapshot]) {
        var next = identity
        next.observe(snapshots)
        guard next != identity else { return }
        if next.volatileDocumentApps != identity.volatileDocumentApps {
            UserDefaults.standard.set(next.volatileDocumentApps.sorted(),
                                      forKey: Self.volatileDocumentAppsKey)
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
    @Published private(set) var moveHealth = MoveHealth()
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

    /// Pencere başına düzenin en son uygulandığı çözülmüş hedef ve nesil.
    /// Düzen hedef başına bir kez verilir; kullanıcı pencereyi sonradan elle
    /// taşırsa, başka bir kural aynı hedefe çıksa da yerinden oynatılmaz.
    /// Hedef değişip geri dönerse (A→B→A) yeniden verilir (B7).
    private var applied: [CGWindowID: AppliedEntry] = [:]
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
            desktop move path: \(sky.movePath, privacy: .public)
            """)
        loadSessionPins()
        loadDesktopBaseline()
        loadReopenTargets()

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

        screens.settled
            .sink { [weak self] in
                // Önce yeni kurulumun adları taze okumayla yerleşir (sahiplenme),
                // sonra adlı masaüstündeki pencereler adı izler.
                self?.followDesktopNames()
                self?.followNamedDesktops()
                self?.reapplyAll()
            }
            .store(in: &cancellables)

        // Ekran değişimi yatışmadan da süren taramanın yan etkileri durmalı.
        screens.$screens
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.generation.advance() }
            .store(in: &cancellables)

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

    deinit {
        timer?.invalidate()
        followUp?.cancel()
        for token in sleepTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    private func setPaused(_ paused: Bool, reason: String) {
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
        moveHealth.reset()
        pendingMoves = [:]
        Log.skylight.notice("Desktop moves re-enabled by user")
        reapplyAll()
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
        case .unknown:
            break
        }
    }

    // MARK: - Oturum pinleri

    /// Bu pencereyi (kimliğiyle) pencere kapanana kadar hedefte tutar.
    /// Kayıt diske yazılır; Space Router yeniden başlarsa pencere hâlâ
    /// açıksa pin geri gelir.
    func pinSession(_ windowID: CGWindowID, destination: Destination) {
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
        sessionRecords[windowID] = nil
        sessionMisses[windowID] = nil
        forgetApplied(for: windowID)
        dropFreeMoves([windowID], reason: "unpinned")
        saveSessionPins()
    }

    // MARK: - Serbest hareket

    /// Panelde sunulan süreler (sn).
    nonisolated static let freeMoveDurations: [TimeInterval] = [60, 5 * 60, 15 * 60, 30 * 60, 60 * 60]

    /// Bu pencereler `duration` boyunca serbest: motor onları yerine
    /// döndürmez. Süren bir izin yeniden verilirse süre baştan başlar.
    /// Yalnız pinli (şu an bir hedefi olan) pencerelere verilir; hedef
    /// izinle birlikte saklanır.
    func allowFreeMove(_ windowIDs: [CGWindowID], for duration: TimeInterval) {
        guard duration > 0 else { return }
        let end = Date().addingTimeInterval(duration)
        var granted = 0
        for id in windowIDs {
            guard let window = windows.first(where: { $0.id == id }),
                  let match = Routing.select(
                    rules: store.document.rules, sessionPins: sessionPins, mode: screens.mode,
                    windowID: id, bundleID: window.bundleID, appName: window.appName,
                    title: window.title, document: window.document)
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
        Log.routing.notice("Free move: \(granted) window(s) for \(Int(duration)) s")
        sweep()
    }

    /// Süren izni `duration` kadar uzatır; izni olmayan ya da süresi
    /// dolmuş pencereye yeni izin vermez.
    func extendFreeMove(_ windowIDs: [CGWindowID], by duration: TimeInterval) {
        let now = Date()
        for id in windowIDs {
            guard let until = freeMoves[id], until > now else { continue }
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

    /// Süresi dolan izinleri düşürür (zamanlayıcı turu).
    private func expireFreeMoves(now: Date) {
        let expired = freeMoves.filter { $0.value <= now }.map(\.key)
        guard !expired.isEmpty else { return }
        Log.routing.notice("Free move ended: \(expired.count) window(s)")
        endFreeMove(expired)
    }

    /// Şu an serbest olan pencereler (saf).
    nonisolated static func activeFreeMoves(_ until: [CGWindowID: Date], now: Date) -> Set<CGWindowID> {
        Set(until.filter { $0.value > now }.keys)
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
        queue.async {
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
            Task { @MainActor [weak self] in
                for (window, placement) in handOff { self?.moveWindow(window, to: placement) }
            }
            Log.routing.notice("Desktop move \(fromScreen, privacy: .public) → \(toScreen, privacy: .public): moved \(moved) window(s), \(handOff.count) to the other display")
            Task { @MainActor [weak self] in self?.scheduleFollowUp(after: 300) }
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
        queue.async {
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
        guard let display = displayInfo(screenID) else { return false }
        let added = await MissionControl.addDesktop(
            displayID: display.id, displayUUID: display.uuid,
            mainUUID: Self.primaryUUID(screens.screens))
        scheduleFollowUp(after: 300)
        return added
    }

    /// Masaüstünü pinlere dokunmadan siler.
    private func removeDesktopNow(on screenID: String, desktop: Int) async -> Bool {
        guard let display = displayInfo(screenID) else { return false }
        return await MissionControl.removeDesktop(
            displayID: display.id, displayUUID: display.uuid,
            mainUUID: Self.primaryUUID(screens.screens), desktop: desktop)
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
            // Mission Control'de silmeyle aynı: pinleri ve adı hayalete
            // geçer (satırdan geri getirilebilir), sonrakiler bir yukarı kayar.
            Log.app.notice("Desktop \(desktop) on \(screenID, privacy: .public) removed in Deskmap; pins kept on a deleted-desktop row")
            store.ghostDesktop(on: screenID, desktop: desktop, modes: Mode.allCases)
            shiftSessionPins(screen: screenID, removed: desktop)
            updateBaseline(removed: space.map { [$0] } ?? [])
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

    /// Bu oturumda görülmüş masaüstü kimlikleri: adı bağlı kimlik burada
    /// olup artık yoksa masaüstü silinmiştir (bkz. `reconcileDesktopNames`).
    private var seenDesktopSpaces: Set<UInt64> = []
    /// Son okunan ekran → sıralı masaüstü kimlikleri; bir sonraki okumada
    /// kaybolan kimlik Deskmap dışında (Mission Control) silinmiş demektir.
    /// Deskmap'in kendi ekleme/silmelerinden sonra tazelenir.
    private var knownDesktopSpaces: [String: [UInt64]] = [:]

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
        reopenQueue.async { [weak self] in
            var found: [String: URL] = [:]
            for job in jobs {
                guard let element = AX.element(pid: job.pid, windowID: job.window),
                      let url = Reopen.capture(element, bundleID: job.bundleID, title: job.title)
                else { continue }
                found[job.rule] = url
            }
            DispatchQueue.main.async {
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

    // MARK: - Kurulum değişiminde adlı masaüstleri

    /// Son kararlı taramanın kurulumu ve pencereleri.
    private var lastStableWindows: (mode: Mode, windows: [WindowSnapshot])?

    /// Ekran kilitli mi: kilitliyken macOS erişilebilirlikten pencere
    /// vermez (liste boş gelir); kilitlenmeden önceki liste korunmalı, yoksa
    /// kilitliyken çıkarılan monitörde taşınacak pencere kalmaz (08.10).
    nonisolated static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    /// Kurulum değişti (monitör takıldı/çıktı): eski kurulumda adlı bir
    /// masaüstünde duran pencereler, yeni kurulumda aynı adlı masaüstüne
    /// taşınır. "Nova" monitörlü kurulumda Dell'deyse monitör çıkınca
    /// laptop'taki Nova'ya döner (macOS Dell masaüstülerini laptop'un sonuna
    /// ekler); monitör takılınca tersine. Yeni kurulumda pini olan pencere
    /// pinine gider, dokunulmaz.
    private func followNamedDesktops() {
        guard let previous = lastStableWindows, previous.mode != screens.mode else { return }
        lastStableWindows = nil
        let mode = screens.mode
        let rules = store.document.rules, sessions = sessionPins
        let moves = Self.namedDesktopMoves(
            windows: previous.windows,
            from: store.document.desktopNames(for: previous.mode),
            to: store.document.desktopNames(for: mode),
            desktopCounts: Self.desktopCounts(screens: screens.screens)
        ) { window in
            Routing.select(rules: rules, sessionPins: sessions, mode: mode, windowID: window.id,
                           bundleID: window.bundleID, appName: window.appName,
                           title: window.title, document: window.document) != nil
        }
        for move in moves {
            Log.routing.notice("Setup changed: window \(move.window) follows its named desktop to \(move.placement.screen, privacy: .public)/\(move.placement.desktop)")
            moveWindow(move.window, to: move.placement)
        }
    }

    /// Kurulum değişiminde taşınacak pencereler (saf). Eski kurulumda adlı
    /// masaüstündeki her pencere, yeni kurulumda o adı taşıyan (tek)
    /// masaüstüne; yeri aynıysa, yeni masaüstü yoksa ya da pini varsa atlanır.
    nonisolated static func namedDesktopMoves(
        windows: [WindowSnapshot], from old: [String: [String: String]],
        to new: [String: [String: String]], desktopCounts: [String: Int],
        pinned: (WindowSnapshot) -> Bool
    ) -> [(window: CGWindowID, placement: Placement)] {
        var targets: [String: Placement] = [:]
        var duplicate = Set<String>()
        for (screen, list) in new {
            for (slot, name) in list {
                guard let desktop = Int(slot) else { continue }
                let key = name.lowercased()
                if targets[key] != nil { duplicate.insert(key) }
                targets[key] = Placement(screen: screen, desktop: desktop)
            }
        }
        var moves: [(window: CGWindowID, placement: Placement)] = []
        for window in windows {
            guard let placement = window.placement, window.fullscreen == nil,
                  let name = old[placement.screen]?[String(placement.desktop)]?.lowercased(),
                  !duplicate.contains(name), let target = targets[name], target != placement,
                  target.desktop <= (desktopCounts[target.screen] ?? 0),
                  !pinned(window) else { continue }
            moves.append((window.id, target))
        }
        return moves.sorted { $0.window < $1.window }
    }

    /// Deskmap kendi masaüstü işlemini bitirdi: yalnız kendi sildiği kimlikler
    /// tabandan düşer; `addingNewIds` ise tabanda olmayan canlı kimlikler
    /// (kendi eklediği masaüstü) sırasıyla eklenir. Arada Mission Control'de
    /// başkasının sildiği masaüstü tabanda kalır, sonraki taramada görülür.
    func updateBaseline(removed: Set<UInt64> = [], addingNewIds: Bool = false) {
        let live = addingNewIds ? Self.desktopSpaces(
            displays: SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(screens.screens)),
            screens: screens.screens) : [:]
        setDesktopBaseline(Self.updatedBaseline(known: knownDesktopSpaces, removed: removed, live: live))
    }

    /// Yeni taban (saf): `removed` düşer; `live`'daki tabanda olmayan kimlikler
    /// canlı sıralarına yakın yere eklenir. Başka kimliklere dokunulmaz.
    nonisolated static func updatedBaseline(
        known: [String: [UInt64]], removed: Set<UInt64>, live: [String: [UInt64]]
    ) -> [String: [UInt64]] {
        var next = known.mapValues { $0.filter { !removed.contains($0) } }
        let have = Set(next.values.joined())
        for (screen, list) in live {
            var merged = next[screen] ?? []
            for (index, id) in list.enumerated() where !have.contains(id) {
                merged.insert(id, at: min(index, merged.count))
            }
            next[screen] = merged
        }
        return next
    }

    /// Karşılaştırma tabanını değiştirir; değiştiyse diske yazar (Deskmap
    /// yeniden açılınca aradaki silmeler yakalansın).
    private func setDesktopBaseline(_ spaces: [String: [UInt64]]) {
        guard spaces != knownDesktopSpaces else { return }
        knownDesktopSpaces = spaces
        guard !isDemo else { return }
        do {
            try FileManager.default.createDirectory(
                at: Store.directoryURL, withIntermediateDirectories: true)
            try JSONEncoder().encode(spaces).write(to: Self.desktopSpacesFileURL, options: .atomic)
        } catch {
            Log.app.error("desktop-spaces.json not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Açılışta son kaydedilen masaüstü listesi okunur; ilk taramada
    /// şimdiki listeyle karşılaştırılır. Yeniden başlatmada kimlikler
    /// tamamen yenilenirse ekranın bütün eski kimlikleri kaybolur ve bu
    /// silme sayılmaz (`externallyRemovedDesktops`).
    private func loadDesktopBaseline() {
        guard let data = try? Data(contentsOf: Self.desktopSpacesFileURL),
              let saved = try? JSONDecoder().decode([String: [UInt64]].self, from: data)
        else { return }
        // `seenDesktopSpaces` buradan beslenmez: "görüldü" = bu süreçte canlı
        // okundu. Kapalıyken silinen masaüstü taban farkıyla yakalanır; kimlikler
        // yenilenmişse adlar silinmiş sayılmaz.
        knownDesktopSpaces = saved
    }

    /// Önceki ve şimdiki listeye göre Deskmap dışında silinen masaüstüleri
    /// (eski sıra numaraları, büyükten küçüğe). Saf. Ekran iki listede de
    /// olmalı; ekranın bütün eski kimlikleri kaybolduysa (yeniden bağlanma,
    /// kimlikler yenilendi) silme sayılmaz. Başka ekrana taşınan kimlik
    /// silinmiş değildir.
    nonisolated static func externallyRemovedDesktops(
        before: [String: [UInt64]], after: [String: [UInt64]]
    ) -> [String: [Int]] {
        let alive = Set(after.values.joined())
        var result: [String: [Int]] = [:]
        for (screen, old) in before {
            guard after[screen] != nil, !old.isEmpty else { continue }
            let gone = old.enumerated().filter { !alive.contains($0.element) }.map { $0.offset + 1 }
            guard !gone.isEmpty, gone.count < old.count else { continue }
            result[screen] = gone.sorted(by: >)
        }
        return result
    }

    /// `externallyRemovedDesktops`, ama Deskmap'in sıraya aldığı silmelerin
    /// (kuyruktaki, pinleri zaten kaymış) kimlikleri iki listeden de çıkarılır:
    /// dönen numaralar kaymış pin numaralarıyla uyuşur.
    nonisolated static func removedOutsideDeskmap(
        before: [String: [UInt64]], after: [String: [UInt64]], pending: Set<UInt64>
    ) -> [String: [Int]] {
        externallyRemovedDesktops(before: before.mapValues { $0.filter { !pending.contains($0) } },
                                  after: after.mapValues { $0.filter { !pending.contains($0) } })
    }

    /// Masaüstü adlarını gerçek masaüstülerine göre yerleştirir: macOS'ta
    /// (Mission Control) sıra/ekran değişse ya da masaüstü silinse de ad
    /// doğru masaüstünü izler. Liste okunamadıysa (boş) dokunulmaz.
    /// Liste taramanın sonucundan değil, o an tazeden okunur: tarama
    /// sürerken Deskmap masaüstü silip adları kaydırdıysa eski liste adı
    /// yanlış masaüstüne bağlar, sonraki taramada da silinmiş sayıp düşürürdü.
    private func followDesktopNames() {
        // Ad olmasa da kimlikler biriktirilir: sonradan verilen adın
        // masaüstü silinince "görülmüş" sayılsın.
        guard !screens.isSettling, !desktopOpInFlight, SkyLight.shared.canRead else { return }
        let spaces = Self.desktopSpaces(
            displays: SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(screens.screens)),
            screens: screens.screens)
        guard !spaces.isEmpty else { return }
        // Kuyruktaki silmeler: kimliği bilinenler iki listeden çıkarılarak
        // (pinler zaten kaydı) ekran yine karşılaştırılır; kimliği bilinmeyen
        // silmesi olan ekranda numaralar gerçek masaüstülerinden önce
        // kaymıştır, o ekran silme bitene dek karşılaştırılmaz.
        var pendingSpaces = Set<UInt64>()
        var unresolved = Set<String>()
        for (key, list) in store.document.pendingRemovals where !list.isEmpty {
            let screen = key.split(separator: "|").last.map(String.init) ?? key
            for removal in list {
                if let space = removal.space { pendingSpaces.insert(space) } else { unresolved.insert(screen) }
            }
        }
        let comparable = spaces.filter { !unresolved.contains($0.key) }
        let previous = knownDesktopSpaces.filter { !unresolved.contains($0.key) }
        // Mission Control'de silinen masaüstü: pinleri ve adı hayalete
        // geçer, sonrakilerin pinleri bir yukarı kayar (yoksa hepsi bir
        // sonraki masaüstüne giderdi).
        for (screen, desktops) in Self.removedOutsideDeskmap(
            before: previous, after: comparable, pending: pendingSpaces) {
            for desktop in desktops {
                Log.app.notice("Desktop \(desktop) on \(screen, privacy: .public) was removed outside Deskmap; pins kept on a deleted-desktop row")
                store.ghostDesktop(on: screen, desktop: desktop, modes: Mode.allCases)
                shiftSessionPins(screen: screen, removed: desktop)
            }
        }
        // Taban: kuyruğu çözülemeyen ekran eski girdisinde kalır.
        var baseline = spaces
        for screen in unresolved { baseline[screen] = knownDesktopSpaces[screen] }
        let before = knownDesktopSpaces
        setDesktopBaseline(baseline)
        // Adlar mantıksal numaralara göre: kuyruktaki silmeler düşülür.
        let logical = comparable.mapValues { $0.filter { !pendingSpaces.contains($0) } }
        if !store.document.desktopNames.isEmpty, !logical.isEmpty {
            let result = store.reconcileDesktopNames(
                spaces: logical, seen: seenDesktopSpaces, mode: screens.mode,
                previous: before.mapValues { $0.filter { !pendingSpaces.contains($0) } })
            applySessionMoves(result.moves)
            for drop in result.dropped.sorted(by: { $0.place.desktop > $1.place.desktop }) {
                Log.app.notice("Named desktop \(drop.name, privacy: .private) lost its desktop; kept on a deleted-desktop row")
                store.ghostDesktop(on: drop.place.screen, desktop: drop.place.desktop,
                                   modes: Mode.allCases, name: drop.name, space: drop.place.space,
                                   droppedMode: drop.place.mode)
                shiftSessionPins(screen: drop.place.screen, removed: drop.place.desktop)
            }
        }
        seenDesktopSpaces.formUnion(spaces.values.joined())
    }

    /// Mission Control'de yer değiştiren adlı masaüstlerinin oturum pinleri
    /// de gider (eş zamanlı eşleme).
    private func applySessionMoves(_ moves: [NameMove]) {
        var table: [Slot: Slot] = [:]
        for move in moves where move.mode == screens.mode && move.from != move.to {
            table[move.from] = move.to
        }
        guard !table.isEmpty else { return }
        var changed = false
        for (id, record) in sessionRecords {
            guard let to = table[Slot(screen: record.destination.screen,
                                      desktop: record.destination.desktop)] else { continue }
            var next = record
            next.destination.screen = to.screen
            next.destination.desktop = to.desktop
            sessionRecords[id] = next
            sessionPins[id] = next.destination
            forgetApplied(for: id)
            changed = true
        }
        if changed { saveSessionPins() }
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

    /// Etkin olmayan modda silinecek masaüstünün şu an bilinen space
    /// kimliği: ekran bağlıysa, o ekranın masaüstüleri arasından önceki
    /// bekleyen silmeler çıkarıldıktan sonra `desktop`. sıradaki. Saf olmayan
    /// tek parça SkyLight okuması.
    func spaceForPendingRemoval(on screenID: String, desktop: Int, mode: Mode) -> UInt64? {
        guard let info = screens.screens.first(where: { $0.id == screenID }),
              let display = SkyLight.shared.displaySpaces(mainUUID: Self.primaryUUID(screens.screens))
                .first(where: { $0.displayUUID == info.uuid })
        else { return nil }
        let gone = Set(store.document.pendingRemovals(mode: mode, screen: screenID).compactMap(\.space))
        let remaining = display.desktops.map(\.id).filter { !gone.contains($0) }
        return desktop >= 1 && desktop <= remaining.count ? remaining[desktop - 1] : nil
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

    /// Etkin moddaki bekleyen silmeleri yapar, sonra planlanmış
    /// masaüstülerinden eksik olanları yaratır (etkin olmayan modda
    /// eklenenler). Silme: başarılı ya da artık olmayan girdi kuyruktan
    /// düşer, öbür modların pinleri ve oturum pinleri o an kayar; başarısız
    /// girdi ve sonrakiler kuyrukta kalır, kullanıcıya bildirilir, bu
    /// oturumda aynı kuyruk bir kez denenir (sonraki açılışta yeniden).
    /// Biten ya da ekran değişimiyle yarıda kesilen deneme hedefi bırakır:
    /// aynı mod|ekran|sayı sonradan yeniden planlanabilir.
    /// Plan: karşılanınca silinir (kalıcı alt sınır değil; sonradan
    /// silinen masaüstü yeniden yaratılmaz).
    private func createPlannedDesktops() {
        guard !desktopOpInFlight, !screens.isSettling, !desktopCounts.isEmpty else { return }
        let mode = screens.mode
        for screen in screens.screens {
            let removals = store.document.pendingRemovals(mode: mode, screen: screen.id)
            guard !removals.isEmpty else { continue }
            let key = "remove|\(mode.rawValue)|\(screen.id)|\(removals.count)"
            guard plannedAttempts.begin(key) else { continue }
            desktopOpInFlight = true
            let uuid = screen.uuid, screenID = screen.id
            Log.app.notice("Removing \(removals.count) desktop(s) planned for \(screenID, privacy: .public)")
            Task { [weak self] in
                guard let self else { return }
                var outcome = PlannedAttempts.Outcome.done
                defer {
                    self.plannedAttempts.finish(key, outcome)
                    self.desktopOpInFlight = false
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
                        Log.app.notice("Planned removal skipped on \(screenID, privacy: .public): desktop not found")
                        self.store.dropFirstPendingRemoval(mode: mode, screen: screenID)
                        continue
                    }
                    let removedSpace = desktops[index - 1]
                    guard await self.removeDesktopNow(on: screenID, desktop: index) else {
                        // İşlem sürerken ekran değiştiyse başarısızlık gerçek
                        // değil: bildirilmez, hedef bırakılır.
                        guard self.screens.mode == mode, !self.screens.isSettling else {
                            outcome = .interrupted
                            return
                        }
                        self.store.report(L("Could not remove desktop %ld on %@", index, screenID))
                        outcome = .failed
                        return
                    }
                    self.store.dropFirstPendingRemoval(mode: mode, screen: screenID)
                    // Bu modun pinleri silme sıraya girerken kaydı; öbürleri şimdi.
                    self.store.removeDesktop(on: screenID, desktop: index,
                                             modes: Mode.allCases.filter { $0 != mode },
                                             shiftNames: false)
                    self.shiftSessionPins(screen: screenID, removed: index)
                    self.updateBaseline(removed: [removedSpace])
                }
            }
            return
        }
        for screen in screens.screens {
            let want = store.document.plannedDesktops(mode: mode, screen: screen.id)
            guard want > 0, let have = desktopCounts[screen.id] else { continue }
            let key = "add|\(mode.rawValue)|\(screen.id)|\(want)"
            guard want > have else {
                // Plan başka yoldan karşılandı (elle eklenen masaüstü):
                // önceki başarısız denemenin hedefi de bırakılır, aynı sayı
                // sonradan yeniden planlanabilsin.
                store.clearPlannedDesktops(mode: mode, screen: screen.id)
                plannedAttempts.finish(key, .done)
                continue
            }
            guard plannedAttempts.begin(key) else { continue }
            desktopOpInFlight = true
            let uuid = screen.uuid, screenID = screen.id
            Log.app.notice("Creating planned desktops on \(screenID, privacy: .public): \(have) → \(want)")
            Task { [weak self] in
                guard let self else { return }
                var outcome = PlannedAttempts.Outcome.failed
                defer {
                    self.plannedAttempts.finish(key, outcome)
                    self.desktopOpInFlight = false
                }
                var interrupted = false
                for _ in 0..<Self.maxPlannedCreations {
                    guard self.screens.mode == mode, !self.screens.isSettling else {
                        interrupted = true
                        break
                    }
                    // Tarama anlık görüntüsü değil, o anki sayı (ekranlar yeni yatışmış olabilir).
                    guard let now = self.liveDesktopCount(uuid: uuid), now < want else { break }
                    guard await self.addDesktopNow(on: screenID) else {
                        // İşlem sürerken ekran değiştiyse kesilme sayılır.
                        guard self.screens.mode == mode, !self.screens.isSettling else {
                            interrupted = true
                            break
                        }
                        self.store.report(L("Could not add a desktop to %@", screenID))
                        return
                    }
                }
                let now = self.liveDesktopCount(uuid: uuid)
                outcome = PlannedAttempts.addOutcome(live: now, want: want, interrupted: interrupted)
                if let now, now >= want {
                    self.store.clearPlannedDesktops(mode: mode, screen: screenID)
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

    func sweep() {
        guard !isDemo, AXIsProcessTrusted(), !isPaused else { return }
        if isSweeping {
            // Tarama sürerken gelen olay kaybolmasın; bitince bir tur daha.
            sweepRequested = true
            return
        }

        // Duraklatılmışken kural uygulanmaz ama pencereler yine listelenir.
        // Ekran değişimi yatışırken de öyle: yarım düzenlenmiş ekranlara
        // göre taşıma yapılmaz; yatışınca `settled` → `reapplyAll`.
        // Özgüllük sıralamasını `Routing.select` yapar.
        let routing = store.document.enabled && !screens.isSettling
        let rules = routing ? store.document.rules : []
        let sessionPins = routing ? self.sessionPins : [:]
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
        let token = generation.token()
        isSweeping = true
        sweepRequested = false
        lastSweepAt = Date()

        queue.async { [weak self] in
            let outcome = Self.route(rules: rules, sessionPins: sessionPins,
                                     sessionIDs: sessionIDs, free: free,
                                     mode: mode, screens: connected,
                                     applied: applied, attempts: attempts,
                                     refusedSizes: refusedSizes,
                                     lastAttempts: lastAttempts, movesAllowed: movesAllowed,
                                     token: token)
            Task { @MainActor in
                guard let self else { return }
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
                    let freeMoves = self.freeMoves.filter { live[$0.key] != nil }
                    if freeMoves != self.freeMoves { self.freeMoves = freeMoves }
                    self.freeTargets = self.freeTargets.filter { live[$0.key] != nil }
                    self.appliedFloor = self.appliedFloor.filter { live[$0.key] != nil }
                    attempts = attempts.filter { isLive($0.key) }
                    lastAttempts = lastAttempts.filter { isLive($0.key) }
                    self.refusedSizes = self.refusedSizes.filter { isLive($0.key) }
                }
                self.refusedSizes.merge(outcome.refusedSizes) { $1 }
                self.applied = applied
                self.attempts = attempts
                self.lastAttempts = lastAttempts
                self.screenHooks.fire(self.screenMemory.update(
                    windows: outcome.snapshots, screens: connected,
                    settling: self.screens.isSettling))
                self.captureReopenTargets(outcome.snapshots)
                // Kurulum değişiminde adlı masaüstüyle taşınacak pencereler
                // için son kararlı liste (ekranlar yatışmışken, aynı kurulumda).
                if !self.screens.isSettling, mode == self.screens.mode,
                   connected == self.screens.screens, !Self.screenIsLocked() {
                    self.lastStableWindows = (mode, outcome.snapshots)
                }
                if outcome.snapshots != self.windows {
                    Self.logFullscreenChange(from: self.windows, to: outcome.snapshots)
                    self.windows = outcome.snapshots
                }
                self.observeIdentity(outcome.snapshots)
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
                self.followDesktopNames()
                self.createPlannedDesktops()
                self.sweepDeadline = Self.nextSweepDeadline(
                    now: Date(), pendingSessionMisses: !self.sessionMisses.isEmpty,
                    attempts: self.attempts, lastAttempts: self.lastAttempts,
                    backoffEnd: AX.nextBackoffEnd())
                if outcome.stale {
                    Log.routing.info("Sweep cut short: routing changed while it ran")
                }
                if outcome.needsFollowUp || outcome.stale || self.sweepRequested {
                    self.scheduleFollowUp(after: outcome.needsFollowUp ? 200 : 20)
                }
                var status = self.status
                status.routedWindows = outcome.routed
                status.unresponsive = outcome.unresponsive
                if let action = outcome.lastAction {
                    status.lastAction = action
                    status.lastActionAt = Date()
                }
                if status != self.status { self.status = status }
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
        /// Bu taramada yapılan masaüstü taşımaları ve sonuçları.
        var moves: [(window: CGWindowID, space: UInt64, result: SkyLight.MoveResult)] = []
        var routed = 0
        var lastAction: String?
        /// Bir pencere taşındı ya da düzeni henüz oturmadı; kısa süre sonra
        /// yeniden dene.
        var needsFollowUp = false
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
        lastAttempts: [String: Date], movesAllowed: Bool, token: RoutingGeneration.Token
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
        let server = AX.windowServerList()
        let windows = AX.allWindows(alwaysInclude: sessionIDs, server: server)
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
        windowLoop: for window in listed {
            // Arayüzle aynı seçim: oturum pini, yoksa bu modda hedefi olan
            // en özgül eşleşen kural.
            guard let match = Routing.select(
                rules: rules, sessionPins: sessionPins, mode: mode, windowID: window.id,
                bundleID: window.bundleID, appName: window.appName, title: window.title,
                document: documents[window.id])
            else { continue }
            // Serbest hareket izni olan pencereye dokunulmaz (izin geçerliliği
            // taramadan önce ana aktörde denetlenir: `validateFreeMoves`).
            if free.contains(window.id) { continue }
            let destination = match.destination

            guard let screen = screens.first(where: { $0.id == destination.screen })
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
                let index = min(destination.desktop, desktops.count)
                let space = desktops[index - 1]
                let current = state.spaces
                // Tam ekran uygulamaya ait pencerelere dokunulmaz.
                if state.isFullscreen { continue }
                target = space
                onTarget = current.contains(space.id)
                isVisible = current.contains(where: visibleSpaces.contains)
                desktopLabel = L("%@ · Desktop %ld", screen.name, index)
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
