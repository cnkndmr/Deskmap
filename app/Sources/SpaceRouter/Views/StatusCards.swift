import SwiftUI

// MARK: - macOS ayarları kartı

/// Space Router'ın çalışması için gereken macOS ayarları. Canlı denetlenen
/// ayarlardan biri yanlışsa kart kapatılamaz; hepsi doğruysa yalnızca
/// genel hatırlatma gösterilir ve "Anladım" ile gizlenir.
struct SetupCard: View {

    let checks: [MacSettings.Check]

    @EnvironmentObject private var store: Store

    private var allOK: Bool { checks.allSatisfy(\.ok) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: allOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(allOK ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(allOK ? "macOS ayarları uygun" : "macOS ayarları düzeltilmeli")
                        .font(.callout.weight(.semibold))
                    Text(allOK
                         ? "Kurulumda bir kez kontrol edilmesi gerekenler aşağıda."
                         : "Bu ayarlar böyle kalırsa Space Router düzgün çalışmaz: Dock'tan geçiş "
                           + "yanlış masaüstüne gider, pencereler belirip kaybolur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Desktop & Dock'u aç") { MacSettings.openDesktopAndDock() }
                    .controlSize(.small)
                if allOK {
                    Button("Anladım") { store.document.setupNoticeDismissed = true }
                        .controlSize(.small)
                        .help("Kartı gizle; bir ayar bozulursa yeniden görünür")
                }
            }

            ForEach(checks) { check in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.ok ? Color.green : Color.red)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.title).font(.caption.weight(.medium))
                        Text(check.detail).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                Text("Erişilebilirlik izni gerekli")
                    .font(.callout.weight(.semibold))
                Text("Pencereleri görmek ve taşımak için.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("İzin ver") {
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
            Text("Başlarken")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            step(1, "pin",
                 "Aşağıda bir pencere satırındaki pin düğmesine tıklayın.")
            step(2, "textformat",
                 "Başlığın bu pencereyi tanımlayan parçasını seçin; pencere artık o masaüstünde kalır.")
            step(3, "arrow.up.and.down.and.arrow.left.and.right",
                 "Bir satırı başka masaüstüne sürüklemek pencereyi bir kez taşır, pinlemez. "
                 + "Üstteki laptop / monitör düğmesi diğer kurulum içindir; ikisi ayrı ayarlanır.")
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
