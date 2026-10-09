import SwiftUI

/// Pin düğmesine basılınca ya da pencere sürüklenince açılır. İki seçenek:
/// yalnız bu pencere (kararlı kimlikle kalıcı kural, bulunamazsa sessizce
/// oturum pini) ya da uygulamanın bütün pencereleri. Çerçeve pencerenin o
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

            Picker("", selection: $scope) {
                Text(L("This window")).tag(Scope.window)
                Text(L("All windows of %@", window.appName)).tag(Scope.app)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 320)

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
                    .disabled(resolution == nil)
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

    /// Bu pencerenin pin kararı. Geçici pin yalnız şu anki kurulumda
    /// anlamlı; diğer kurulumda kalıcı bir anahtar yoksa nil (pinlenemez).
    private var resolution: WindowIdentity.Resolution? {
        switch scope {
        case .app:
            return .rule([])
        case .window:
            let others = ui.windows.filter { $0.id != window.id }
            let found = WindowIdentity.resolve(appName: window.appName, bundleID: window.bundleID,
                                               title: window.title, others: others)
            guard found == .session, mode != screens.mode else { return found }
            let parts = WindowIdentity.candidates(appName: window.appName,
                                                  bundleID: window.bundleID, title: window.title)
            return parts.isEmpty ? nil : .rule(parts)
        }
    }

    /// Kuralın uyduğu pencere sayısı (oturum pininde 1).
    private var matchCount: Int {
        guard case .rule(let tokens) = resolution else { return 1 }
        let rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
        return ui.windows.filter {
            rule.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
        }.count
    }

    /// Düz dille neyin eşleşeceği: ham parça listesi gösterilmez.
    private var matchDescription: String {
        let count = matchCount == 1 ? L("1 window matches right now.")
                                    : L("%ld windows match right now.", matchCount)
        switch resolution {
        case .rule(let tokens) where tokens.isEmpty:
            return L("The title is ignored; every window of %@ matches.", window.appName) + " " + count
        case .rule(let tokens):
            // Yalnız ana parça; daraltma ayrıntıları ham liste olarak basılmaz.
            let extra = tokens.count > 1 ? " " + L("Narrowed by %ld more detail(s) from the title.", tokens.count - 1) : ""
            return L("Matches: \"%@\"", tokens[0]) + extra + " " + count
        case .session:
            return L("No stable name found; only this window is kept until it closes or its app restarts.")
        case nil:
            return L("This window has no stable name to match.")
        }
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
        switch resolution {
        case .rule(let tokens):
            let rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
            store.pin(rule, destination: destination, mode: mode)
        case .session:
            router.pinSession(window.id, destination: destination)
        case nil:
            return
        }
        ui.panel = nil
    }
}
