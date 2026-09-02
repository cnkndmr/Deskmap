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

    /// Ekran değişimi yatıştıktan sonra tetiklenir.
    let settled = PassthroughSubject<Void, Never>()

    private var observer: NSObjectProtocol?
    private var settleTask: Task<Void, Never>?

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
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            // Monitör takılınca macOS birkaç saniye boyunca yeniden düzenler.
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
            self?.settled.send()
        }
    }

    static func detect() -> [ScreenInfo] {
        var builtin: [NSScreen] = []
        var externals: [NSScreen] = []

        for screen in NSScreen.screens {
            guard let displayID = ScreenInfo.displayID(of: screen) else { continue }
            if CGDisplayIsBuiltin(displayID) != 0 {
                builtin.append(screen)
            } else {
                externals.append(screen)
            }
        }
        externals.sort { $0.frame.minX < $1.frame.minX }

        var result: [ScreenInfo] = []
        if let screen = builtin.first, let uuid = ScreenInfo.uuid(of: screen) {
            result.append(ScreenInfo(
                id: "builtin", uuid: uuid, name: screen.localizedName,
                isBuiltin: true, frame: screen.frame,
                visibleFrame: screen.visibleFrame))
        }
        for (index, screen) in externals.enumerated() {
            guard let uuid = ScreenInfo.uuid(of: screen) else { continue }
            result.append(ScreenInfo(
                id: index == 0 ? "external" : "external-\(index + 1)",
                uuid: uuid, name: screen.localizedName, isBuiltin: false,
                frame: screen.frame, visibleFrame: screen.visibleFrame))
        }
        return result
    }
}
