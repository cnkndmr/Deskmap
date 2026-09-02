import AppKit
import Combine

/// Bütün masaüstlerini sırayla ziyaret edip her birinde tarama yapar.
/// macOS'ta masaüstü değiştirmek için resmi API olmadığından Mission
/// Control'ün varsayılan kısayolları (Ctrl+← / Ctrl+→) klavye olayı
/// olarak üretilir. Çok ekranda kısayol imlecin bulunduğu ekrana
/// uygulandığı için önce imleç o ekrana taşınır. Tur bitince başlangıç
/// masaüstüne ve imleç eski yerine döner.
@MainActor
final class Tour: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var progress: String?

    private let router: Router
    private let screens: ScreenService
    private var task: Task<Void, Never>?

    init(router: Router, screens: ScreenService) {
        self.router = router
        self.screens = screens
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            await self?.run()
            self?.isRunning = false
            self?.progress = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - Tur

    private func run() async {
        let sky = SkyLight.shared
        let connected = screens.screens
        guard sky.isAvailable, AXIsProcessTrusted() else {
            progress = "Tur için SkyLight ve Erişilebilirlik gerekli"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return
        }

        let originalMouse = NSEvent.mouseLocation
        // Her şey yeniden yerleşsin: düzen belleği temizlenir.
        router.reapplyAll()
        await router.sweepAndWait()

        for display in sky.displaySpaces(mainUUID: Router.primaryUUID(connected)) {
            guard !Task.isCancelled else { break }
            guard let screen = connected.first(where: { $0.uuid == display.displayUUID }),
                  display.spaces.count > 1,
                  let start = display.spaces.firstIndex(where: { $0.id == display.current })
            else { continue }

            // Kısayol imlecin olduğu ekrana uygulanır.
            Self.warpMouse(toCenterOf: screen, screens: connected)
            try? await Task.sleep(nanoseconds: 150_000_000)

            let count = display.spaces.count
            // 1. En baştaki masaüstüne git.
            for _ in 0..<start {
                guard !Task.isCancelled else { break }
                await step(.left, on: display.displayUUID)
            }
            // 2. Sağa doğru hepsini gez; her birinde tara.
            for index in 0..<count {
                guard !Task.isCancelled else { break }
                progress = "\(screen.name) · \(index + 1)/\(count)"
                await router.sweepAndWait()
                if index < count - 1 {
                    await step(.right, on: display.displayUUID)
                }
            }
            // 3. Başlangıca dön.
            for _ in 0..<(count - 1 - start) {
                await step(.left, on: display.displayUUID)
            }
        }

        CGWarpMouseCursorPosition(Self.cgPoint(fromCocoa: originalMouse, screens: connected))
        await router.sweepAndWait()
    }

    private enum Direction { case left, right }

    /// Kısayolu gönderir, ekranın geçerli space'i değişene kadar (en çok
    /// 1,5 sn) bekler, sonra animasyonun bitmesi için kısa bir süre daha.
    private func step(_ direction: Direction, on displayUUID: String) async {
        let sky = SkyLight.shared
        let before = sky.displaySpaces(mainUUID: nil)
            .first { $0.displayUUID == displayUUID }?.current
        Self.press(direction == .left ? 0x7B : 0x7C, flags: .maskControl)

        var waited = 0
        while waited < 1_500 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 50
            let now = sky.displaySpaces(mainUUID: nil)
                .first { $0.displayUUID == displayUUID }?.current
            if now != before { break }
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    // MARK: - Olaylar

    private static func press(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
    }

    private static func warpMouse(toCenterOf screen: ScreenInfo, screens: [ScreenInfo]) {
        let rect = Coordinates.axRect(fromCocoa: screen.frame, screens: screens)
        CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Cocoa (sol alt tabanlı) noktayı CG (sol üst tabanlı) noktaya çevirir.
    private static func cgPoint(fromCocoa point: CGPoint, screens: [ScreenInfo]) -> CGPoint {
        let primaryHeight = screens.first { $0.frame.origin == .zero }?.frame.height
            ?? screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
