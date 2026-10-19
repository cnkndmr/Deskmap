import SwiftUI

// MARK: - macOS ayarları kartı

/// Deskmap'in çalışması için gereken macOS ayarları. Zorunlu ayarlardan
/// biri yanlışsa kart kapatılamaz; zorunluların hepsi doğruysa yalnızca
/// genel hatırlatma gösterilir ve "Anladım" ile gizlenir. Önerilen ayar
/// kapalıysa sarı ipucu olarak kalır, kartı "düzeltilmeli"ye çevirmez.
struct SetupCard: View {

    let checks: [MacSettings.Check]
    /// false: Ayarlar penceresinde; "Anladım" düğmesi yok.
    var dismissible = true

    @EnvironmentObject private var store: Store

    private var allOK: Bool { MacSettings.allRequiredOK(checks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: allOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(allOK ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(allOK ? L("macOS settings look good") : L("macOS settings need fixing"))
                        .font(.callout.weight(.semibold))
                    Text(allOK
                         ? L("Things to check once during setup are listed below.")
                         : L("With these settings Deskmap cannot work properly: switching from the Dock goes to the wrong desktop, and windows appear and vanish."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("Open Desktop & Dock")) { MacSettings.openDesktopAndDock() }
                    .controlSize(.small)
                if allOK && dismissible {
                    Button(L("Got It")) { store.document.setupNoticeDismissed = true }
                        .controlSize(.small)
                        .help(L("Hide this card; it comes back if a setting changes"))
                }
            }

            // Zorunlu ayarlar tek akışta; önerilen ayar ayrı başlık altında.
            ForEach(checks.filter(\.required)) { check in
                checkRow(check)
            }
            if checks.contains(where: { !$0.required }) {
                Text(L("Recommended"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(checks.filter { !$0.required }) { check in
                    checkRow(check)
                }
            }

            ForEach(MacSettings.reminders, id: \.self) { reminder in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text(reminder).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill((allOK ? Color.green : Color.orange).opacity(0.10)))
    }

    private func checkRow(_ check: MacSettings.Check) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon(for: check))
                .foregroundStyle(color(for: check))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).font(.caption.weight(.medium))
                Text(check.detail).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func icon(for check: MacSettings.Check) -> String {
        if check.ok { return "checkmark.circle.fill" }
        return check.required ? "xmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private func color(for check: MacSettings.Check) -> Color {
        if check.ok { return .green }
        return check.required ? .red : .yellow
    }
}

// MARK: - Düşük mod kartı

/// Masaüstü taşıması bu Mac'te yok, bu macOS'ta doğrulanmadı ya da
/// doğrulanamadı (devre kesici açık): ekran ve düzen uygulanmaya devam
/// eder, masaüstü taşıma durur.
struct ReducedModeCard: View {

    enum Reason: Equatable {
        /// Bu macOS'ta hiç taşıma yolu yok (yeniden deneme anlamsız).
        case unavailable
        /// Taşıma bu macOS sürümünde doğrulanmadı (PLAN K4); kullanıcı
        /// deneyebilir.
        case unverified(version: String)
        /// Taşımalar art arda etkisiz kaldı (devre kesici).
        case failed

        /// Kart gösterilecekse nedeni (saf).
        static func current(canMove: Bool, health: MoveHealth.State,
                            version: String) -> Reason? {
            if !canMove { return .unavailable }
            switch health {
            case .held: return .unverified(version: version)
            case .degraded: return .failed
            case .unknown, .working: return nil
            }
        }
    }

    let reason: Reason
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch reason {
            case .unavailable:
                EmptyView()
            case .unverified:
                Button(L("Try Anyway"), action: retry)
                    .controlSize(.small)
            case .failed:
                Button(L("Try Again"), action: retry)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
    }

    private var title: String {
        switch reason {
        case .unverified: return L("Desktop moves are off on this macOS")
        case .unavailable, .failed: return L("Reduced mode: desktop moves are off")
        }
    }

    private var message: String {
        switch reason {
        case .unavailable:
            return L("Moving windows between desktops is not available on this macOS. Windows are still placed on the right display and in the right layout.")
        case .unverified(let version):
            return L("Moving windows between desktops has not been verified on macOS %@. Windows are still placed on the right display and in the right layout. If you try it and moves do not take effect, Deskmap turns them off again.", version)
        case .failed:
            return L("Moves to other desktops did not take effect several times in a row, so they were stopped. Windows are still placed on the right display and in the right layout.")
        }
    }
}

// MARK: - İzin kartı

struct PermissionCard: View {

    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Accessibility permission required"))
                    .font(.callout.weight(.semibold))
                Text(L("Needed to see and move windows."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("Deskmap works offline: it makes no network connections and never reads what is inside your windows, only their titles, positions and desktops."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(L("Grant Access")) {
                permission.request()
                permission.openSettings()
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
    }
}

// MARK: - İlk adımlar kartı

/// İlk kullanım: izin var ama aktif profilde pin ve geçici pin yok. Üç
/// adım; ilk pinle kendiliğinden kaybolur, kayıt tutulmaz (yeni boş
/// profilde yeniden görünmesi de istenen davranış).
struct FirstStepsCard: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Getting Started"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            step(1, "pin",
                 L("Click the pin button on a window row below."))
            step(2, "textformat",
                 L("Select the part of the title that identifies the window; it now stays on that desktop."))
            step(3, "arrow.up.and.down.and.arrow.left.and.right",
                 L("Dragging a row to another desktop moves the window once without pinning it. The Plan switch at the top (Monitor connected / Laptop only) shows two separate plans; each is set up on its own."))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
    }

    private func step(_ number: Int, _ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor))
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Ad geçişi raporu (şema 6)

/// Şema 5 → 6 geçişinin raporu: profil başına bağlanan adlar, yerleşmeyen
/// adlar, kaldırılan hayaletler, geri gelen pinler; planın ötesindeki boş
/// masaüstüleri için "Kaldır" (M1), "Geçişi geri al".
struct MigrationReportCard: View {

    let report: MigrationReport
    let removeEmpty: () -> Void
    let undoUpgrade: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Desktop names upgraded"))
                    .font(.callout.weight(.semibold))
                Text(L("Each name now belongs to one desktop and follows it; plug and unplug arrange desktops by plan."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(report.profiles, id: \.profileID) { entry in
                    Text(Self.line(entry))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if report.emptyCount > 0 {
                        Button(report.emptyCount == 1 ? L("Remove 1 empty desktop")
                                                      : L("Remove %ld empty desktops", report.emptyCount),
                               action: removeEmpty)
                            .help(L("Desktops beyond the plan that have no windows; each is checked again right before removal."))
                    }
                    Button(L("Undo upgrade"), action: undoUpgrade)
                        .help(L("Put back the previous rules.json; changes are not saved until Deskmap restarts."))
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Close"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.10)))
    }

    /// Profilin özet satırı (saf).
    static func line(_ entry: MigrationReport.ProfileReport) -> String {
        var parts: [String] = []
        if !entry.bound.isEmpty {
            parts.append(entry.bound.map { L("%@ → %@ %ld", $0.name, $0.screen, $0.desktop) }
                .joined(separator: ", "))
        }
        if !entry.unplaced.isEmpty {
            parts.append(L("no desktop yet: %@", entry.unplaced.joined(separator: ", ")))
        }
        if entry.ghostsRemoved > 0 {
            parts.append(L("%ld deleted-desktop rows cleared", entry.ghostsRemoved))
        }
        if entry.pinsRestored > 0 {
            parts.append(L("%ld pins restored", entry.pinsRestored))
        }
        let body = parts.isEmpty ? L("no desktop names") : parts.joined(separator: " · ")
        return "\(entry.profileName): \(body)"
    }
}

// MARK: - Plan uygulaması durumu

/// Monitör takılıp çıkınca planın uygulanma sonucu; başarısızlıkta "Yeniden dene".
struct PlanStatusCard: View {

    let status: Router.PlanStatus
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: status.failed ? "exclamationmark.triangle.fill" : "rectangle.3.group")
                .foregroundStyle(status.failed ? Color.orange : Color.accentColor)
            Text(status.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if status.failed {
                Button(L("Retry"), action: retry).controlSize(.small)
            }
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("Close"))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill((status.failed ? Color.orange : Color.accentColor).opacity(0.10)))
    }
}
