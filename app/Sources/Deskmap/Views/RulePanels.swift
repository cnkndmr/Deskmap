import SwiftUI

// MARK: - Ortak başlık satırı

/// Pin panellerinin üst satırı: uygulama simgesi ve adı, alt başlık, sağda
/// panele özel bir etiket, "Pini kaldır" ve kapatma düğmesi (Esc).
struct PinPanelHeader<Trailing: View>: View {

    let bundleID: String
    let appName: String
    let subtitle: String
    let unpin: () -> Void
    let close: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(bundleID: bundleID, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)

            Spacer()

            trailing()

            Button(action: unpin) {
                Label(L("Unpin"), systemImage: "pin.slash")
            }
            .controlSize(.small)

            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help(L("Close (Esc)"))
            .accessibilityLabel(L("Close"))
        }
    }
}

// MARK: - Pin bilgi paneli

/// Bir pin çipine ya da pinli pencere satırına tıklanınca açılır: bilgi,
/// düzen düzenleyici ve "pini kaldır".
struct RulePanel: View {

    let rule: Rule
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var screens: ScreenService

    /// Parça düzenleme taslağı: uyan ilk pencerenin başlık bölümleri ve
    /// seçim. Parçalar kurala aittir, moddan bağımsızdır; bu yüzden diğer
    /// modda da düzenlenebilir.
    @State private var segments: [String] = []
    @State private var chosen: Set<Int> = []
    @State private var appWide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PinPanelHeader(
                bundleID: rule.bundleID, appName: rule.appName, subtitle: rule.title,
                unpin: {
                    store.unpin(rule.id, mode: mode)
                    ui.panel = nil
                },
                close: { ui.panel = nil }
            ) {
                Text(otherModeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            tokenSection

            if let destination = rule[mode] {
                Divider()
                LayoutEditor(layout: Binding(
                    // Her zaman depodaki güncel değeri oku; yakalanan
                    // `destination` bir sonraki çizime kadar eski kalır.
                    get: { store.rule(rule.id)?[mode]?.layout ?? destination.layout },
                    set: { layout in
                        var updated = store.rule(rule.id)?[mode] ?? destination
                        updated.layout = layout
                        store.setDestination(updated, for: rule.id, mode: mode)
                    }))
                SaveCurrentLayoutRow(
                    window: layoutSourceWindow,
                    stored: store.rule(rule.id)?[mode]?.layout ?? destination.layout,
                    // Canlı pencereler yalnızca şu anki modda listelenir; diğer
                    // modun paneli açıksa ölçü alınmaz.
                    isLive: mode == screens.mode
                ) { layout in
                    store.saveLayout(layout, for: rule.id, mode: mode)
                }
            }
        }
    }

    /// Ölçünün okunacağı pencere: panel bir satırdan açıldıysa o satırın
    /// penceresi (hâlâ kurala uyuyorsa), yoksa kurala uyan ilk pencere.
    private var layoutSourceWindow: Router.WindowSnapshot? {
        if let id = ui.panelSourceWindowID,
           let window = matching.first(where: { $0.id == id }) {
            return window
        }
        return matching.first
    }

    private var otherModeText: String {
        let other: Mode = mode == .docked ? .undocked : .docked
        return rule[other] == nil ? L("%@: no pin", other.title) : L("%@: pinned", other.title)
    }

    // MARK: Başlık parçaları

