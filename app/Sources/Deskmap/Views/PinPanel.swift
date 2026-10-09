import SwiftUI

/// Pin düğmesine basılınca ya da pencere sürüklenince açılır. İki seçenek:
/// yalnız bu pencere (kararlı anahtarla kalıcı kural: belge yolu ya da
/// başlığın değişmeyen parçası; anahtar yoksa bu seçenek sunulmaz) ya da
/// uygulamanın bütün pencereleri. Çerçeve pencerenin o
/// anki çerçevesidir.
struct PinPanel: View {

    let draft: PinDraft
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    /// Kapsam: yalnız bu pencere ya da uygulamanın bütün pencereleri.
    enum Scope: CaseIterable, Identifiable {
        case window, app
        var id: Self { self }
    }

    @State private var scope: Scope = .window
    /// Varsayılan: pencerenin şu anki çerçevesi; hazır düzenle değiştirilebilir.
    @State private var layout: WindowLayout = .full
    /// Pencereden okunan son varsayılan düzen. `layout` hâlâ buna eşitse
    /// kullanıcı düzeni değiştirmemiştir; pencerenin taze ölçümü gelince
    /// (taşındı, boyutu değişti) varsayılan ona uyar.
    @State private var measuredLayout: WindowLayout?

    private var window: Router.WindowSnapshot { draft.window }

    private var targetLabel: String {
        let name = store.screens(for: mode).first { $0.id == draft.target.screen }?.name
            ?? draft.target.screen
        return L("%@ · Desktop %ld", name, draft.target.desktop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppIcon(bundleID: window.bundleID, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName).font(.callout.weight(.semibold))
                    Text(window.title.isEmpty ? L("Untitled window") : window.title)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer()
                Label(targetLabel, systemImage: "pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    ui.panel = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Cancel (Esc)"))
                .accessibilityLabel(L("Cancel"))
            }

            if mode != screens.mode {
                Text(L("Pin for %@", mode.title))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let key = windowKey.label {
                Picker("", selection: $scope) {
                    Text(L("This window (%@)", key)).tag(Scope.window)
                    Text(L("All windows of %@", window.appName)).tag(Scope.app)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 380)
            } else {
                Text(L("All windows of %@", window.appName))
                    .font(.callout.weight(.medium))
            }

            Text(matchDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            LayoutEditor(layout: $layout,
                         screen: store.screens(for: mode).first { $0.id == draft.target.screen })

            HStack {
                Spacer()
                Button(L("Cancel")) { ui.panel = nil }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                Button(L("Pin"), action: pin)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draftRule == nil)
            }
        }
        .onAppear { reset() }
        .onChange(of: draft) { fresh in
            // Kapanış eski gövdenin `draft`'ını tutar; taze ölçüm parametreden okunur.
            guard layout == measuredLayout,
                  let measured = fresh.window.currentLayout(
                    screens: screens.screens, fallbackScreen: fresh.target.screen),
                  measured != layout else { return }
            layout = measured
            measuredLayout = measured
        }
    }

    private func reset() {
        layout = currentLayout
        measuredLayout = layout
        scope = .window
    }

    /// Bu pencerenin anahtarı (belge yolu, başlığın kararlı parçası ya da
    /// yok); `Router.identity` başlık/belge geçmişini verir.
    private var windowKey: WindowIdentity.Resolution {
        let others = ui.windows.filter { $0.id != window.id }
        return WindowIdentity.resolve(window, others: others, history: router.identity)
    }

    /// Yazılacak kural taslağı: anahtar yoksa hep uygulama geneli.
    private var draftRule: Rule? {
        if scope == .window, let rule = windowKey.rule(appName: window.appName,
                                                       bundleID: window.bundleID) {
            return rule
        }
        return Rule(appName: window.appName, bundleID: window.bundleID, tokens: [])
    }

    /// Kuralın uyduğu pencere sayısı.
    private var matchCount: Int {
        guard let rule = draftRule else { return 0 }
        return ui.windows.filter { rule.matches($0) }.count
    }

    /// Düz dille neyin eşleşeceği: ham parça listesi gösterilmez.
    private var matchDescription: String {
        let count = matchCount == 1 ? L("1 window matches right now.")
                                    : L("%ld windows match right now.", matchCount)
        guard let rule = draftRule else { return count }
        if let path = rule.path {
            return L("Matches the file %@", path) + " " + count
        }
        if rule.isAppWide {
            let reason = windowKey == .none
                ? L("This window has no stable name to match.") + " " : ""
            return reason + L("The title is ignored; every window of %@ matches.", window.appName)
                + " " + count
        }
        let tokens = rule.tokens
        // Yalnız ana parça; daraltma ayrıntıları ham liste olarak basılmaz.
        let extra = tokens.count > 1 ? " " + L("Narrowed by %ld more detail(s) from the title.", tokens.count - 1) : ""
        return L("Matches: \"%@\"", tokens[0]) + extra + " " + count
    }

    /// Pencerenin şu anki çerçevesi, bulunduğu ekranın kullanılabilir
    /// alanına göre oranlar. Başka ekrana taşınıyorsa aynı oranlar orada
    /// uygulanır.
    private var currentLayout: WindowLayout {
        window.currentLayout(screens: screens.screens,
                             fallbackScreen: draft.target.screen) ?? .full
    }

    private func pin() {
        let destination = Destination(screen: draft.target.screen,
                                      desktop: draft.target.desktop, layout: layout)
        guard let rule = draftRule else { return }
        store.pin(rule, destination: destination, mode: mode)
        ui.panel = nil
    }
}
