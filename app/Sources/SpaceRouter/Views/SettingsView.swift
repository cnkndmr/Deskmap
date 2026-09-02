import AppKit
import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var hammerspoon: HammerspoonBridge

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                GroupBox("Davranış") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Taşıma sonrası bildirim göster",
                               isOn: $store.document.settings.notifications)

                        Toggle("Taşınan pencerenin Desktop'ına geç",
                               isOn: $store.document.settings
                                .followWindowAfterMove)

                        secondsSlider(
                            "Başlık gecikmesi",
                            help: "Başlık değişimlerinin yatışması için "
                                + "beklenen süre.",
                            value: $store.document.settings.debounceSeconds,
                            range: 0.1...2.0)

                        secondsSlider(
                            "Monitör gecikmesi",
                            help: "Dock takıldıktan sonra yeniden "
                                + "yerleştirme için beklenen süre.",
                            value: $store.document.settings
                                .screenSettleSeconds,
                            range: 0.5...8.0)

                        secondsSlider(
                            "Taşıma gecikmesi",
                            help: "Ekran değişimi ile Space taşıma arası.",
                            value: $store.document.settings.moveSettleSeconds,
                            range: 0.1...2.0)
                    }
                    .padding(6)
                }

                GroupBox("Günlük kaydı") {
                    Picker("Seviye", selection: $store.document.settings.logLevel) {
                        Text("Hata").tag("error")
                        Text("Uyarı").tag("warning")
                        Text("Bilgi").tag("info")
                        Text("Ayrıntılı").tag("debug")
                    }
                    .pickerStyle(.segmented)
                    .padding(6)
                }

                GroupBox("Motor") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Durum", value: hammerspoon.statusText)

                        HStack {
                            Button("Yapılandırmayı yeniden yükle") {
                                hammerspoon.reloadEngine()
                            }
                            .disabled(!hammerspoon.isRunning)

                            Button("rules.json dosyasını göster") {
                                NSWorkspace.shared.activateFileViewerSelecting(
                                    [RuleStore.fileURL])
                            }
                        }

                        Text(RuleStore.fileURL.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(6)
                }
            }
            .padding(12)
        }
    }

    private func secondsSlider(
        _ label: String,
        help: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f sn", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            Text(help)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
