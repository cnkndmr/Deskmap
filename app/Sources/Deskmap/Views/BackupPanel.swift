import SwiftUI

/// Otomatik yedekler: katmana göre gruplu liste, satır başına zaman ve
/// profiller. Geri yükleme iki tık (satır içi onay; menü çubuğu penceresinde
/// sayfa/diyalog pencereyi kapatır): önce şimdiki hâl yedeklenir, sonra
/// belge değişir; alt çubukta "Geri al" çıkar.
struct BackupPanel: View {

    @ObservedObject var service: BackupService
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ui: UIState

    /// Onay bekleyen satır.
    @State private var confirming: String?

    private static let groups: [(BackupTier, String)] = [
        (.hourly, L("Hourly (last 24 hours)")),
        (.daily, L("Daily (last 7 days)")),
        (.weekly, L("Weekly (kept forever)")),
        (.preRestore, L("Before restore")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text(L("Backups")).font(.headline)
                Spacer()
                Button(L("Back up now")) {
                    if let e = service.runNow().skipped {
                        store.report(L("No backup taken: %@", e.localizedDescription))
                    }
                    service.reload()
                }
                .controlSize(.small)
                .disabled(store.isReadOnly)
                Button {
                    ui.panel = .profile
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help(L("Close (Esc)"))
                .accessibilityLabel(L("Close"))
            }
            Text(L("Deskmap keeps all profiles, pins and desktop names: one copy per hour for a day, one per day for a week, one per week forever."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if service.entries.isEmpty {
                Text(L("No backups yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Self.groups, id: \.0) { tier, title in
                            let rows = service.entries.filter { $0.tier == tier }
                            if !rows.isEmpty {
                                Text(title).font(.caption.weight(.semibold))
                                ForEach(rows) { row($0) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .onAppear { service.reload() }
        .onChange(of: service.lastRun) { _ in service.reload() }
    }

    private func row(_ entry: BackupEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.created.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.monospacedDigit())
                .frame(width: 150, alignment: .leading)
            Text(summary(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(entry.id)
            Spacer()
            if confirming == entry.id {
                Button(L("Cancel")) { confirming = nil }
                Button(L("Replace current profiles"), role: .destructive) {
                    confirming = nil
                    if service.restore(entry.id, store: store, router: router) {
                        ui.panel = nil
                    }
                }
            } else {
                Button(L("Restore")) { confirming = entry.id }
                    .disabled(store.isReadOnly)
                    .help(L("Restore this backup; the current state is backed up first and can be undone"))
            }
        }
        .controlSize(.small)
    }

    private func summary(_ entry: BackupEntry) -> String {
        entry.profiles.map { profile in
            let pins = profile.ruleCount == 1 ? L("1 pin") : L("%ld pins", profile.ruleCount)
            return "\(profile.isActive ? "✓ " : "")\(profile.name) (\(pins))"
        }.joined(separator: ", ")
    }
}
