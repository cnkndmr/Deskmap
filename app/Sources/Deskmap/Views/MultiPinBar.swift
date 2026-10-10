import SwiftUI

/// ⌘-tıklamayla seçilen pencereler için alt çubuk: hepsini bulundukları
/// masaüstüne, şu anki boyut ve konumlarıyla pinler (tek adımda geri alınır).
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

        static func == (a: Plan, b: Plan) -> Bool {
            a.rules.map(\.rule.tokens) == b.rules.map(\.rule.tokens)
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
    static func plan(selected ids: Set<CGWindowID>, windows: [Router.WindowSnapshot],
                     history: WindowIdentity.Observations = .init(),
                     layout: (Router.WindowSnapshot) -> WindowLayout) -> Plan {
        var plan = Plan()
        let selected = windows.filter { ids.contains($0.id) }
        for window in selected {
            guard let placement = window.placement, window.fullscreen == nil else { continue }
            let destination = Destination(screen: placement.screen, desktop: placement.desktop,
                                          layout: layout(window))
            // Seçimdeki başka bir pencere aynı kuralı başka yere istemişse çakışır.
            let others = windows.filter { !ids.contains($0.id) }
            if let rule = WindowIdentity.resolve(window, others: others, history: history)
                .rule(appName: window.appName, bundleID: window.bundleID),
               !plan.rules.contains(where: { $0.rule.sameKey(as: rule) }) {
                plan.rules.append((rule, destination))
            } else {
                plan.sessions.append((window.id, destination))
            }
        }
        return plan
    }

    private var plan: Plan {
        Self.plan(selected: ui.selection, windows: ui.windows, history: router.identity) {
            $0.currentLayout(screens: screens.screens) ?? .full
        }
    }

    var body: some View {
        let plan = plan
        let count = plan.rules.count + plan.sessions.count
        VStack(alignment: .leading, spacing: 8) {
            Label(L("%ld windows selected", ui.windows.filter { ui.selection.contains($0.id) }.count),
                  systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
            Text(plan.sessions.isEmpty
                 ? L("Each is pinned to its current desktop with its current size and position.")
                 : L("%ld of them only until the window closes: their titles also match other open windows.",
                     plan.sessions.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("⌘-click windows to add or remove them."))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                pinAll(plan)
            } label: {
                Label(L("Pin %ld where they are", count), systemImage: "pin.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0)
            .keyboardShortcut(.defaultAction)
            Button(L("Clear")) { ui.selection = [] }
                .buttonStyle(.link)
        }
        .onExitCommand { ui.selection = [] }
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
        store.pinMany(plan.rules, mode: screens.mode)
        for item in plan.sessions {
            router.pinSession(item.window, destination: item.destination)
        }
        return plan.rules.count + plan.sessions.count
    }

    private func pinAll(_ plan: Plan) {
        store.pinMany(plan.rules, mode: mode)
        for item in plan.sessions {
            router.pinSession(item.window, destination: item.destination)
        }
        ui.selection = []
    }
}
