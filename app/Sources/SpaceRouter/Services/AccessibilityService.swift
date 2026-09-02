import AppKit
import ApplicationServices
import Combine

/// Accessibility izninin durumunu izler.
/// Pencere başlıklarını okumak ve pencereleri taşımak bu izne bağlıdır.
@MainActor
final class AccessibilityService: ObservableObject {

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var timer: Timer?

    init() {
        // İzin System Settings'ten verilir; uygulamaya bildirim gelmez.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let current = AXIsProcessTrusted()
        if current != isTrusted {
            isTrusted = current
        }
    }

    /// Sistem izin penceresini açar.
    func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Doğrudan ayarlar bölmesini açar.
    func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security" +
                    "?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
