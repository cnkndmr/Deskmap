import AppKit
import SwiftUI

struct RootView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case rules = "Kurallar"
        case screens = "Ekranlar"
        case settings = "Ayarlar"

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var accessibility: AccessibilityService
    @EnvironmentObject private var hammerspoon: HammerspoonBridge

    @State private var selectedTab: Tab = .rules
    @State private var editingRule: Rule?

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            StatusHeaderView()

            Divider()

            if let rule = editingRule {
                RuleEditorView(
                    rule: rule,
                    onSave: { updated in
                        if store.document.rules.contains(where: {
                            $0.id == updated.id
                        }) {
                            store.update(updated)
                        } else {
                            store.addRule(updated)
                        }
                        editingRule = nil
                    },
                    onCancel: { editingRule = nil })
            } else {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Group {
                    switch selectedTab {
                    case .rules:
                        RuleListView(onEdit: { editingRule = $0 })
                    case .screens:
                        ScreensView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            FooterView()
        }
    }
}

// MARK: - Alt bar

private struct FooterView: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var hammerspoon: HammerspoonBridge

    var body: some View {
        HStack(spacing: 12) {
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let savedAt = store.lastSavedAt {
                Text("Kaydedildi · \(savedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Değişiklikler otomatik kaydedilir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Pencereleri yerleştir") {
                hammerspoon.rescanWindows()
            }
            .disabled(!hammerspoon.isRunning)
            .font(.caption)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Space Router uygulamasından çık")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
