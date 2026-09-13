import AppKit
import Combine

/// Bağlı bir ekranın anlık görüntüsü.
struct ScreenInfo: Identifiable, Equatable, Hashable {
    /// Rol kimliği: builtin, external, external-2 ...
    let id: String
    let uuid: String
    let name: String
    let isBuiltin: Bool
    /// Cocoa koordinatları (sol alt köşe tabanlı).
    let frame: CGRect
    let visibleFrame: CGRect

    var known: KnownScreen {
        KnownScreen(id: id, name: name,
                    aspect: frame.height > 0 ? frame.width / frame.height : 1.6)
    }

    static func uuid(of screen: NSScreen?) -> String? {
        guard let screen,
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(
                CGDirectDisplayID(number.uint32Value))?.takeRetainedValue()
        else { return nil }
        return normalize(CFUUIDCreateString(nil, cfUUID) as String)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func normalize(_ uuid: String) -> String {
        uuid.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}

/// Bağlı ekranları ve dock durumunu izler.
@MainActor
final class ScreenService: ObservableObject {

    @Published private(set) var screens: [ScreenInfo] = []
    /// Ekran değişiminden yatışmaya kadar true. Bu sürede macOS ekranları
    /// yeniden düzenler; Router listelemeyi sürdürür ama hiçbir pencereyi
    /// taşımaz (yarım düzenlenmiş ekrana göre yanlış yere yerleşmesin).
    @Published private(set) var isSettling = false

    /// Ekran değişimi yatıştıktan sonra tetiklenir.
    let settled = PassthroughSubject<Void, Never>()

    // nonisolated(unsafe): yalnızca init'te (ana aktör) atanır, deinit'te
    // kaldırılır; gözlemci belirteci Sendable olmadığı için deinit erişimi
    // başka türlü sıkı eşzamanlılık uyarısı verir.
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private var settleTask: Task<Void, Never>?
    /// Süren yatışma bölümünün ilk ekran değişimi (üst sınır için).
    private var settleEpisodeStart: Date?
    /// Son ekran değişiminden sonra bu kadar sessizlik "yatıştı" sayılır
    /// (monitör takılınca macOS birkaç saniye boyunca yeniden düzenler).
    nonisolated static let settleInterval: TimeInterval = 2.5
    /// Değişimler hiç durmazsa (titrek kablo, sürekli bildirim) yatışma en
    /// geç bölümün başından bu kadar sonra zorla biter; yoksa `isSettling`
    /// hiç düşmez ve yönlendirme sonsuza dek kapalı kalırdı.
    nonisolated static let settleHardCap: TimeInterval = 10

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var isDocked: Bool { screens.contains { !$0.isBuiltin } }
    var mode: Mode { isDocked ? .docked : .undocked }

    func refresh() {
        screens = Self.detect()
    }

    private func screensChanged() {
        refresh()
        let now = Date()
        if !isSettling {
            isSettling = true
            settleEpisodeStart = now
            Log.screens.notice("Display change: \(self.screens.count) display(s), waiting to settle")
        }
        let delay = Self.settleDelay(episodeStart: settleEpisodeStart ?? now, now: now)
        let forced = delay < Self.settleInterval
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.settleEpisodeStart = nil
            self.refresh()
            self.isSettling = false
            Log.screens.notice("""
                Displays settled\(forced ? " (hard cap)" : "", privacy: .public): \
                \(self.screens.map(\.id).joined(separator: ", "), privacy: .public)
                """)
            self.settled.send()
        }
    }

    /// Bu ekran değişiminden sonra ne kadar beklenir (saf): normalde
    /// `settleInterval`; bölüm başlangıcından `settleHardCap` sonrasını
    /// aşmaz, sınır geçildiyse 0.
    nonisolated static func settleDelay(episodeStart: Date, now: Date) -> TimeInterval {
        let remaining = settleHardCap - now.timeIntervalSince(episodeStart)
        return max(0, min(settleInterval, remaining))
    }

    /// Harici ekranların rol sırası (`external`, `external-2` …): soldan
    /// sağa; aynı sütundaysa yukarıdan aşağı (Cocoa'da küçük minY alttadır,
    /// yine de sabit bir sıra verir); ikisi de eşitse UUID. Böylece aynı
    /// yerleşim her açılışta aynı rolleri üretir.
    nonisolated static func externalOrder(
        _ a: (minX: CGFloat, minY: CGFloat, uuid: String),
        _ b: (minX: CGFloat, minY: CGFloat, uuid: String)
    ) -> Bool {
        if a.minX != b.minX { return a.minX < b.minX }
        if a.minY != b.minY { return a.minY < b.minY }
        return a.uuid < b.uuid
    }

    static func detect() -> [ScreenInfo] {
        var builtin: [NSScreen] = []
        var externals: [(screen: NSScreen, uuid: String?)] = []

        for screen in NSScreen.screens {
            guard let displayID = ScreenInfo.displayID(of: screen) else { continue }
            if CGDisplayIsBuiltin(displayID) != 0 {
                builtin.append(screen)
            } else {
                externals.append((screen, ScreenInfo.uuid(of: screen)))
            }
        }
        externals.sort {
            externalOrder(($0.screen.frame.minX, $0.screen.frame.minY, $0.uuid ?? ""),
                          ($1.screen.frame.minX, $1.screen.frame.minY, $1.uuid ?? ""))
        }

        var result: [ScreenInfo] = []
        if let screen = builtin.first, let uuid = ScreenInfo.uuid(of: screen) {
            result.append(ScreenInfo(
                id: "builtin", uuid: uuid, name: screen.localizedName,
                isBuiltin: true, frame: screen.frame,
                visibleFrame: screen.visibleFrame))
        }
        for (index, external) in externals.enumerated() {
            guard let uuid = external.uuid else { continue }
            let screen = external.screen
            result.append(ScreenInfo(
                id: index == 0 ? "external" : "external-\(index + 1)",
                uuid: uuid, name: screen.localizedName, isBuiltin: false,
                frame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        return result
    }
}
