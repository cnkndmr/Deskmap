import AppKit
import CoreGraphics
import Combine

/// Bağlı bir ekranın motorun ihtiyaç duyduğu kimliği.
struct DetectedScreen: Identifiable, Equatable, Hashable {
    var id: String { uuid }
    let uuid: String
    let name: String
    let isBuiltin: Bool
    let pixelSize: CGSize
}

/// Bağlı ekranları ve dock durumunu izler.
@MainActor
final class ScreenService: ObservableObject {

    @Published private(set) var screens: [DetectedScreen] = []

    private var observer: NSObjectProtocol?

    init() {
        refresh()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Harici monitörlerden en az biri bağlı mı?
    var isDocked: Bool {
        screens.contains { !$0.isBuiltin }
    }

    func refresh() {
        screens = NSScreen.screens.compactMap(Self.describe)
    }

    /// NSScreen -> kalıcı UUID.
    /// UUID kullanılır çünkü ekranların sırası ve adı değişebilir.
    private static func describe(_ screen: NSScreen) -> DetectedScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")

        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(number.uint32Value)

        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?
            .takeRetainedValue() else {
            return nil
        }

        let uuid = CFUUIDCreateString(nil, cfUUID) as String

        return DetectedScreen(
            uuid: uuid,
            name: screen.localizedName,
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            pixelSize: screen.frame.size)
    }
}
