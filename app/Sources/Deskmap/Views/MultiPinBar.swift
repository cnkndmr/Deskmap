import SwiftUI

/// ⌘-tıklamayla seçilen pencereler için alt çubuk: hepsini bulundukları
/// masaüstüne, şu anki boyut ve konumlarıyla pinler (tek adımda geri alınır).
/// Seçimde pinli öğe de (⌘-tıklanan pin çipleri, kapalılar dahil) varsa
/// hepsi bir pin grubunda toplanabilir ("Grup olarak pinle").
struct MultiPinBar: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState

    /// Bir pencerenin pini: kalıcı kural ya da (başlığı başka açık
    /// pencerelere de uyduğu için) yalnız bu pencereye oturum pini.
    struct Plan: Equatable {
        var rules: [(rule: Rule, destination: Destination)] = []
        var sessions: [(window: CGWindowID, destination: Destination)] = []
        /// Seçimdeki zaten pinli öğelerin kural kimlikleri (yalnız
        /// `existingRules` verilince): seçili çipler, kalıcı kuralı olan
        /// pencereler, taslağı var olan kurala (`sameKey`) düşen pencereler.
        /// Gruplamada yerleri değişmez (K12); `rules` yalnız gerçekten yeniler.
        var existing: [String] = []
        /// Gruplamada atlanan, oturum pini (geçici sabitleme) olan seçili
        /// pencereler (K8: gruba girmez, kutuda görünmezdi).
        var temporary: [CGWindowID] = []
        /// Gruplamada atlanan, bu planda yeri olmayan seçili çipler (öbür
        /// planın tepsisi): kutu çizmezlerdi; çubuk nedenini söyler.
        var otherPlan: [String] = []

        static func == (a: Plan, b: Plan) -> Bool {
            a.existing == b.existing && a.temporary == b.temporary && a.otherPlan == b.otherPlan
                && a.rules.map(\.rule.tokens) == b.rules.map(\.rule.tokens)
                && a.rules.map(\.rule.path) == b.rules.map(\.rule.path)
                && a.rules.map(\.destination) == b.rules.map(\.destination)
                && a.sessions.map(\.window) == b.sessions.map(\.window)
                && a.sessions.map(\.destination) == b.sessions.map(\.destination)
        }
    }

    /// Seçilen pencerelerin pin planı (saf). Kural, pencerenin kararlı
    /// kimliğiyle (`WindowIdentity`) yazılır; anahtar seçilmemiş başka açık
    /// pencereye de uyuyorsa daraltılır (belge yolu ve başlık geçmişi
    /// `WindowIdentity.resolve` ile), kararlı anahtar yoksa ya da seçimdeki
    /// başka pencere aynı kuralı başka yere istiyorsa yalnız bu pencereye
    /// oturum pini. Yeri bilinmeyen ya da tam ekran pencere atlanır.
    ///
    /// Gruplama planı (`existingRules` verilince): kalıcı kuralı olan
    /// (`ruleFor`, oturum pini kazanırsa nil) ya da taslağı bu modda yeri
    /// olan bir kurala düşen pencere ve bu modda yeri olan seçili çipler
    /// (`selectedRules`) `existing`'e gider, yeniden pinlenmez. Taslağı
    /// yalnız öbür planda yeri olan kurala düşen pencere `rules`'a gider:
    /// `Document.pin` o kurala bu planın yerini ekler (yazılı yer yok, K12
    /// bozulmaz). Oturum pini olan pencere (`sessionPinned`) `temporary`'ye
    /// gider, gruba girmez (K8). Kazanan kural uygulamanın bütün
    /// pencerelerini tutuyorsa (`isAppWide`) pencere pinsiz sayılır ve kendi
    /// başlık kuralını alır: yoksa seçilmeyen pencereler de gruba girerdi.
    /// Bu planda yeri olmayan seçili çipler `otherPlan`'a gider. `mode` nil:
    /// yer denetimi yok.
    static func plan(selected ids: Set<CGWindowID>, windows: [Router.WindowSnapshot],
                     history: WindowIdentity.Observations = .init(),
                     existingRules: [Rule]? = nil, selectedRules: Set<String> = [],
                     mode: Mode? = nil, sessionPinned: Set<CGWindowID> = [],
                     ruleFor: ((Router.WindowSnapshot) -> Rule?)? = nil,
                     layout: (Router.WindowSnapshot) -> WindowLayout) -> Plan {
        var plan = Plan()
        func keep(_ id: String) { if !plan.existing.contains(id) { plan.existing.append(id) } }
        func hasPlace(_ rule: Rule) -> Bool { mode.map { rule[$0] != nil } ?? true }
        let known = Set(existingRules?.map(\.id) ?? [])
        let selected = windows.filter { ids.contains($0.id) }
        for window in selected {
            guard let placement = window.placement, window.fullscreen == nil else { continue }
            if existingRules != nil, sessionPinned.contains(window.id) {
                plan.temporary.append(window.id)
                continue
            }
            if existingRules != nil, let rule = ruleFor?(window), known.contains(rule.id),
               !rule.isAppWide {
                keep(rule.id)
                continue
            }
            let destination = Destination(screen: placement.screen, desktop: placement.desktop,
                                          layout: layout(window))
            // Seçimdeki başka bir pencere aynı kuralı başka yere istemişse çakışır.
            let others = windows.filter { !ids.contains($0.id) }
            if let rule = WindowIdentity.resolve(window, others: others, history: history)
                .rule(appName: window.appName, bundleID: window.bundleID),
               !plan.rules.contains(where: { $0.rule.sameKey(as: rule) }) {
                if let match = existingRules?.first(where: { $0.sameKey(as: rule) }), hasPlace(match) {
                    keep(match.id)
                } else {
                    plan.rules.append((rule, destination))
                }
            } else {
                plan.sessions.append((window.id, destination))
            }
        }
        // Öbür planın tepsi çipi bu planda kutu çizmezdi: yalnız yeri olanlar.
        for rule in existingRules ?? [] where selectedRules.contains(rule.id) {
            if hasPlace(rule) { keep(rule.id) } else { plan.otherPlan.append(rule.id) }
        }
        return plan
    }

    private var plan: Plan {
        Self.plan(selected: ui.selection, windows: ui.windows, history: router.identity) {
            $0.currentLayout(screens: screens.screens) ?? .full
        }
    }

    /// Gruplama planı: seçili pencereler ve çipler, zaten pinliler ayrı.
    private var groupPlan: Plan {
        let rules = store.document.rules, sessions = router.sessionPins, mode = mode
        let context = router.context(for: mode)
        return Self.plan(selected: ui.selection, windows: ui.windows, history: router.identity,
                         existingRules: rules, selectedRules: ui.selectedRules,
                         mode: mode, sessionPinned: Set(sessions.keys),
                         ruleFor: { PinGroupLayout.winningRule($0, rules: rules, sessionPins: sessions,
                                                               mode: mode, context: context) }) {
            $0.currentLayout(screens: screens.screens) ?? .full
        }
    }

    var body: some View {
        let plan = plan
        let grouping = groupPlan
        let count = plan.rules.count + plan.sessions.count
        let selected = ui.windows.filter { ui.selection.contains($0.id) }.count
        let pins = ui.selectedRules.filter { store.rule($0) != nil }.count
        let groupable = grouping.rules.count + grouping.existing.count
        VStack(alignment: .leading, spacing: 8) {
            if selected > 0 || pins == 0 {
                Label(selected == 1 ? L("1 window selected") : L("%ld windows selected", selected),
                      systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
            }
            if pins > 0 {
                Label(pins == 1 ? L("1 pin selected") : L("%ld pins selected", pins),
                      systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
            }
            if selected > 0 {
                Text(plan.sessions.isEmpty
                 ? L("Each is pinned to its current desktop with its current size and position.")
                 : plan.sessions.count == 1
                 ? L("1 window is pinned only until it closes: its title also matches other open windows.")
                 : L("%ld windows are pinned only until they close: their titles also match other open windows.",
                     plan.sessions.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("⌘-click windows or pins to add or remove them."))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if selected > 0 {
                Button {
                    pinAll(plan)
                } label: {
                    Label(count == 1 ? L("Pin it where it is") : L("Pin %ld where they are", count),
                          systemImage: "pin.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(count == 0)
                // Yalın Return arama alanında da hepsini sabitlerdi.
                .keyboardShortcut(.return, modifiers: .command)
                .help(L("Pin (⌘Return)"))
            }
            if groupable >= 1 {
                Button {
                    pinAsGroup(grouping)
                } label: {
                    Label(!grouping.rules.isEmpty ? L("Pin as group")
                          : grouping.existing.count == 1 ? L("Group 1 pin")
                          : L("Group %ld pins", grouping.existing.count),
                          systemImage: "square.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help(L("Collect the selection in a new pin group; pins that already exist keep their places"))
                if !grouping.sessions.isEmpty || !grouping.temporary.isEmpty {
                    Text(L("Temporary pins are not grouped"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Öbür planın çipi seçilebilir ama burada gruplanamaz; yalnız
            // "Temizle" kalırsa neden boş olduğu görünsün.
            if !grouping.otherPlan.isEmpty {
                Text(grouping.otherPlan.count == 1
                     ? L("1 selected pin belongs to the other plan and is not grouped here")
                     : L("%ld selected pins belong to the other plan and are not grouped here",
                         grouping.otherPlan.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Esc kısayolu odak gerektirmez (onExitCommand gerektirirdi).
            Button(L("Clear")) { ui.clearSelection() }
                .buttonStyle(.link)
                .keyboardShortcut(ui.cancelShortcut)
                .help(L("Clear (Esc)"))
        }
    }

    /// Verilen pencereleri olduğu yere sabitler (toplu çubukla aynı plan):
    /// kararlı anahtarı olan kalıcı kural, olmayan geçici sabitleme olur.
    /// Kaç pencere sabitlendiğini döndürür.
    @discardableResult
    static func pinWhereTheyAre(_ ids: Set<CGWindowID>, store: Store, router: Router,
                                screens: ScreenService) -> Int {
        let plan = plan(selected: ids, windows: router.windows, history: router.identity) {
            $0.currentLayout(screens: screens.screens) ?? .full
        }
        apply(plan, store: store, router: router, mode: screens.mode)
        return plan.rules.count + plan.sessions.count
    }

    private func pinAll(_ plan: Plan) {
        Self.apply(plan, store: store, router: router, mode: mode)
        ui.clearSelection()
    }

    /// "Grup olarak pinle": yeni pencereler pinlenir, zaten pinliler yerinde
    /// kalır, hepsi yeni grupta (tek geri alma adımı). Oturum pinleri her
    /// zamanki gibi pinlenir, gruba girmez (K8). Yeni grubun adı hemen
    /// düzenlemeye açılır.
    private func pinAsGroup(_ plan: Plan) {
        let undoSessions = Self.sessionUndo(plan, router: router)
        let id = store.pinAsGroup(new: plan.rules, existing: plan.existing, mode: mode,
                                  companion: undoSessions)
        for item in plan.sessions {
            router.pinSession(item.window, destination: item.destination)
        }
        if let id { ui.requestPinGroupRename(id) }
        ui.clearSelection()
    }

    /// Oturum pinlerini önceki hâline döndüren kapanış (yoksa nil).
    private static func sessionUndo(_ plan: Plan, router: Router) -> (() -> Void)? {
        let previous = plan.sessions.map { ($0.window, router.sessionPins[$0.window]) }
        return previous.isEmpty ? nil : { [weak router] in
            for (id, old) in previous {
                if let old { router?.pinSession(id, destination: old) } else { router?.unpinSession(id) }
            }
        }
    }

    /// Planı uygular; tek "Geri al" kalıcı kuralları da oturum pinlerini de
    /// (önceki oturum pini varsa ona) geri getirir.
    private static func apply(_ plan: Plan, store: Store, router: Router, mode: Mode) {
        let undoSessions = sessionUndo(plan, router: router)
        if !plan.rules.isEmpty {
            store.pinMany(plan.rules, mode: mode, companion: undoSessions)
        } else if let undoSessions {
            store.recordSessionChange(L("Windows pinned"), undo: undoSessions)
        }
        for item in plan.sessions {
            router.pinSession(item.window, destination: item.destination)
        }
    }
}