    /// Kurala şu an uyan açık pencereler; ilkinin başlığı seçim kaynağıdır.
    private var matching: [Router.WindowSnapshot] {
        ui.windows.filter { rule.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title) }
    }

    private var sourceTitle: String? { matching.first?.title }

    private var draftTokens: [String] {
        TokenPicker.tokens(segments: segments, chosen: chosen, appWide: appWide)
    }

    private var draftRule: Rule {
        var draft = rule
        draft.tokens = draftTokens
        return draft
    }

    private var draftMatchCount: Int {
        ui.windows.filter {
            draftRule.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
        }.count
    }

    /// Seçim, kuralın mevcut parçalarından (büyük/küçük harf duyarsız) farklı mı?
    private var isChanged: Bool { !draftRule.sameKey(as: rule) }

    private var conflict: Rule? {
        store.document.conflictingRule(ifTokens: draftTokens, for: rule.id)
    }

    private var canApply: Bool {
        isChanged && conflict == nil && (appWide || !chosen.isEmpty)
    }

    @ViewBuilder
    private var tokenSection: some View {
        if let title = sourceTitle {
            VStack(alignment: .leading, spacing: 6) {
                TokenPicker(segments: segments, chosen: $chosen, appWide: $appWide)
                HStack(spacing: 8) {
                    Text(tokenCaption)
                        .font(.caption2)
                        .foregroundStyle(conflict != nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(L("Apply")) {
                        store.setTokens(draftTokens, for: rule.id)
                    }
                    .controlSize(.small)
                    .disabled(!canApply)
                    .help(L("Use the selected parts as this pin's title parts"))
                }
            }
            .onAppear { reset(title) }
            .onChange(of: title) { reset($0) }
            .onChange(of: rule.id) { _ in reset(title) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 6) {
                    if rule.isAppWide {
                        TokenPill(L("All windows"), systemImage: "macwindow.on.rectangle", isOn: true)
                    } else {
                        ForEach(Array(rule.tokens.enumerated()), id: \.offset) { _, token in
                            TokenPill(token, isOn: true)
                        }
                    }
                }
                Text(L("To change the parts, a window matching this pin must be open."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tokenCaption: String {
        if let conflict {
            return L("A pin with these parts already exists: “%@”", conflict.title)
        }
        if appWide {
            return L("The title is ignored; every window of %@ matches.", rule.appName)
        }
        if chosen.isEmpty {
            return L("Select at least one part, or All windows.")
        }
        return draftMatchCount == 1
            ? L("1 window matches right now.")
            : L("%ld windows match right now.", draftMatchCount)
    }

    /// Uyan pencerenin başlığını böler, kuralın mevcut parçalarını işaretler.
    private func reset(_ title: String) {
        segments = Rule.split(title: title)
        appWide = rule.isAppWide
        chosen = appWide ? [] : TokenPicker.preselection(segments: segments, tokens: rule.tokens)
    }
}

// MARK: - Geçici pin paneli

/// Oturum pinli (pencere kimliğine bağlı) satıra tıklanınca açılır:
/// bilgi, düzen düzenleyici ve "pini kaldır".
struct SessionPinPanel: View {

    let window: Router.WindowSnapshot
    let destination: Destination

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PinPanelHeader(
                bundleID: window.bundleID, appName: window.appName,
                subtitle: window.title.isEmpty ? L("Untitled window") : window.title,
                unpin: {
                    router.unpinSession(window.id)
                    ui.panel = nil
                },
                close: { ui.panel = nil }
            ) {
                Label(L("Temporary · window #%ld", Int(window.id)), systemImage: "pin.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                    .help(L("Only this window, for this session. Not saved to the profile."))
            }

            LayoutEditor(layout: Binding(
                get: { router.sessionPins[window.id]?.layout ?? destination.layout },
                set: { layout in
                    var updated = router.sessionPins[window.id] ?? destination
                    updated.layout = layout
                    router.pinSession(window.id, destination: updated)
                }))
            SaveCurrentLayoutRow(
                window: window,
                stored: router.sessionPins[window.id]?.layout ?? destination.layout,
                isLive: true
            ) { layout in
                // Geçici pin: hedef doğrudan güncellenir; geri alma pin hâlâ
                // duruyorsa eski düzene döndürür (sürüklemeyle aynı kalıp).
                let current = router.sessionPins[window.id] ?? destination
                var updated = current
                updated.layout = layout
                router.pinSession(window.id, destination: updated)
                let router = router, id = window.id
                store.recordSessionChange(L("Layout saved")) {
                    if router.sessionPins[id] != nil {
                        router.pinSession(id, destination: current)
                    }
                }
            }
        }
    }
}

// MARK: - Şu anki boyutu kullan

/// Düzen düzenleyicinin altındaki satır: pencerenin gerçek konum ve
/// boyutunu (bulunduğu ekranın kullanılabilir alanına oranla) kayıtlı
/// düzenin yerine yazar. Yalnızca düzen değişir: pin başka ekrana ya da
/// masaüstüne gönderilmez, yeni pin yazılmaz.
struct SaveCurrentLayoutRow: View {

    /// Ölçünün okunacağı pencere; kurala uyan açık pencere yoksa nil.
    let window: Router.WindowSnapshot?
    /// Kayıtlı düzen; ölçü buna eşitse düğme kapalı kalır.
    let stored: WindowLayout
    /// Panel şu anki modu gösteriyor mu (canlı pencereler yalnızca o modda).
    let isLive: Bool
    let save: (WindowLayout) -> Void

    @EnvironmentObject private var screens: ScreenService

    /// Pencerenin şu anki düzeni; okunamıyorsa nil.
    private var current: WindowLayout? {
        guard isLive, let window else { return nil }
        return window.currentLayout(screens: screens.screens)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            Button {
                if let current { save(current) }
            } label: {
                Label(L("Use current size and position"),
                      systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .controlSize(.small)
            .disabled(current == nil || current == stored)
            .help(L("Save the window's current position and size as this pin's layout. Screen and desktop stay the same."))
        }
    }

    private var caption: String {
        guard isLive else { return L("Switch to this mode to read the window's size.") }
        guard let window else { return L("Open a matching window to read its size.") }
        guard let current else { return L("The window's size can't be read right now.") }
        if current == stored { return L("The saved layout already matches the window.") }
        return L("Window now: %@", current.label)
    }
}
