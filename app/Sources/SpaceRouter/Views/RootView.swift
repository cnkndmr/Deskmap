import AppKit
import ServiceManagement
import SwiftUI

/// Pencere içi görünüm durumu. Menü çubuğu penceresi popover, sheet veya
/// menü açılınca kapandığı için her şey aynı pencerede, satır içi gösterilir.
@MainActor
final class UIState: ObservableObject {
    @Published var adding = false
    @Published var editingRuleID: String?
}

struct RootView: View {

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var permission: AccessibilityPermission
    @EnvironmentObject private var ui: UIState

    @State private var mode: Mode = .undocked
    @State private var desktopCounts: [String: Int] = [:]
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            if ui.adding {
                AddWindowView(mode: mode) { rule in
                    store.add(rule)
                    ui.adding = false
                } onCancel: {
                    ui.adding = false
                }
            } else {
                header
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()

                ScrollView {
                    VStack(spacing: 14) {
                        if !permission.isTrusted {
                            PermissionCard()
                        }
                        ScreenMapView(mode: mode, desktopCounts: desktopCounts)
                    }
                    .padding(14)
                }

                if let id = ui.editingRuleID, let rule = store.rule(id) {
                    Divider()
                    RuleOptionsPanel(rule: rule, mode: mode)
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                }

                Divider()
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 560, height: 540)
        .background(.regularMaterial)
        .onAppear {
            mode = screens.mode
            syncScreens()
        }
        .onReceive(screens.$screens) { _ in syncScreens() }
        .onChange(of: mode) { _ in ui.editingRuleID = nil }
    }

    private func syncScreens() {
        store.remember(screens.screens.map(\.known))
        desktopCounts = Router.desktopCounts(screens: screens.screens)
    }

    // MARK: - Üst çubuk

    private var header: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $store.document.enabled) {
                Image(systemName: "power")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(store.document.enabled ? "Yönlendirme açık" : "Yönlendirme duraklatıldı")

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { candidate in
                    Image(systemName: candidate.symbol)
                        .help(candidate.title)
                        .tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            if mode == screens.mode {
                Text("şu an")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                router.reapplyAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Pencereleri şimdi yerleştir")

            Button {
                ui.editingRuleID = nil
                ui.adding = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!permission.isTrusted)
            .help("Açık bir pencereden kural ekle")
        }
    }

    // MARK: - Alt çubuk

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if let error = store.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if let action = router.status.lastAction {
                    Label(action, systemImage: "arrow.turn.down.right")
                } else {
                    Text(store.document.rules.isEmpty
                         ? "+ ile bir pencere ekleyin, çipi masaüstüne sürükleyin."
                         : "Eşleşen pencereler otomatik yerleştirilir.")
                }
            }
            .lineLimit(1)

            Spacer()

            Toggle("Girişte başlat", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { enabled in
                    if enabled {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Space Router'dan çık")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Seçili kural paneli

/// Çipe tıklanınca haritanın altında açılan düzen seçici ve silme.
private struct RuleOptionsPanel: View {

    let rule: Rule
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                AppIcon(bundleID: rule.bundleID, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.appName).font(.caption.weight(.semibold))
                    Text(rule.title).font(.caption2).foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            if let destination = rule[mode] {
                HStack(spacing: 4) {
                    ForEach(WindowLayout.presets, id: \.self) { layout in
                        let isSelected = layout == destination.layout
                        Button {
                            var updated = destination
                            updated.layout = layout
                            store.setDestination(updated, for: rule.id, mode: mode)
                        } label: {
                            LayoutGlyph(layout: layout, size: CGSize(width: 34, height: 22))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15)
                                                         : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .help(layout.label)
                    }
                }
            } else {
                Text("Bir masaüstüne sürükleyin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.remove(rule.id)
                ui.editingRuleID = nil
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Kuralı sil")

            Button {
                ui.editingRuleID = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Kapat")
        }
    }
}

// MARK: - İzin kartı

private struct PermissionCard: View {

    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Erişilebilirlik izni gerekli")
                    .font(.callout.weight(.semibold))
                Text("Pencereleri görmek ve taşımak için.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("İzin ver") {
                permission.request()
                permission.openSettings()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
    }
}
