import AppKit
import ServiceManagement
import SwiftUI

/// Pencere içi görünüm durumu. Menü çubuğu penceresi popover, sheet veya
/// menü açılınca kapandığı için her şey aynı pencerede, satır içi gösterilir.
@MainActor
final class UIState: ObservableObject {
    /// Çipine tıklanan (penceresi kapalı ya da diğer moddaki) pin.
    @Published var selectedRuleID: String?
    /// Pin düğmesi / sürükleme sonrası başlık parçası bekleyen taslak.
    @Published var pinDraft: PinDraft?
    /// Daraltılmış uygulama grupları ("ekran|masaüstü|bundleID").
    @Published var collapsed: Set<String> = []
    /// Haritada gösterilen pencereler. Sürükleme sürerken yenilenmez.
    @Published var windows: [Router.WindowSnapshot] = []

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
    /// Sürükleme sırasında gelen tarama sonucu; sürükleme bitince uygulanır.
    @State private var pendingWindows: [Router.WindowSnapshot]?

    var body: some View {
        VStack(spacing: 0) {
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

            if let draft = ui.pinDraft, mode == screens.mode {
                Divider()
                PinPanel(draft: draft, mode: mode)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            } else if let id = ui.selectedRuleID, let rule = store.rule(id) {
                Divider()
                RulePanel(rule: rule, mode: mode)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }

            Divider()
            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 560, height: 600)
        .background(.regularMaterial)
        .onAppear {
            mode = screens.mode
            ui.windows = router.windows
            syncScreens()
        }
        .onReceive(screens.$screens) { _ in syncScreens() }
        .onReceive(router.$windows) { windows in
            if ui.drag == nil {
                ui.windows = windows
            } else {
                pendingWindows = windows
            }
        }
        .onChange(of: ui.drag == nil) { idle in
            guard idle, let pending = pendingWindows else { return }
            ui.windows = pending
            pendingWindows = nil
        }
        .onChange(of: mode) { _ in
            ui.selectedRuleID = nil
            ui.pinDraft = nil
        }
        .onChange(of: ui.windows) { windows in
            // Taslağın penceresi kapandıysa paneli kapat.
            if let draft = ui.pinDraft, !windows.contains(where: { $0.id == draft.window.id }) {
                ui.pinDraft = nil
            }
        }
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

            let pinned = store.document.rules.filter { $0[mode] != nil }.count
            Text(pinned == 0 ? "pin yok" : "\(pinned) pin")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                router.reapplyAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Pinli pencereleri şimdi yerleştir")
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
                         ? "Bir pencereyi pinleyin ya da başka masaüstüne sürükleyin."
                         : "Pinli pencereler yerinde tutulur; diğerlerine dokunulmaz.")
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

// MARK: - Pin paneli

/// Pin düğmesine basılınca ya da pencere sürüklenince açılır: başlığın
/// hangi parçası bu pencereyi tanımlıyor? Seçim kurala dönüşür; çerçeve
/// pencerenin o anki çerçevesidir.
private struct PinPanel: View {

    let draft: PinDraft
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState

    @State private var segments: [String] = []
    @State private var chosen: Set<Int> = []
    @State private var appWide = false
    /// Varsayılan: pencerenin şu anki çerçevesi; hazır düzenle değiştirilebilir.
    @State private var layout: WindowLayout = .full

    private var window: Router.WindowSnapshot { draft.window }

    private var targetLabel: String {
        let name = store.screens(for: mode).first { $0.id == draft.target.screen }?.name
            ?? draft.target.screen
        return "\(name) · Masaüstü \(draft.target.desktop)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppIcon(bundleID: window.bundleID, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName).font(.callout.weight(.semibold))
                    Text(window.title.isEmpty ? "Adsız pencere" : window.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer()
                Label(targetLabel, systemImage: "pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    ui.pinDraft = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Vazgeç")
            }

            Text(segments.isEmpty
                 ? "Bu pencerenin başlığı yok; uygulamanın bütün pencereleri pinlenir."
                 : "Başlığın hangi parçası bu pencereyi tanımlıyor?")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                pill("Tüm pencereler", systemImage: "macwindow.on.rectangle", isOn: appWide) {
                    appWide.toggle()
                    if appWide { chosen = [] }
                }
                ForEach(segments.indices, id: \.self) { index in
                    pill(segments[index], isOn: chosen.contains(index)) {
                        if chosen.contains(index) {
                            chosen.remove(index)
                        } else {
                            chosen.insert(index)
                            appWide = false
                        }
                    }
                }
            }

            Divider()

            LayoutEditor(layout: $layout)

            HStack {
                Text(appWide
                     ? "Başlığa bakılmaz; \(window.appName) uygulamasının her penceresi uyar."
                     : (matchCount == 1 ? "Şu an 1 pencere uyuyor."
                                        : "Şu an \(matchCount) pencere uyuyor. Dosya adı gibi değişen parçaları seçmeyin."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                Spacer()
                Button("Vazgeç") { ui.pinDraft = nil }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                Button("Pinle", action: pin)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!appWide && chosen.isEmpty)
            }
        }
        .onAppear { reset() }
        .onChange(of: draft.window.id) { _ in reset() }
    }

