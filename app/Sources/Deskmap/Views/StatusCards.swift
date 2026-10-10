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

/// Masaüstü taşıması bu Mac'te yok ya da doğrulanamadı (devre kesici
/// açık): ekran ve düzen uygulanmaya devam eder, masaüstü taşıma durur.
struct ReducedModeCard: View {

    /// false: bu macOS'ta hiç taşıma yolu yok (yeniden deneme anlamsız).
    let canMove: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Reduced mode: desktop moves are off"))
                    .font(.callout.weight(.semibold))
                Text(canMove
                     ? L("Moves to other desktops did not take effect several times in a row, so they were stopped. Windows are still placed on the right display and in the right layout.")
                     : L("Moving windows between desktops is not available on this macOS. Windows are still placed on the right display and in the right layout."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if canMove {
                Button(L("Try Again"), action: retry)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
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
