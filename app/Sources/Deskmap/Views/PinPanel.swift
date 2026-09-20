import SwiftUI

/// Pin düğmesine basılınca ya da pencere sürüklenince açılır: başlığın
/// hangi parçası bu pencereyi tanımlıyor? Seçim kurala dönüşür; çerçeve
/// pencerenin o anki çerçevesidir.
struct PinPanel: View {

    let draft: PinDraft
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    /// Pin türü: başlığa göre kalıcı kural ya da pencere kimliğine bağlı
    /// geçici (oturum) pin.
    enum Kind: String, CaseIterable, Identifiable {
        case title, session
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title:   return L("By title")
            case .session: return L("This window only")
            }
        }
    }

    @State private var kind: Kind = .title
    @State private var segments: [String] = []
    @State private var chosen: Set<Int> = []
    @State private var appWide = false
    /// Varsayılan: pencerenin şu anki çerçevesi; hazır düzenle değiştirilebilir.
    @State private var layout: WindowLayout = .full

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

            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { candidate in
                    Text(candidate.label).tag(candidate)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 300)

            switch kind {
            case .title:
                Text(segments.isEmpty
                     ? L("This window has no title; all windows of the app are pinned.")
                     : L("Which part of the title identifies this window? This pin is permanent and saved to the profile."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TokenPicker(segments: segments, chosen: $chosen, appWide: $appWide)
            case .session:
                Text(L("The title is ignored; only this window (ID #%ld) is kept. Valid until the window closes or its app restarts; not saved to the profile.", Int(window.id)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            LayoutEditor(layout: $layout)

            HStack {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                Spacer()
                Button(L("Cancel")) { ui.panel = nil }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
                Button(kind == .session ? L("Pin temporarily") : L("Pin"), action: pin)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(kind == .title && !appWide && chosen.isEmpty)
            }
        }
        .onAppear { reset() }
        .onChange(of: draft.window.id) { _ in reset() }
    }

    private var footnote: String {
        switch kind {
        case .session:
            return L("Other windows with the same title are not affected. Temporary pins are shown with an orange icon.")
        case .title:
            if appWide {
                return L("The title is ignored; every window of %@ matches.", window.appName)
            }
            return matchCount == 1
                ? L("1 window matches right now.")
                : L("%ld windows match right now. Avoid parts that change, such as file names.", matchCount)
        }
    }

    private func reset() {
        layout = currentLayout
        kind = .title
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
        TokenPicker.tokens(segments: segments, chosen: chosen, appWide: appWide)
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
        window.currentLayout(screens: screens.screens,
                             fallbackScreen: draft.target.screen) ?? .full
    }

    private func pin() {
        let destination = Destination(screen: draft.target.screen,
                                      desktop: draft.target.desktop, layout: layout)
        switch kind {
        case .title:
            let rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
            store.pin(rule, destination: destination, mode: mode)
        case .session:
            router.pinSession(window.id, destination: destination)
        }
        ui.panel = nil
    }
}
