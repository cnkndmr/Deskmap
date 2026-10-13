import SwiftUI

// MARK: - Ortak başlık satırı

/// Ayrıntı panellerinin üst satırı: uygulama simgesi ve adı, alt başlık,
/// sağda panele özel bir etiket ve kapatma düğmesi (Esc).
struct PinPanelHeader<Trailing: View>: View {

    let bundleID: String
    let appName: String
    let subtitle: String
    let close: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @EnvironmentObject private var ui: UIState

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AppIcon(bundleID: bundleID, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(appName).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                trailing()
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(ui.cancelShortcut)
            .help(L("Close (Esc)"))
            .accessibilityLabel(L("Close"))
        }
    }
}

/// Panellerin en altındaki "Sabitlemeyi kaldır" düğmesi.
struct UnpinButton: View {
    var title = L("Unpin")
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "pin.slash")
        }
        .controlSize(.small)
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
            PinPanelHeader(bundleID: rule.bundleID, appName: rule.appName, subtitle: rule.title,
                           close: { ui.panel = nil }) {
                Text(otherModeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let destination = rule[mode] {
                RuleSentence(
                    appName: rule.appName, matchText: matchText,
                    destination: store.rule(rule.id)?[mode] ?? destination, mode: mode,
                    matchMenu: { matchItems },
                    setDestination: { store.setDestination($0, for: rule.id, mode: mode) },
                    showAdvanced: { ui.showAdvanced = true })
                DestinationPickers(
                    destination: store.rule(rule.id)?[mode] ?? destination, mode: mode,
                    setDestination: { store.setDestination($0, for: rule.id, mode: mode) })
                BasicLayoutRow(layout: layoutBinding(destination))
            } else {
                Text(L("Drag onto a desktop to give it a place in this plan."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if mode == screens.mode, !freeMoveTargets.isEmpty {
                FreeMoveRow(windowIDs: freeMoveTargets)
            }

            Divider()
            AdvancedToggle(summary: L("title parts, every layout, margins"))
            if ui.showAdvanced {
                tokenSection
                if let destination = rule[mode] {
                    LayoutEditor(layout: layoutBinding(destination),
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
            }

            if let target = Self.unpinMode(for: rule, viewing: mode) {
                Divider()
                UnpinButton(title: target == mode ? L("Unpin")
                                                  : L("Unpin in the %@ plan", target.title)) {
                    store.unpin(rule.id, mode: target)
                    ui.panel = nil
                }
            }

            if let why = whyHere {
                WhyHereBox(reason: why.reason, note: why.note)
            }
        }
    }

    /// "Neden burada?" kutusu: bu planda hedefi varsa kural ve hedefi; canlı
    /// planda penceresi daha özgül bir kurala (ya da geçici pine) düşüyorsa
    /// bunu söyler, öbür planda ne zaman uygulanacağını.
    private var whyHere: (reason: String, note: String)? {
        guard let destination = store.rule(rule.id)?[mode] ?? rule[mode],
              let reason = Routing.reason(
                for: Routing.Match(destination: destination, ruleID: rule.id, rule: rule),
                screenName: store.screens(for: mode).first { $0.id == destination.screen }?.name)
        else { return nil }
        guard mode == screens.mode else {
            return (WhyHereBox.sentence(reason),
                    L("This takes effect when the %@ plan is active; nothing moves now.", mode.title))
        }
        let winners = matching.compactMap {
            Routing.select(rules: store.document.rules, sessionPins: router.sessionPins,
                           mode: mode, windowID: $0.id, bundleID: $0.bundleID,
                           appName: $0.appName, title: $0.title, document: $0.document)?.ruleID
        }
        if let winner = winners.first, !winners.contains(rule.id) {
            let name = winner == Routing.sessionRuleID
                ? L("a temporary pin")
                : L("the “%@” pin", store.rule(winner)?.title ?? "")
            return (WhyHereBox.sentence(reason),
                    L("This window is matched first by %@; this pin does not take effect.", name))
        }
        return (WhyHereBox.sentence(reason),
                L("Deskmap puts matching windows back here whenever they open or are moved somewhere else by hand."))
    }

    /// "Sabitlemeyi kaldır"ın etki ettiği plan (saf): bu planda hedef varsa
    /// bu plan; yoksa (çip "yalnız diğer planda sabit" kutusundan açıldı)
    /// pinin durduğu diğer plan. Eskiden düğme hep bu planı hedefliyordu ve
    /// o durumda hiçbir şey yapmıyordu. Hiç hedef yoksa nil (düğme gizli).
    static func unpinMode(for rule: Rule, viewing mode: Mode) -> Mode? {
        if rule[mode] != nil { return mode }
        return Mode.allCases.first { $0 != mode && rule[$0] != nil }
    }

    /// Her zaman depodaki güncel değeri okur; yakalanan `destination` bir
    /// sonraki çizime kadar eski kalır.
    private func layoutBinding(_ destination: Destination) -> Binding<WindowLayout> {
        Binding(
            get: { store.rule(rule.id)?[mode]?.layout ?? destination.layout },
            set: { layout in
                var updated = store.rule(rule.id)?[mode] ?? destination
                updated.layout = layout
                store.setDestination(updated, for: rule.id, mode: mode)
            })
    }

    /// Cümledeki eşleşme parçası.
    private var matchText: String {
        if let path = rule.path {
            return L("the file %@", (path as NSString).lastPathComponent)
        }
        if rule.isAppWide { return L("all windows") }
        return L("windows with “%@” in the title", rule.tokens.joined(separator: " + "))
    }

    /// Eşleşme menüsü: bütün pencereler ya da başlık parçaları (gelişmiş).
    @ViewBuilder private var matchItems: some View {
        if rule.path != nil {
            Text(matchText)
        } else {
            MenuCheck(L("All windows of %@", rule.appName), checked: rule.isAppWide) {
                store.setTokens([], for: rule.id)
            }
            .disabled(rule.isAppWide || store.document.conflictingRule(ifTokens: [], for: rule.id) != nil)
            if !rule.isAppWide {
                MenuCheck(matchText, checked: true)
            }
            Divider()
            Button(L("Choose title parts…")) { ui.showAdvanced = true }
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
                           appName: $0.appName, title: $0.title, document: $0.document)?.rule?.id == rule.id
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

    /// Kurala şu an uyan açık pencereler. Başlık kaynağı `layoutSourceWindow`:
    /// tıklanan satırın penceresi, yoksa ilk uyan pencere.
    private var matching: [Router.WindowSnapshot] {
        ui.windows.filter { rule.matches($0) }
    }

    private var sourceTitle: String? { layoutSourceWindow?.title }

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
            draftRule.matches($0)
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
        if let path = rule.path {
            // Belge yoluyla pin: başlık parçası yok, dosya gösterilir.
            VStack(alignment: .leading, spacing: 6) {
                TokenPill((path as NSString).lastPathComponent, systemImage: "doc", isOn: true)
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
        } else if let title = sourceTitle {
            VStack(alignment: .leading, spacing: 6) {
                TokenPicker(segments: segments, chosen: $chosen, appWide: $appWide)
                // Açıklama sarar: çakışmada sondaki sabitleme adı kesilmesin.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(tokenCaption)
                        .font(.caption2)
                        .foregroundStyle(conflict != nil ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(tokenCaption)
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

    private var current: Destination { router.sessionPins[window.id] ?? destination }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PinPanelHeader(
                bundleID: window.bundleID, appName: window.appName,
                subtitle: window.title.isEmpty ? L("Untitled window") : window.title,
                close: { ui.panel = nil }
            ) {
                Label(L("Temporary · window #%ld", Int(window.id)), systemImage: "pin.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                    .help(L("Only this window, for this session. Not saved to the profile."))
            }

            RuleSentence(
                appName: window.appName, matchText: L("only this window, this session"),
                destination: current, mode: screens.mode,
                matchMenu: { EmptyView() },
                setDestination: { router.pinSession(window.id, destination: $0) },
                showAdvanced: { ui.showAdvanced = true })
            DestinationPickers(destination: current, mode: screens.mode,
                               setDestination: { router.pinSession(window.id, destination: $0) })
            BasicLayoutRow(layout: layoutBinding)
            FreeMoveRow(windowIDs: [window.id])

            Divider()
            AdvancedToggle(summary: L("every layout, margins, fixed size"))
            if ui.showAdvanced {
                LayoutEditor(layout: layoutBinding,
                             screen: store.document.screens.first { $0.id == destination.screen }
                                ?? store.screens(for: .docked).first { $0.id == destination.screen })
                SaveCurrentLayoutRow(
                    window: window,
                    stored: current.layout,
                    isLive: true
                ) { layout in
                    // Geçici pin: hedef doğrudan güncellenir; geri alma pin hâlâ
                    // duruyorsa eski düzene döndürür (sürüklemeyle aynı kalıp).
                    let before = current
                    var updated = before
                    updated.layout = layout
                    router.pinSession(window.id, destination: updated)
                    let router = router, id = window.id
                    store.recordSessionChange(L("Layout saved")) {
                        if router.sessionPins[id] != nil {
                            router.pinSession(id, destination: before)
                        }
                    }
                }
            }

            Divider()
            UnpinButton {
                router.unpinSession(window.id)
                ui.panel = nil
            }

            if let reason = Routing.reason(
                for: Routing.Match(destination: current, ruleID: Routing.sessionRuleID, rule: nil),
                screenName: store.screens(for: screens.mode).first { $0.id == current.screen }?.name) {
                WhyHereBox(reason: WhyHereBox.sentence(reason),
                           note: L("Only this window, for this session. Not saved to the profile."))
            }
        }
    }

    private var layoutBinding: Binding<WindowLayout> {
        Binding(
            get: { router.sessionPins[window.id]?.layout ?? destination.layout },
            set: { layout in
                var updated = router.sessionPins[window.id] ?? destination
                updated.layout = layout
                router.pinSession(window.id, destination: updated)
            })
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
            if !free.isEmpty {
                active(now: context.date, free: free)
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
    private func active(now: Date, free: [CGWindowID]) -> some View {
        let rest = windowIDs.filter { !free.contains($0) }
        let text = Router.freeMoveStatus(free.compactMap { router.freeMoves[$0] }, now: now)
        let untilLock = text.timedRemaining == nil
        // İki satır: geri sayım ve açıklama üstte (sarmadan), düğmeler altta.
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(Color.teal)
                Text(text.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.teal)
                    .fixedSize()
                Text(rest.isEmpty ? L("Then it goes back to its pin.")
                                  : L("%ld of %ld windows", free.count, windowIDs.count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                if !rest.isEmpty {
                    durationMenu(for: rest)
                }
                if !untilLock {
                    Button(L("+5 min")) {
                        router.extendFreeMove(free, by: 5 * 60)
                    }
                    .controlSize(.small)
                }
                Button(L("End now")) {
                    router.endFreeMove(free)
                }
                .controlSize(.small)
                .help(L("End free movement; the window goes back to its pin"))
            }
        }
    }

    static func label(_ duration: TimeInterval) -> String {
        if duration.isInfinite { return L("Until the screen locks") }
        if duration > 3600 { return L("%ld hours", Int(duration / 3600)) }
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
            if Router.isUntilLock(until) {
                Image(systemName: "lock.open")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.teal)
                    .help(L("Free to move · until the screen locks"))
            } else if left > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                    Text(Router.freeMoveRemaining(left))
                        .monospacedDigit()
                }
                .fixedSize()
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

    /// Pencerenin şu anki düzeni, kaydın türünde (sabit boyutlu kayıtta pt);
    /// okunamıyorsa nil.
    private var current: WindowLayout? {
        guard isLive, let window else { return nil }
        return window.currentLayout(like: stored, screens: screens.screens)
    }

    /// Açıklama üstte sarar, düğme altta sağda: yan yana açıklamaya yer kalmıyordu.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
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
    }

    private var caption: String {
        guard isLive else { return L("Switch to this plan to read the window's size.") }
        guard window != nil else { return L("Open a matching window to read its size.") }
        guard let current else { return L("The window's size can't be read right now.") }
        if current == stored { return L("The saved layout already matches the window.") }
        if current.fixed != nil {
            return L("Window now: %@ (the anchor sets the position)", current.label)
        }
        return L("Window now: %@", current.label)
    }
}
