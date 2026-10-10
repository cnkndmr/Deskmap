import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Pencere

/// Ayarlar penceresi (⌘,): Genel, macOS ayarları, Profiller, Kısayollar.
///
/// SwiftUI `Settings` sahnesi menü çubuğu uygulamasında (LSUIElement) macOS
/// 14+'te yalnızca `SettingsLink`/`openSettings` ile açılıyor ve harita
/// penceresinin arkasında kalabiliyor; tek bir AppKit penceresi her sürümde
/// aynı davranır. Pencere bir kez yaratılır, kapatılınca gizlenir.
@MainActor
final class SettingsWindow {

    static let shared = SettingsWindow()

    private var window: NSWindow?
    private let state = SettingsState()

    func show(tab: SettingsTab = .general, store: Store) {
        state.tab = tab
        if window == nil {
            let host = NSHostingController(rootView:
                SettingsView(state: state).environmentObject(store))
            let window = NSWindow(contentViewController: host)
            window.title = L("Deskmap Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(SettingsView.size)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, macOS, profiles, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:   return L("General")
        case .macOS:     return L("macOS Settings")
        case .profiles:  return L("Profiles")
        case .shortcuts: return L("Shortcuts")
        }
    }

    var symbol: String {
        switch self {
        case .general:   return "gearshape"
        case .macOS:     return "macwindow"
        case .profiles:  return "square.stack.3d.up"
        case .shortcuts: return "keyboard"
        }
    }
}

@MainActor
final class SettingsState: ObservableObject {
    @Published var tab: SettingsTab = .general
}

// MARK: - Görünüm

struct SettingsView: View {

    static let size = NSSize(width: 680, height: 460)

