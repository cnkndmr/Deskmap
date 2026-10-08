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
                && a.rules.map(\.destination) == b.rules.map(\.destination)
                && a.sessions.map(\.window) == b.sessions.map(\.window)
                && a.sessions.map(\.destination) == b.sessions.map(\.destination)
        }
    }

    /// Seçilen pencerelerin pin planı (saf). Kural, tek pin düğmesinin
    /// varsayılan başlık parçasıyla yazılır; bu parça seçilmemiş başka açık
    /// pencereye de uyuyorsa (onları da sürüklerdi) bütün başlık denenir, o
    /// da uyuyorsa ya da seçimdeki başka pencere aynı kuralı başka yere
    /// istiyorsa yalnız bu pencereye oturum pini. Yeri bilinmeyen ya da tam
    /// ekran pencere atlanır.
    static func plan(selected ids: Set<CGWindowID>, windows: [Router.WindowSnapshot],
                     layout: (Router.WindowSnapshot) -> WindowLayout) -> Plan {
        var plan = Plan()
        let selected = windows.filter { ids.contains($0.id) }
        for window in selected {
            guard let placement = window.placement, window.fullscreen == nil else { continue }
            let destination = Destination(screen: placement.screen, desktop: placement.desktop,
                                          layout: layout(window))
            func clashes(_ tokens: [String]) -> Bool {
                let rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
                if windows.contains(where: {
                    !ids.contains($0.id)
                        && rule.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
                }) { return true }
                return plan.rules.contains { $0.rule.sameKey(as: rule) }
            }
            let preferred = PinPanel.defaultTokens(title: window.title, appName: window.appName)
            let full = Rule.split(title: window.title)
            let tokens = [preferred, full].first { !$0.isEmpty && !clashes($0) }
            if let tokens {
                plan.rules.append((Rule(appName: window.appName, bundleID: window.bundleID,
                                        tokens: tokens), destination))
            } else {
                plan.sessions.append((window.id, destination))
            }
        }
        return plan
    }

    private var plan: Plan {
        Self.plan(selected: ui.selection, windows: ui.windows) {
            $0.currentLayout(screens: screens.screens) ?? .full
        }
    }

    var body: some View {
        let plan = plan
        let count = plan.rules.count + plan.sessions.count
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("%ld windows selected", ui.windows.filter { ui.selection.contains($0.id) }.count))
                    .font(.callout.weight(.semibold))
                Text(plan.sessions.isEmpty
                     ? L("Each is pinned to its current desktop with its current size and position.")
                     : L("%ld of them only until the window closes: their titles also match other open windows.",
                         plan.sessions.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("⌘-click windows to add or remove them."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(L("Clear")) { ui.selection = [] }
            Button {
                pinAll(plan)
            } label: {
                Label(L("Pin %ld where they are", count), systemImage: "pin.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .onExitCommand { ui.selection = [] }
    }

    private func pinAll(_ plan: Plan) {
        store.pinMany(plan.rules, mode: mode)
        for item in plan.sessions {
            router.pinSession(item.window, destination: item.destination)
        }
        ui.selection = []
    }
}
