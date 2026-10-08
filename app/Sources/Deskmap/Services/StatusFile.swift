import Combine
import CoreGraphics
import Foundation

/// Uygulamanın anlık durumunu `status.json`'a yazar (rules.json ile aynı
/// klasör): ekranlar, pencereler, oturum pinleri, profil, kurallar, son hata.
/// `deskmap` komut satırı aracı bunu okur. Değişiklikler 300 ms toplanır;
/// URL komutu `?req=<n>` taşıyorsa komuttan hemen sonra `request: n` ile
/// yazılır, araç komutun işlendiğini buradan anlar.
@MainActor
final class StatusFile {

    struct Snapshot: Codable {
        struct Screen: Codable {
            let id: String
            let name: String
            let builtin: Bool
            let frame: [Double]
            let visible: [Double]
            let desktops: Int?
            /// Mod başına planlanan masaüstü sayısı (docked / undocked).
            let planned: [String: Int]
        }
        struct Window: Codable {
            let id: CGWindowID
            let app: String
            let bundleID: String
            let title: String
            let screen: String?
            let desktop: Int?
            let frame: [Double]?
            let minimized: Bool
            let fullscreen: Bool
            let pinned: Pin?
        }
        struct Pin: Codable {
            let screen: String
            let desktop: Int
        }
        let pid: Int32
        let updated: Date
        let request: String?
        let enabled: Bool
        let mode: String
        let profile: String?
        let profiles: [String]
        let lastError: String?
        let primaryHeight: Double?
        let screens: [Screen]
        let windows: [Window]
        let rules: [Rule]
        /// Masaüstü adları: ekran → masaüstü numarası → ad (bağlı olmayan
        /// ekranlarınki de).
        let desktopNames: [String: [String: String]]
        /// Mission Control'de silinmiş, pinleri saklanan masaüstüleri.
        let deletedDesktops: [GhostDesktop]
    }

    private let url: URL
    private let store: Store
    private let router: Router
    private let screens: ScreenService
    private var cancellables = Set<AnyCancellable>()

    init(url: URL, store: Store, router: Router, screens: ScreenService) {
        self.url = url
        self.store = store
        self.router = router
        self.screens = screens
        let changes: [AnyPublisher<Void, Never>] = [
            router.$windows.map { _ in () }.eraseToAnyPublisher(),
            router.$sessionPins.map { _ in () }.eraseToAnyPublisher(),
            store.$document.map { _ in () }.eraseToAnyPublisher(),
            store.$lastError.map { _ in () }.eraseToAnyPublisher(),
            screens.$screens.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.write(request: nil) }
            .store(in: &cancellables)
    }

    private func screenEntry(_ screen: ScreenInfo) -> Snapshot.Screen {
        let frame: [Double] = [screen.frame.minX, screen.frame.minY,
                               screen.frame.width, screen.frame.height]
        let visible: [Double] = [screen.visibleFrame.minX, screen.visibleFrame.minY,
                                 screen.visibleFrame.width, screen.visibleFrame.height]
        var planned: [String: Int] = [:]
        for mode in Mode.allCases {
            planned[mode.rawValue] = store.document.plannedDesktops(mode: mode, screen: screen.id)
        }
        return Snapshot.Screen(id: screen.id, name: screen.name, builtin: screen.isBuiltin,
                               frame: frame, visible: visible,
                               desktops: router.desktopCounts[screen.id], planned: planned)
    }

    func write(request: String?) {
        let pins = router.sessionPins
        let primary: ScreenInfo? = screens.screens.first { $0.frame.origin == CGPoint.zero }
        let primaryHeight: Double? = primary.map { Double($0.frame.height) }
        let snapshot = Snapshot(
            pid: ProcessInfo.processInfo.processIdentifier,
            updated: Date(),
            request: request,
            enabled: store.document.enabled,
            mode: screens.mode.rawValue,
            profile: store.document.activeProfile?.name,
            profiles: store.profiles.map(\.name),
            lastError: store.lastError,
            primaryHeight: primaryHeight,
            screens: screens.screens.map(screenEntry),
            windows: router.windows.map { window in
                .init(id: window.id, app: window.appName, bundleID: window.bundleID,
                      title: window.title,
                      screen: window.placement?.screen ?? window.fullscreen?.screen,
                      desktop: window.placement?.desktop,
                      frame: window.frame.map { [$0.minX, $0.minY, $0.width, $0.height] },
                      minimized: window.isMinimized, fullscreen: window.fullscreen != nil,
                      pinned: pins[window.id].map { .init(screen: $0.screen, desktop: $0.desktop) })
            },
            rules: store.document.rules,
            desktopNames: store.document.desktopNames,
            deletedDesktops: store.document.ghostDesktops)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch {
            Log.app.error("status.json not written: \(error.localizedDescription, privacy: .public)")
        }
    }
}
