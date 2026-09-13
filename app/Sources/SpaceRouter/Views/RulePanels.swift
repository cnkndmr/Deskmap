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
                Label("Pini kaldır", systemImage: "pin.slash")
            }
            .controlSize(.small)

            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .help("Kapat (Esc)")
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

            if let destination = rule[mode] {
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
        return rule[other] == nil ? "\(other.title): pin yok" : "\(other.title): pinli"
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
                subtitle: window.title.isEmpty ? "Adsız pencere" : window.title,
                unpin: {
                    router.unpinSession(window.id)
                    ui.panel = nil
                },
                close: { ui.panel = nil }
            ) {
                Label("Geçici · pencere #\(window.id)", systemImage: "pin.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                    .help("Yalnızca bu pencere, bu oturum için. Profile yazılmaz.")
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
