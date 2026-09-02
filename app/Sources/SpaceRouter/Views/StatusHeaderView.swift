import SwiftUI

/// Motorun ve izinlerin tek bakışta durumu.
struct StatusHeaderView: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var screenService: ScreenService
    @EnvironmentObject private var accessibility: AccessibilityService
    @EnvironmentObject private var hammerspoon: HammerspoonBridge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Space Router")
                    .font(.headline)

                Spacer()

                Toggle("Etkin", isOn: $store.document.settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Yönlendirmeyi tamamen açar veya kapatır")
            }

            HStack(spacing: 14) {
                statusChip(
                    ok: hammerspoon.isHealthy,
                    text: hammerspoon.statusText,
                    symbol: "gearshape.2")

                statusChip(
                    ok: accessibility.isTrusted,
                    text: accessibility.isTrusted
                        ? "Erişilebilirlik izni var"
                        : "Erişilebilirlik izni gerekli",
                    symbol: "hand.raised")
            }

            HStack(spacing: 6) {
                Image(systemName: screenService.isDocked
                      ? "display.2" : "laptopcomputer")
                    .foregroundStyle(.secondary)

                Text(screenService.isDocked
                     ? "Harici monitör bağlı — docked profili geçerli"
                     : "Yalnızca dahili ekran — undocked profili geçerli")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !accessibility.isTrusted {
                Button("Erişilebilirlik iznini aç") {
                    accessibility.requestAccess()
                    accessibility.openSystemSettings()
                }
                .font(.caption)
            } else if !hammerspoon.isRunning && hammerspoon.isInstalled {
                Button("Hammerspoon'u başlat") {
                    hammerspoon.launchHammerspoon()
                }
                .font(.caption)
            }
        }
        .padding(12)
    }

    private func statusChip(
        ok: Bool, text: String, symbol: String
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
    }
}
