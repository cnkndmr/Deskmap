import AppKit
import SwiftUI

// MARK: - Pencere

/// İlk açılış rehberi: üç adım (erişilebilirlik izni → macOS ayarları →
/// nasıl başlanacağı). Uygulama ilk kez ve hiç sabitleme yokken açılır;
/// Ayarlar › Genel'den yeniden gösterilebilir. Bitince (ya da "Sonra")
/// bir daha kendiliğinden açılmaz.
@MainActor
final class WelcomeWindow {

    static let shared = WelcomeWindow()

    /// UserDefaults anahtarı: rehber bitirildi ya da geçildi.
    nonisolated static let doneKey = "welcomeDone"

    private var window: NSWindow?

    /// Açılışta gösterilmeli mi (saf): daha önce bitirilmediyse ve hiç
    /// sabitleme yoksa. Sabitlemesi olan (eski) kurulumda gösterilmez.
    nonisolated static func shouldShow(done: Bool, ruleCount: Int) -> Bool {
        !done && ruleCount == 0
    }

    func showIfNeeded() {
        let model = AppModel.shared
        let done = UserDefaults.standard.bool(forKey: Self.doneKey)
        guard Self.shouldShow(done: done, ruleCount: model.store.document.rules.count) else {
            // Sabitlemesi olan kurulumda rehber bir daha sorulmasın.
            if !done { UserDefaults.standard.set(true, forKey: Self.doneKey) }
            return
        }
        show()
    }

    func show() {
        let model = AppModel.shared
        if window == nil {
            let view = WelcomeView { [weak self] in self?.finish() }
                .environmentObject(model.store)
                .environmentObject(model.router)
                .environmentObject(model.screens)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = L("Welcome to Deskmap")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        AppModel.shared.store.document.setupNoticeDismissed = true
        window?.close()
    }
}

// MARK: - Görünüm

struct WelcomeView: View {

    let finish: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    @StateObject private var permission = AccessibilityPermission()

    /// 1 izin, 2 macOS ayarları, 3 başla.
    @State private var step = 1
    @State private var checks = MacSettings.checks()
    /// Shots modu: izin ve ayarlar dışarıdan verilir, zamanlayıcı kurulmaz.
    var demoStep: Int?
    var demoTrusted: Bool?

    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(demoStep: Int? = nil, demoTrusted: Bool? = nil, finish: @escaping () -> Void) {
        self.demoStep = demoStep
        self.demoTrusted = demoTrusted
        self.finish = finish
    }

    private var trusted: Bool { demoTrusted ?? permission.isTrusted }
    private var currentStep: Int { demoStep ?? step }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            steps
            switch currentStep {
            case 1: permissionStep
            case 2: settingsStep
            default: startStep
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .topLeading)
        .onReceive(refresh) { _ in
            guard demoStep == nil else { return }
            checks = MacSettings.checks()
        }
    }

    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { index in
                let title = [L("Permission"), L("macOS settings"), L("Start")][index - 1]
                let done = index < currentStep
                Text((done ? "✓ " : "\(index) · ") + title)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(index == currentStep ? Color.accentColor
                                               : Color.primary.opacity(0.07)))
                    .foregroundStyle(index == currentStep ? Color.white
                                     : done ? Color.green : Color.secondary)
            }
        }
    }

    // MARK: 1 — izin

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Welcome to Deskmap")).font(.title2.weight(.semibold))
            Text(L("Deskmap puts each window on the display, desktop and spot you choose, and puts it back when it wanders off. To move windows it needs the Accessibility permission."))
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Deskmap works offline: it makes no network connections and never reads what is inside your windows, only their titles, positions and desktops."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if trusted {
                Label(L("Permission granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(L("Open System Settings and allow")) {
                    permission.request()
                    permission.openSettings()
                }
                .buttonStyle(.borderedProminent)
                Text(L("Turn on Deskmap in the list; this page notices it by itself."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            footer(back: false, canContinue: trusted)
        }
    }

    // MARK: 2 — macOS ayarları

    private var settingsStep: some View {
        let ok = MacSettings.allRequiredOK(checks)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("macOS settings")).font(.title2.weight(.semibold))
            Text(ok ? L("All required settings are right.")
                    : L("One or more Mission Control settings must change for Deskmap to work."))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(checks.filter(\.required)) { check in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.ok ? Color.green : Color.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.title).font(.callout.weight(.medium))
                        if !check.ok {
                            Text(check.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !ok {
                HStack {
                    Button(L("Open Desktop & Dock")) { MacSettings.openDesktopAndDock() }
                    Text(L("Fixed settings turn green by themselves."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            footer(back: true, canContinue: ok)
        }
    }

    // MARK: 3 — başla

    private var unpinned: [Router.WindowSnapshot] {
        ScreenMapView.unownedWindows(router.windows, rules: store.document.rules,
                                     sessionPins: router.sessionPins)
            .filter { $0.placement != nil && $0.fullscreen == nil }
    }

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("How do you want to start?")).font(.title2.weight(.semibold))
            choice(
                title: L("Pin my windows where they are (recommended)"),
                detail: unpinned.count == 1
                    ? L("1 open window is pinned to its current desktop, size and position. Fix any of them later; one click undoes it.")
                    : L("%ld open windows are pinned to their current desktop, size and position. Fix any of them later; one click undoes it.", unpinned.count),
                prominent: true
            ) {
                MultiPinBar.pinWhereTheyAre(Set(unpinned.map(\.id)), store: store,
                                            router: router, screens: screens)
                finish()
            }
            .disabled(unpinned.isEmpty)
            choice(
                title: L("Start empty"),
                detail: L("Nothing is pinned. Click the Deskmap icon in the menu bar and drag a window onto a desktop, or click its pin."),
                prominent: false,
                action: finish)
            footer(back: true, canContinue: nil)
        }
    }

    private func choice(title: String, detail: String, prominent: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(prominent ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(prominent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Alt satır: Sonra / Geri / Devam. `canContinue` nil ise Devam yok.
    private func footer(back: Bool, canContinue: Bool?) -> some View {
        HStack {
            Button(L("Later"), action: finish)
                .help(L("Close the guide; it can be opened again from Settings › General"))
            Spacer()
            if back {
                Button(L("Back")) { step = max(1, step - 1) }
            }
            if let canContinue {
                Button(L("Continue")) { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 6)
    }
}
