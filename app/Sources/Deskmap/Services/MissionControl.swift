import AppKit
import ApplicationServices

/// Mission Control üzerinden masaüstü ekleme. macOS'ta masaüstü yaratan
/// açık ya da SIP'siz çalışan özel bir çağrı yok; Hammerspoon'un
/// `hs.spaces.addSpaceToScreen` yöntemindeki gibi Mission Control kısa
/// açılır, ilgili ekranın "+" düğmesine Accessibility ile basılır, kapanır.
///
/// Ağaç (ölçüldü, macOS 26, 25.09.2026): `com.apple.WindowManager`
/// uygulamasının çocukları `mc.display` grupları (`AXDisplayID` =
/// CGDirectDisplayID), her birinde `mc.spaces` → `mc.spaces.add` düğmesi.
/// Eski macOS'ta aynı ağaç Dock'ta `mc` grubunun altındadır.
@MainActor
enum MissionControl {

    /// Mission Control ağacı bu süre içinde belirmezse vazgeçilir.
    private static let appearTimeout: TimeInterval = 2.0
    private static let pollInterval: UInt64 = 100_000_000

    /// Verilen ekrana bir masaüstü ekler; eklenen masaüstü sayısı
    /// SkyLight'ta görülürse true. Mission Control her durumda kapatılır.
    static func addDesktop(displayID: CGDirectDisplayID, displayUUID: String) async -> Bool {
        let before = desktopCount(uuid: displayUUID)
        guard openMissionControl() else {
            Log.app.error("Add desktop: Mission Control could not be opened")
            return false
        }
        defer { close() }

        let deadline = Date().addingTimeInterval(appearTimeout)
        var button: AXUIElement?
        while button == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: pollInterval)
            button = addButton(displayID: displayID)
        }
        guard let button else {
            Log.app.error("Add desktop: '+' button not found for display \(displayID)")
            return false
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard result == .success else {
            Log.app.error("Add desktop: press failed (\(result.rawValue))")
            return false
        }
        // Yeni space SkyLight'ta birkaç yüz ms içinde görünür.
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: pollInterval)
            if let before, let now = desktopCount(uuid: displayUUID), now > before {
                Log.app.notice("Desktop added on display \(displayID): \(before) → \(now)")
                return true
            }
        }
        Log.app.notice("Add desktop: pressed '+' but the desktop count did not change yet")
        return before == nil
    }

    /// Verilen ekrandaki `desktop`. normal masaüstünü siler (içindeki
    /// pencereleri macOS başka masaüstüne taşır). Mission Control'deki
    /// sıra SkyLight'ın space sırasıyla aynıdır (tam ekran space'ler dahil);
    /// sayılar uyuşmazsa hiçbir şeye dokunulmaz. Son masaüstü silinmez.
    static func removeDesktop(displayID: CGDirectDisplayID, displayUUID: String,
                              desktop: Int) async -> Bool {
        guard let display = SkyLight.shared.displaySpaces(mainUUID: nil)
                .first(where: { $0.displayUUID == displayUUID }) else { return false }
        let desktops = display.desktops
        guard desktops.count > 1, desktop >= 1, desktop <= desktops.count,
              let index = display.spaces.firstIndex(of: desktops[desktop - 1])
        else { return false }
        guard openMissionControl() else { return false }
        defer { close() }

        let deadline = Date().addingTimeInterval(appearTimeout)
        var buttons: [AXUIElement] = []
        while buttons.isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: pollInterval)
            buttons = spaceButtons(displayID: displayID)
        }
        guard buttons.count == display.spaces.count else {
            Log.app.error("Remove desktop: Mission Control shows \(buttons.count) spaces, SkyLight \(display.spaces.count); nothing removed")
            return false
        }
        let result = AXUIElementPerformAction(buttons[index], "AXRemoveDesktop" as CFString)
        guard result == .success else {
            Log.app.error("Remove desktop: action failed (\(result.rawValue))")
            return false
        }
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: pollInterval)
            if let now = desktopCount(uuid: displayUUID), now < desktops.count {
                Log.app.notice("Desktop \(desktop) removed on display \(displayID): \(desktops.count) → \(now)")
                return true
            }
        }
        Log.app.notice("Remove desktop: action sent but the desktop count did not change")
        return false
    }

    // MARK: - Yardımcılar

    /// İlgili ekranın `mc.spaces.list` düğmeleri, Mission Control sırasıyla.
    private static func spaceButtons(displayID: CGDirectDisplayID) -> [AXUIElement] {
        for display in displayGroups()
        where (value(display, "AXDisplayID") as? NSNumber)?.uint32Value == displayID {
            for bar in children(display) where identifier(bar) == "mc.spaces" {
                if let list = children(bar).first(where: { identifier($0) == "mc.spaces.list" }) {
                    return children(list)
                }
            }
        }
        return []
    }

    private static func openMissionControl() -> Bool {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }

    /// Escape ile kapatır (Mission Control açıkken tuş ona gider).
    private static func close() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?
                .post(tap: .cghidEventTap)
        }
    }

    private static func desktopCount(uuid: String) -> Int? {
        SkyLight.shared.displaySpaces(mainUUID: nil)
            .first { $0.displayUUID == uuid }?.desktops.count
    }

    /// İlgili ekranın `mc.spaces.add` düğmesi; ağaç henüz yoksa nil.
    private static func addButton(displayID: CGDirectDisplayID) -> AXUIElement? {
        for display in displayGroups()
        where (value(display, "AXDisplayID") as? NSNumber)?.uint32Value == displayID {
            for bar in children(display) where identifier(bar) == "mc.spaces" {
                if let add = children(bar).first(where: { identifier($0) == "mc.spaces.add" }) {
                    return add
                }
            }
        }
        return nil
    }

    /// `mc.display` grupları: önce WindowManager (macOS 26+), sonra Dock.
    private static func displayGroups() -> [AXUIElement] {
        var groups: [AXUIElement] = []
        for bundleID in ["com.apple.WindowManager", "com.apple.dock"] {
            guard let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.5)
            for child in children(element) {
                switch identifier(child) {
                case "mc.display": groups.append(child)
                case "mc": groups += children(child).filter { identifier($0) == "mc.display" }
                default: break
                }
            }
        }
        return groups
    }

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success
        else { return nil }
        return result
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func identifier(_ element: AXUIElement) -> String? {
        value(element, kAXIdentifierAttribute) as? String
    }
}