    private func reset() {
        layout = currentLayout
        segments = Rule.split(title: window.title)
        if segments.isEmpty {
            chosen = []
            appWide = true
        } else {
            // Varsayılan: uygulama adı olmayan son parça (çalışma alanı adı
            // genellikle başlığın sonundadır).
            let candidates = segments.indices.filter {
                segments[$0].caseInsensitiveCompare(window.appName) != .orderedSame
            }
            chosen = Set([candidates.last ?? segments.indices.last].compactMap { $0 })
            appWide = false
        }
    }

    private var tokens: [String] {
        appWide ? [] : chosen.sorted().map { segments[$0] }
    }

    private var matchCount: Int {
        let rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
        return ui.windows.filter {
            rule.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
        }.count
    }

    /// Pencerenin şu anki çerçevesi, bulunduğu ekranın kullanılabilir
    /// alanına göre oranlar. Başka ekrana taşınıyorsa aynı oranlar orada
    /// uygulanır.
    private var currentLayout: WindowLayout {
        let screenID = window.placement?.screen ?? draft.target.screen
        guard let frame = window.frame,
              let screen = screens.screens.first(where: { $0.id == screenID })
        else { return .full }
        let area = Coordinates.axRect(fromCocoa: screen.visibleFrame,
                                      screens: screens.screens)
        return WindowLayout(frame: frame, in: area)
    }

    private func pin() {
        let rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
        let destination = Destination(screen: draft.target.screen,
                                      desktop: draft.target.desktop, layout: layout)
        store.pin(rule, destination: destination, mode: mode)
        ui.pinDraft = nil
    }

    private func pill(_ text: String, systemImage: String? = nil, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(text).lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pin bilgi paneli

/// Bir pin çipine ya da pinli pencere satırına tıklanınca açılır: bilgi,
/// düzen düzenleyici ve "pini kaldır".
private struct RulePanel: View {

    let rule: Rule
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if let destination = rule[mode] {
                LayoutEditor(layout: Binding(
                    // Her zaman depodaki güncel değeri oku; yakalanan
                    // `destination` bir sonraki çizime kadar eski kalır.
                    get: { store.rule(rule.id)?[mode]?.layout ?? destination.layout },
                    set: { layout in
                        var updated = store.rule(rule.id)?[mode] ?? destination
                        updated.layout = layout
                        store.setDestination(updated, for: rule.id, mode: mode)
                    }))
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            AppIcon(bundleID: rule.bundleID, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.appName).font(.callout.weight(.semibold))
                Text(rule.title).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer()

            Text(otherModeText)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                store.unpin(rule.id, mode: mode)
                ui.selectedRuleID = nil
            } label: {
                Label("Pini kaldır", systemImage: "pin.slash")
            }
            .controlSize(.small)

            Button {
                ui.selectedRuleID = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Kapat")
        }
    }

    private var otherModeText: String {
        let other: Mode = mode == .docked ? .undocked : .docked
        return rule[other] == nil ? "\(other.title): pin yok" : "\(other.title): pinli"
    }
}

// MARK: - Düzen düzenleyici

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

    // Kenar boşluğu (%) <-> oran dönüşümleri. Pencere en az %10 kalır.
    // Her ayar tek bir atama ile yazılır; iki ayrı atama arasında
    // binding'in eski değeri okunup diğer kenarı bozuyordu.

    private struct Margins {
        var left: Int, right: Int, top: Int, bottom: Int

        init(_ layout: WindowLayout) {
            left = Int((layout.x * 100).rounded())
            right = 100 - Int(((layout.x + layout.w) * 100).rounded())
            top = Int((layout.y * 100).rounded())
            bottom = 100 - Int(((layout.y + layout.h) * 100).rounded())
        }

        var layout: WindowLayout {
            WindowLayout(
                x: Double(left) / 100,
                y: Double(top) / 100,
                w: Double(100 - left - right) / 100,
                h: Double(100 - top - bottom) / 100)
        }
    }

    private func margin(_ keyPath: WritableKeyPath<Margins, Int>,
                        opposite: KeyPath<Margins, Int>) -> Binding<Int> {
        Binding(
            get: { Margins(layout)[keyPath: keyPath] },
            set: { newValue in
                var margins = Margins(layout)
                margins[keyPath: keyPath] =
                    min(max(newValue, 0), 90 - margins[keyPath: opposite])
                layout = margins.layout
            })
    }

    private var leftBinding: Binding<Int> { margin(\.left, opposite: \.right) }
    private var rightBinding: Binding<Int> { margin(\.right, opposite: \.left) }
    private var topBinding: Binding<Int> { margin(\.top, opposite: \.bottom) }
    private var bottomBinding: Binding<Int> { margin(\.bottom, opposite: \.top) }
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
