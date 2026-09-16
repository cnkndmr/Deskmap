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
            }
        }
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
        }
    }
}
