import SwiftUI

/// Ayarlar › Yedekler: otomatik yedekler katmana göre gruplu, satır başına
/// zaman ve profiller. Geri yükleme iki tık (satır içi onay): önce şimdiki
/// hâl yedeklenir, sonra belge değişir; haritanın alt çubuğunda "Geri al"
/// çıkar (⌘Z).
struct BackupSettings: View {

    @ObservedObject var service: BackupService
    @EnvironmentObject private var store: Store

    /// Onay bekleyen satır.
    @State private var confirming: String?
    /// Son geri yükleme sonucu (satır altında kısa not).
    @State private var restored: String?

    private static let groups: [(BackupTier, String)] = [
        (.hourly, L("Hourly (last 24 hours)")),
        (.daily, L("Daily (last 7 days)")),
        (.weekly, L("Weekly (kept forever)")),
        (.preRestore, L("Before restore")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Deskmap keeps all profiles, pins and desktop names: one copy per hour for a day, one per day for a week, one per week forever."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            if service.entries.isEmpty {
                Text(L("No backups yet"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Divider() }
            } else {
                ForEach(Self.groups, id: \.0) { tier, title in
                    let rows = service.entries.filter { $0.tier == tier }
                    if !rows.isEmpty {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(rows) { row($0) }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    if let e = service.runNow().skipped {
                        store.report(L("No backup taken: %@", e.localizedDescription))
                    }
                    service.reload()
                } label: {
                    Label(L("Back up now"), systemImage: "clock.arrow.circlepath")
                }
                .disabled(store.isReadOnly)
                if let restored {
                    Text(restored).font(.caption).foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
        .onAppear { service.reload() }
        .onChange(of: service.lastRun) { _ in service.reload() }
    }

    private func row(_ entry: BackupEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.created.formatted(date: .abbreviated, time: .shortened))
                .font(.callout.monospacedDigit())
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
                    if service.restore(entry.id, store: store,
                                       router: BackupService.current == nil ? nil : AppModel.shared.router) {
                        restored = L("Backup restored")
                    }
                }
            } else {
                Button(L("Restore")) { confirming = entry.id }
                    .disabled(store.isReadOnly)
                    .help(L("Restore this backup; the current state is backed up first and can be undone"))
            }
        }
        .controlSize(.small)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }

    private func summary(_ entry: BackupEntry) -> String {
        entry.profiles.map { profile in
            "\(profile.isActive ? "✓ " : "")\(profile.name) (\(pinCount(profile.ruleCount)))"
        }.joined(separator: ", ")
    }
}
