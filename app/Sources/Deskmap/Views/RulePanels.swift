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
    @EnvironmentObject private var router: Router

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
                    }),
                    screen: store.screens(for: mode).first { $0.id == destination.screen })
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

            if mode == screens.mode, !freeMoveTargets.isEmpty {
                Divider()
                FreeMoveRow(windowIDs: freeMoveTargets)
            }
        }
    }

    /// Serbest hareket izninin verileceği pencereler: yalnız bu kuralın
    /// gerçekten yönettiği pencereler (oturum pinli ya da daha özgül bir
    /// kurala düşen pencere değil). Panel bir satırdan açıldıysa yalnız o
    /// pencere; o pencere kapandıysa hiçbiri (kapsam sessizce genişlemesin).
    private var freeMoveTargets: [CGWindowID] {
        guard rule[mode] != nil else { return [] }
        let governed = ui.windows.filter {
            Routing.select(rules: store.document.rules, sessionPins: router.sessionPins,
                           mode: mode, windowID: $0.id, bundleID: $0.bundleID,
                           appName: $0.appName, title: $0.title)?.rule?.id == rule.id
        }.map(\.id)
        if let id = ui.panelSourceWindowID {
            return governed.contains(id) ? [id] : []
        }
        return governed
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
    @EnvironmentObject private var screens: ScreenService

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
                }),
                screen: store.screens(for: screens.mode).first { $0.id == destination.screen })
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

            Divider()
            FreeMoveRow(windowIDs: [window.id])
        }
    }
}

// MARK: - Serbest hareket

/// Pin panellerinin altındaki satır: pencereye belirli bir süre serbest
/// hareket izni verir. Süre boyunca Deskmap pencereyi yerine döndürmez;
/// süre bitince pin yeniden uygulanır.
struct FreeMoveRow: View {

    let windowIDs: [CGWindowID]

    @EnvironmentObject private var router: Router

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let free = windowIDs.filter { (router.freeMoves[$0] ?? .distantPast) > context.date }
            if let until = free.compactMap({ router.freeMoves[$0] }).max() {
                active(remaining: until.timeIntervalSince(context.date), free: free)
            } else {
                idle
            }
        }
    }

    /// Süre menüsü: yalnız verilen pencerelere izin verir.
    private func durationMenu(for ids: [CGWindowID]) -> some View {
        Menu {
            ForEach(Router.freeMoveDurations, id: \.self) { duration in
                Button(Self.label(duration)) {
                    router.allowFreeMove(ids, for: duration)
                }
            }
        } label: {
            Label(L("Free move"), systemImage: "timer")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .controlSize(.small)
        .help(L("Let this window be moved freely for a while"))
    }

    private var idle: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(.secondary)
            Text(L("Move freely for a while: Deskmap will not put the window back until the time is up."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            durationMenu(for: windowIDs)
        }
    }

    /// `free`: şu an serbest olan hedefler. Bir kısmı serbestse sayı
    /// gösterilir ve kalanlar için süre menüsü açık kalır.
    private func active(remaining: TimeInterval, free: [CGWindowID]) -> some View {
        let rest = windowIDs.filter { !free.contains($0) }
        return HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(Color.teal)
            Text(L("Free to move · %@ left", Router.freeMoveRemaining(remaining)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.teal)
            if rest.isEmpty {
                Text(L("Then it goes back to its pin."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(L("%ld of %ld windows", free.count, windowIDs.count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !rest.isEmpty {
                durationMenu(for: rest)
            }
            Button(L("+5 min")) {
                router.extendFreeMove(free, by: 5 * 60)
            }
            .controlSize(.small)
            Button(L("End now")) {
                router.endFreeMove(free)
            }
            .controlSize(.small)
            .help(L("End free movement; the window goes back to its pin"))
        }
    }

    static func label(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return minutes == 1 ? L("1 minute") : L("%ld minutes", minutes)
    }
}

/// Satırda serbest hareket göstergesi: saat simgesi ve kalan süre.
struct FreeMoveBadge: View {

    let until: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = until.timeIntervalSince(context.date)
            if left > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                    Text(Router.freeMoveRemaining(left))
                        .monospacedDigit()
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.teal)
                .help(L("Free to move · %@ left", Router.freeMoveRemaining(left)))
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
        guard window != nil else { return L("Open a matching window to read its size.") }
        guard let current else { return L("The window's size can't be read right now.") }
        if current == stored { return L("The saved layout already matches the window.") }
        return L("Window now: %@", current.label)
    }
}
