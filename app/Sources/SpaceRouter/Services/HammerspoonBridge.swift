import AppKit
import Combine

/// Motorun (Hammerspoon) kurulum ve çalışma durumu.
/// Kurallar dosya üzerinden paylaşıldığı için köprü yalnızca durum
/// bildirir ve isteğe bağlı olarak yeniden yükleme tetikler.
@MainActor
final class HammerspoonBridge: ObservableObject {

    static let bundleID = "org.hammerspoon.Hammerspoon"

    @Published private(set) var isInstalled = false
    @Published private(set) var isRunning = false
    @Published private(set) var isEngineLinked = false

    private var timer: Timer?

    private static let engineLinkURL: URL =
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".hammerspoon/spacerouter")

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        isInstalled = FileManager.default.fileExists(
            atPath: "/Applications/Hammerspoon.app")

        isRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.bundleID)
            .isEmpty

        isEngineLinked = FileManager.default.fileExists(
            atPath: Self.engineLinkURL.path)
    }

    var statusText: String {
        if !isInstalled { return "Hammerspoon kurulu değil" }
        if !isEngineLinked { return "Motor bağlanmamış — install.sh çalıştırın" }
        if !isRunning { return "Hammerspoon çalışmıyor" }
        return "Motor çalışıyor"
    }

    var isHealthy: Bool {
        isInstalled && isRunning && isEngineLinked
    }

    func launchHammerspoon() {
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: Self.bundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Motoru elle yeniden yükletir.
    /// Normalde gerekmez: motor rules.json dosyasını zaten izler.
    func reloadEngine() {
        openHammerspoonURL(action: "reload")
    }

    /// Açık pencereleri hemen yeniden değerlendirtir.
    func rescanWindows() {
        openHammerspoonURL(action: "rescan")
    }

    private func openHammerspoonURL(action: String) {
        guard isRunning,
              let url = URL(
                string: "hammerspoon://spacerouter?action=\(action)") else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(
            url, configuration: configuration, completionHandler: nil)
    }
}
