import AppKit
import ApplicationServices

/// Kural yazarken kullanılan canlı pencere listesi.
struct ObservedWindow: Identifiable, Hashable {
    let id: String
    let applicationName: String
    let bundleID: String
    let title: String
}

/// Açık pencerelerin uygulama adı, bundle id ve başlığını okur.
/// Accessibility izni olmadan başlıklar boş döner.
@MainActor
final class WindowInspector: ObservableObject {

    @Published private(set) var windows: [ObservedWindow] = []
    @Published private(set) var refreshedAt: Date?

    func refresh() {
        var collected: [ObservedWindow] = []

        let applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        for application in applications {
            let axApplication =
                AXUIElementCreateApplication(application.processIdentifier)

            var rawWindows: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                axApplication,
                kAXWindowsAttribute as CFString,
                &rawWindows)

            guard result == .success,
                  let axWindows = rawWindows as? [AXUIElement] else {
                continue
            }

            let applicationName = application.localizedName ?? "?"
            let bundleID = application.bundleIdentifier ?? "?"

            for (index, axWindow) in axWindows.enumerated() {
                var rawTitle: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(
                    axWindow, kAXTitleAttribute as CFString, &rawTitle)

                let title = (rawTitle as? String) ?? ""
                guard !title.isEmpty else { continue }

                collected.append(
                    ObservedWindow(
                        id: "\(bundleID)#\(index)#\(title)",
                        applicationName: applicationName,
                        bundleID: bundleID,
                        title: title))
            }
        }

        windows = collected.sorted {
            ($0.applicationName, $0.title) < ($1.applicationName, $1.title)
        }
        refreshedAt = Date()
    }
}
