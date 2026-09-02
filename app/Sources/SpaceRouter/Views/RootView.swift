import AppKit
import ServiceManagement
import SwiftUI

/// Pencere içi görünüm durumu. Menü çubuğu penceresi popover, sheet veya
/// menü açılınca kapandığı için her şey aynı pencerede, satır içi gösterilir.
@MainActor
final class UIState: ObservableObject {
    @Published var adding = false
    @Published var editingRuleID: String?

    /// Sürükleme sırasında canlı durum ve bilinen hedef çerçeveleri.
    @Published var drag: ChipDrag?
    var targets: [DropTargetFrame] = []

    func target(at point: CGPoint) -> DropTarget? {
        targets.first { $0.frame.contains(point) }?.target
    }
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
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                }

                Divider()
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 560, height: 600)
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

/// Çipe tıklanınca haritanın altında açılan düzen paneli: hazır düzenler
/// ve yüzde cinsinden kenar boşlukları.
private struct RuleOptionsPanel: View {

    let rule: Rule
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AppIcon(bundleID: rule.bundleID, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.appName).font(.callout.weight(.semibold))
                    Text(rule.title).font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)

                Spacer()

                Button {
                    store.remove(rule.id)
                    ui.editingRuleID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Kuralı sil")

                Button {
                    ui.editingRuleID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Kapat")
            }

            if let destination = rule[mode] {
                LayoutEditor(layout: Binding(
                    get: { destination.layout },
                    set: { layout in
                        var updated = destination
                        updated.layout = layout
                        store.setDestination(updated, for: rule.id, mode: mode)
                    }))
            } else {
                Text("Düzen seçmek için önce çipi bir masaüstüne sürükleyin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Hazır düzenler + yüzde kenar boşlukları + canlı önizleme.
private struct LayoutEditor: View {

    @Binding var layout: WindowLayout

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Önizleme
            VStack(spacing: 6) {
                LayoutGlyph(layout: layout, size: CGSize(width: 128, height: 80))
                    .foregroundStyle(Color.accentColor)
                Text(layout.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                // Hazır düzenler
                HStack(spacing: 4) {
                    ForEach(WindowLayout.presets, id: \.self) { preset in
                        let isSelected = preset == layout
                        Button {
                            layout = preset
                        } label: {
                            LayoutGlyph(preset: preset)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15)
                                                         : Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .help(preset.label)
                    }
                }

                // Kenar boşlukları
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        PercentField("Sol", systemImage: "arrow.left.to.line",
                                     value: leftBinding)
                        PercentField("Sağ", systemImage: "arrow.right.to.line",
                                     value: rightBinding)
                    }
                    GridRow {
                        PercentField("Üst", systemImage: "arrow.up.to.line",
                                     value: topBinding)
                        PercentField("Alt", systemImage: "arrow.down.to.line",
                                     value: bottomBinding)
                    }
                }
                Text("Ekranın kullanılabilir alanında, kenardan bırakılacak boşluk.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // Kenar boşluğu (%) <-> oran dönüşümleri. Genişlik en az %10 kalır.

    private var leftBinding: Binding<Int> {
        Binding(
            get: { Int((layout.x * 100).rounded()) },
            set: { left in
                let right = 100 - Int(((layout.x + layout.w) * 100).rounded())
                let clamped = min(max(left, 0), 90 - right)
                layout.x = Double(clamped) / 100
                layout.w = Double(100 - clamped - right) / 100
            })
    }

    private var rightBinding: Binding<Int> {
        Binding(
            get: { 100 - Int(((layout.x + layout.w) * 100).rounded()) },
            set: { right in
                let left = Int((layout.x * 100).rounded())
                let clamped = min(max(right, 0), 90 - left)
                layout.w = Double(100 - left - clamped) / 100
            })
    }

    private var topBinding: Binding<Int> {
        Binding(
            get: { Int((layout.y * 100).rounded()) },
            set: { top in
                let bottom = 100 - Int(((layout.y + layout.h) * 100).rounded())
                let clamped = min(max(top, 0), 90 - bottom)
                layout.y = Double(clamped) / 100
                layout.h = Double(100 - clamped - bottom) / 100
            })
    }

    private var bottomBinding: Binding<Int> {
        Binding(
            get: { 100 - Int(((layout.y + layout.h) * 100).rounded()) },
            set: { bottom in
                let top = Int((layout.y * 100).rounded())
                let clamped = min(max(bottom, 0), 90 - top)
                layout.h = Double(100 - top - clamped) / 100
            })
    }
}

/// "Sol  [ 10 ] %  −/+" biçiminde tek satırlık yüzde alanı.
private struct PercentField: View {

    let label: String
    let systemImage: String
    @Binding var value: Int

    init(_ label: String, systemImage: String, value: Binding<Int>) {
        self.label = label
        self.systemImage = systemImage
        _value = value
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .frame(width: 24, alignment: .leading)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 46)
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("", value: $value, in: 0...90, step: 5)
                .labelsHidden()
        }
        .controlSize(.small)
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