    @ObservedObject var state: SettingsState
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        state.tab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(state.tab == tab ? Color.primary.opacity(0.1) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 180)
            .background(Color.primary.opacity(0.03))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(state.tab.title).font(.title3.weight(.semibold))
                    switch state.tab {
                    case .general:   GeneralSettings()
                    case .macOS:     MacOSSettings()
                    case .profiles:  ProfileSettings()
                    case .shortcuts: ShortcutSettings()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// Ayar satırı: solda başlık ve açıklama, sağda denetim.
private struct SettingRow<Control: View>: View {

    let title: String
    var detail: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Genel

private struct GeneralSettings: View {

    @EnvironmentObject private var store: Store

    /// "Girişte başlat" kaydının gerçek durumu; kullanıcı Sistem
    /// Ayarları'ndan kapatabildiği için her görünüşte yeniden okunur.
    @State private var loginStatus: SMAppService.Status = SMAppService.mainApp.status

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: L("Deskmap on"),
                       detail: L("When paused, Deskmap moves no windows; the map still shows them.")) {
                Toggle("", isOn: $store.document.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingRow(title: L("Launch at login"), detail: launchAtLoginHelp) {
                HStack(spacing: 8) {
                    if loginStatus == .requiresApproval {
                        // Kayıt var ama macOS onay bekliyor (Login Items'ta kapalı).
                        Button(L("Approval needed")) { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                            .foregroundStyle(.orange)
                            .help(L("Turn on Deskmap in System Settings › General › Login Items"))
                    }
                    Toggle("", isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                        set: { setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            SettingRow(title: L("Quit Deskmap"),
                       detail: L("Windows stay where they are; nothing is moved until Deskmap runs again.")) {
                Button(L("Quit")) { NSApplication.shared.terminate(nil) }
            }
        }
        .onAppear { refreshLoginStatus() }
    }

    /// Bu kopya /Applications dışındaysa (build/ içinden çalışıyorsa)
    /// girişte bu yol açılır; taşınır ya da silinirse kayıt boşa düşer.
    private var launchAtLoginHelp: String {
        let path = Bundle.main.bundleURL.path
        if path.hasPrefix("/Applications/") {
            return L("Deskmap starts when you log in to macOS")
        }
        return L("This copy opens at login: %@. For a permanent install, copy it to /Applications.", path)
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        if status != loginStatus { loginStatus = status }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            store.report(enabled
                ? L("Could not turn on launch at login: %@", error.localizedDescription)
                : L("Could not turn off launch at login: %@", error.localizedDescription))
        }
        // Gerçek durumu oku: register sonrası .requiresApproval da olabilir.
        refreshLoginStatus()
    }
}

// MARK: - macOS ayarları

private struct MacOSSettings: View {

    @State private var checks = MacSettings.checks()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Deskmap needs a few Mission Control settings. They are checked continuously; if one changes, the menu bar icon turns orange."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SetupCard(checks: checks, dismissible: false)
            Button(L("Check Again")) { checks = MacSettings.checks() }
                .controlSize(.small)
        }
        .onAppear { checks = MacSettings.checks() }
    }
}

// MARK: - Profiller

private struct ProfileSettings: View {

    @EnvironmentObject private var store: Store

    /// Yeniden adlandırılan profil ve taslak adı.
    @State private var editing: String?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("A profile is a separate set of pinned windows, for example one for the office desk and one for working elsewhere. Only the active profile places windows."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            ForEach(store.profiles) { profile in
                row(profile)
            }

            HStack(spacing: 8) {
                Button {
                    let profile = store.addProfile()
                    editing = profile.id
                    name = profile.name
                } label: {
                    Label(L("New empty profile"), systemImage: "plus")
                }
                Button {
                    ProfileFiles.importProfile(into: store)
                } label: {
                    Label(L("Import…"), systemImage: "square.and.arrow.down")
                }
                .help(L("Import a profile from a file (.deskmap.json)"))
            }
            .controlSize(.small)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func row(_ profile: Profile) -> some View {
        let isActive = profile.id == store.document.activeProfileID
        return HStack(spacing: 8) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            if editing == profile.id {
                TextField(L("Profile name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { commit(profile.id) }
                Button(L("Save")) { commit(profile.id) }
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name).fontWeight(isActive ? .semibold : .regular)
                    Text(pinCount(profile.rules.count)
                         + (isActive ? " · " + L("active") : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isActive {
                Button(L("Use")) { store.switchProfile(to: profile.id) }
                    .help(L("Switch to this profile"))
            }
            Menu {
                Button(L("Rename")) { editing = profile.id; name = profile.name }
                Button(L("Duplicate")) {
                    if !isActive { store.switchProfile(to: profile.id) }
                    store.addProfile(named: L("%@ copy", profile.name), copyingCurrent: true)
                }
                Button(L("Export…")) { ProfileFiles.exportProfile(profile.id, from: store) }
                Divider()
                Button(L("Delete"), role: .destructive) { store.deleteProfile(profile.id) }
                    .disabled(store.profiles.count < 2)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Rename, duplicate, export or delete"))
            .accessibilityLabel(L("Rename, duplicate, export or delete"))
        }
        .controlSize(.small)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }

    private func commit(_ id: String) {
        store.renameProfile(id, to: name)
        editing = nil
    }
}

/// "1 pin" / "%ld pins" / "no pins" (Türkçede "sabit pencere").
func pinCount(_ count: Int) -> String {
    count == 0 ? L("no pins") : count == 1 ? L("1 pin") : L("%ld pins", count)
}

// MARK: - Kısayollar

private struct ShortcutSettings: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("These work while the map is open."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
            row(L("Show the Monitor connected plan"), "⌘1")
            row(L("Show the Laptop only plan"), "⌘2")
            row(L("Place pinned windows now"), "⌘R")
            row(L("Undo the last action"), "⌘Z")
            row(L("Settings"), "⌘,")
            row(L("Select several windows"), L("⌘-click"))
        }
    }

    private func row(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Açıklama paneli

/// Üst çubuktaki "?" düğmesinin açtığı kısa sözlük: haritadaki renkler,
/// rozetler ve simgeler ne anlama geliyor.
struct LegendView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("What the map shows")).font(.headline)
            entry(swatch: rowSwatch(pinned: true),
                  title: L("Pinned"),
                  text: L("Deskmap keeps this window on this desktop and in this layout. Moved by hand, it goes back."))
            entry(swatch: rowSwatch(pinned: false),
                  title: L("Not pinned"),
                  text: L("Deskmap leaves this window alone. Click its pin to keep it where it is."))
            entry(swatch: AnyView(Label("15:00", systemImage: "timer")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.teal)),
                  title: L("Free for a while"),
                  text: L("You can move a pinned window by hand; when the time is up it goes back."))
            entry(swatch: AnyView(MissingDesktopBadge(wanted: 5, real: 3)),
                  title: L("Missing desktop"),
                  text: L("The desktop the pin asks for does not exist right now; the window waits on the last one. Add the desktop in Mission Control and it moves there."))
            entry(swatch: AnyView(LayoutGlyph(preset: .leftHalf).foregroundStyle(.secondary)),
                  title: L("Layout"),
                  text: L("Where on the screen the window sits: full, left half, a corner…"))
            entry(swatch: AnyView(Label(L("Full Screen"), systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2).foregroundStyle(.purple)),
                  title: L("Full Screen"),
                  text: L("macOS gives a full-screen window its own space; Deskmap does not touch it."))
            entry(swatch: AnyView(Text(L("active now")).font(.caption2).foregroundStyle(.green)),
                  title: L("Plan"),
                  text: L("Monitor connected and Laptop only are two separate plans. The one in effect right now is marked."))
        }
        .padding(14)
        .frame(width: 380)
    }

    private func rowSwatch(pinned: Bool) -> AnyView {
        AnyView(HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.4))
                .frame(width: 22, height: 6)
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 9))
                .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(pinned ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(pinned ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12),
                          lineWidth: 1)))
    }

    private func entry(swatch: AnyView, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            swatch.frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
