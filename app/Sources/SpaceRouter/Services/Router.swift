import AppKit
import Combine

/// Yönlendirme motoru. Açık pencereleri düzenli aralıklarla tarar,
/// kurala uyanları doğru ekranın doğru masaüstüne taşıyıp düzene oturtur.
///
/// Tarama arka planda çalışır; arayüz yalnızca özet durumu görür.
@MainActor
final class Router: ObservableObject {

    struct Placement: Equatable {
        let screen: String
        let desktop: Int
    }

    struct Status: Equatable {
        var routedWindows = 0
        var lastAction: String?
        var lastActionAt: Date?
    }

    @Published private(set) var status = Status()

    private let store: Store
    private let screens: ScreenService
    private let queue = DispatchQueue(label: "spacerouter.router", qos: .utility)
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// (pencere, hedef) çiftleri için düzen bir kez uygulanır; kullanıcı
    /// sonradan pencereyi elle taşırsa yerinden oynatılmaz.
    private var applied: Set<String> = []
    private var isSweeping = false

    init(store: Store, screens: ScreenService) {
        self.store = store
        self.screens = screens

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }

        screens.settled
            .sink { [weak self] in self?.reapplyAll() }
            .store(in: &cancellables)

        store.$document
            .map(\.rules)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reapplyAll() }
            .store(in: &cancellables)
    }

    deinit { timer?.invalidate() }

    /// Düzen belleğini sıfırlayıp bütün pencereleri yeniden yerleştirir.
    func reapplyAll() {
        applied.removeAll()
        sweep()
    }

    // MARK: - Tarama

    private func sweep() {
        guard store.document.enabled, !isSweeping, AXIsProcessTrusted() else { return }

        let rules = store.document.rules.bySpecificity
        let mode = screens.mode
        let connected = screens.screens
        let applied = self.applied
        isSweeping = true

        queue.async { [weak self] in
            let outcome = Self.route(rules: rules, mode: mode,
                                     screens: connected, applied: applied)
            Task { @MainActor in
                guard let self else { return }
                self.isSweeping = false
                self.applied = outcome.applied
                var status = self.status
                status.routedWindows = outcome.routed
                if let action = outcome.lastAction {
                    status.lastAction = action
                    status.lastActionAt = Date()
                }
                if status != self.status { self.status = status }
            }
        }
    }

    private struct Outcome {
        var applied: Set<String>
        var routed = 0
        var lastAction: String?
    }

    nonisolated private static func route(
        rules: [Rule], mode: Mode, screens: [ScreenInfo], applied: Set<String>
    ) -> Outcome {
        var outcome = Outcome(applied: applied)
        let sky = SkyLight.shared
        let displays = sky.displaySpaces(mainUUID: Self.primaryUUID(screens))
        let windows = AX.allWindows()

        for window in windows {
            guard let rule = rules.first(where: {
                $0.matches(bundleID: window.bundleID,
                           appName: window.appName, title: window.title)
            }), let destination = rule[mode] else { continue }

            guard let screen = screens.first(where: { $0.id == destination.screen })
            else { continue }

            outcome.routed += 1
            let key = "\(window.id)|\(rule.id)|\(mode.rawValue)|\(destination.hashValue)"

            // 1. Masaüstü
            if sky.isAvailable,
               let display = displays.first(where: { $0.displayUUID == screen.uuid }),
               !display.desktops.isEmpty {
                let desktops = display.desktops
                let target = desktops[min(destination.desktop, desktops.count) - 1]
                let current = sky.spaces(of: window.id)

                if !current.contains(target.id) {
                    // Tam ekran uygulamaya ait pencereler taşınmaz.
                    let onFullscreen = current.contains { sky.type(of: $0) != 0 }
                    if !onFullscreen {
                        sky.move(window: window.id, to: target.id)
                        outcome.applied.remove(key)
                        outcome.lastAction =
                            "\(window.appName) → \(screen.name) · Masaüstü "
                            + "\(min(destination.desktop, desktops.count))"
                    }
                }
            }

            // 2. Düzen
            guard !outcome.applied.contains(key), !AX.isMinimized(window) else { continue }
            let targetFrame = Coordinates.axRect(
                fromCocoa: destination.layout.rect(in: screen.visibleFrame),
                screens: screens)
            if let frame = AX.frame(of: window), Coordinates.close(frame, targetFrame) {
                outcome.applied.insert(key)
                continue
            }
            AX.setFrame(targetFrame, of: window)
            outcome.applied.insert(key)
        }
        return outcome
    }

    // MARK: - Yardımcılar

    nonisolated static func primaryUUID(_ screens: [ScreenInfo]) -> String? {
        (screens.first { $0.frame.origin == .zero } ?? screens.first)?.uuid
    }

    /// Pencerenin şu an bulunduğu ekran ve masaüstü sırası.
    nonisolated static func locate(_ window: AXWindow, screens: [ScreenInfo]) -> Placement? {
        let sky = SkyLight.shared
        let spaces = sky.spaces(of: window.id)
        for display in sky.displaySpaces(mainUUID: primaryUUID(screens)) {
            guard let screen = screens.first(where: { $0.uuid == display.displayUUID })
            else { continue }
            let desktops = display.desktops
            if let index = desktops.firstIndex(where: { spaces.contains($0.id) }) {
                return Placement(screen: screen.id, desktop: index + 1)
            }
        }
        // Space bilgisi yoksa pencere çerçevesinden ekranı bul.
        if let frame = AX.frame(of: window) {
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

    /// Bağlı ekranlardaki gerçek masaüstü sayıları.
    nonisolated static func desktopCounts(screens: [ScreenInfo]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for display in SkyLight.shared.displaySpaces(mainUUID: primaryUUID(screens)) {
            if let screen = screens.first(where: { $0.uuid == display.displayUUID }) {
                counts[screen.id] = display.desktops.count
            }
        }
        return counts
    }
}
