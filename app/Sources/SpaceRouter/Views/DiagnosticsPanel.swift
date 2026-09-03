import AppKit
import SwiftUI

/// Tanılama paneli: izinler, Space API durumu, son taramanın pencere
/// listeleme raporu (hangi pencere hangi yoldan geldi / neden elendi),
/// ekran-masaüstü durumu ve son taşıma denemeleri. Menü çubuğu penceresi
/// popover açınca kapandığı için alt panelde, satır içi gösterilir.
struct DiagnosticsPanel: View {

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var permission: AccessibilityPermission
    @EnvironmentObject private var ui: UIState

    @State private var copied = false

    private var diagnostics: Router.Diagnostics { router.diagnostics }
    private var sky: SkyLight { SkyLight.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Tanılama", systemImage: "stethoscope")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(copied ? "Kopyalandı" : "Raporu kopyala") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(report, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copied = false
                    }
                }
                .controlSize(.small)
                Button {
                    ui.diagnosticsPanel = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Kapat")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    permissions
                    spaceAPI
                    lastSweep
                    displays
                    lenient
                    dropped
                    moves
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
        }
        .font(.caption)
    }

    // MARK: - Bölümler

    private var permissions: some View {
        section("İzinler") {
            statusRow(ok: permission.isTrusted,
                      text: "Erişilebilirlik (pencereleri görmek ve taşımak için)")
            HStack(spacing: 6) {
                statusRow(ok: permission.canReadWindowNames,
                          text: "Ekran Kaydı — isteğe bağlı: başka masaüstündeki "
                            + "pencerelerin başlığını verir; başlık kuralları onlara da uygulanır")
                if !permission.canReadWindowNames {
                    Button("İzin ver") { permission.requestWindowNames() }
                        .controlSize(.mini)
                }
            }
        }
    }

    private var spaceAPI: some View {
        section("Space API (SkyLight)") {
            statusRow(ok: sky.isAvailable, text: "Masaüstü listesi ve pencere → space sorgusu")
            statusRow(ok: sky.movePath != .unavailable,
                      text: "Taşıma yolu: \(sky.movePath.rawValue)")
            statusRow(ok: diagnostics.scan.remoteTokenAvailable,
                      text: "_AXUIElementCreateWithRemoteToken (başka masaüstündeki pencereler)")
            statusRow(ok: diagnostics.scan.getWindowIDAvailable,
                      text: "_AXUIElementGetWindow (AX öğesi → pencere numarası)")
            let missing = sky.symbolReport.filter { !$0.found }.map(\.name)
            if !missing.isEmpty {
                Text("Bulunamayan simgeler: " + missing.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                .foregroundStyle(.tertiary)
        }
    }

    private var lastSweep: some View {
        section("Son tarama") {
            if let at = diagnostics.lastSweepAt {
                let scan = diagnostics.scan
                Text(Self.time(at) + " · \(Int(diagnostics.sweepDuration * 1000)) ms · "
                     + "\(router.status.routedWindows) pencere kurala/pine uydu")
                Text("Uygulama listesinden \(scan.fromAXList) · uzak belirteçle doğrulanmış "
                     + "\(scan.fromServerVerified) · rol okunamadan alınan "
                     + "\(scan.fromServerLenient.count) · elenen \(scan.dropped.count)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Henüz tarama yapılmadı.").foregroundStyle(.secondary)
            }
        }
    }

    private var displays: some View {
        section("Ekranlar ve masaüstleri") {
            if diagnostics.displays.isEmpty {
                Text("Ekran bilgisi alınamadı.").foregroundStyle(.secondary)
            }
            ForEach(diagnostics.displays) { display in
                Text(Self.line(for: display))
            }
        }
    }

    private var lenient: some View {
        let entries = diagnostics.scan.fromServerLenient
        return section("Rol okunamadan listelenenler (\(entries.count))") {
            if entries.isEmpty {
                Text("Yok.").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                entryRow(entry)
            }
        }
    }

    private var dropped: some View {
        let entries = diagnostics.scan.dropped
        return section("Pencere sunucusunda olup elenenler (\(entries.count))") {
            if entries.isEmpty {
                Text("Yok.").foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                entryRow(entry)
            }
        }
    }

    private var moves: some View {
        section("Son taşımalar") {
            if diagnostics.moves.isEmpty {
                Text("Bu oturumda taşıma yapılmadı.").foregroundStyle(.secondary)
            }
            ForEach(diagnostics.moves) { move in
                HStack(spacing: 6) {
                    Image(systemName: move.verified ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(move.verified ? Color.green : Color.red)
                    Text(Self.time(move.at)).foregroundStyle(.tertiary)
                    Text(move.text)
                    Spacer()
                    Text(Self.short(move.path)).foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                .help(move.verified ? Self.verifiedHelp : Self.unverifiedHelp)
            }
        }
    }

    // MARK: - Parçalar

    private static let verifiedHelp = "Pencere taşımadan sonra hedef space'te görüldü"
    private static let unverifiedHelp = "Pencere 300 ms içinde hedef space'te görülmedi — "
        + "taşıma yolu bu macOS sürümünde çalışmıyor olabilir"

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func statusRow(ok: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.red)
            Text(text)
        }
    }

    private func entryRow(_ entry: AX.ScanReport.Entry) -> some View {
        HStack(spacing: 6) {
            Text("#\(entry.id)").foregroundStyle(.tertiary)
                .frame(width: 52, alignment: .leading)
            Text(entry.appName).fontWeight(.medium)
            Text(entry.name.isEmpty ? "(adsız)" : entry.name)
                .foregroundStyle(.secondary)
            Spacer()
            Text(entry.reason).foregroundStyle(.tertiary)
        }
        .lineLimit(1)
    }

    private static func line(for display: Router.Diagnostics.Display) -> String {
        var text = "\(display.name): \(display.desktops) masaüstü"
        if let index = display.currentIndex {
            text += " · görünen: Masaüstü \(index)"
        } else {
            text += " · görünen space bir masaüstü değil (tam ekran?)"
        }
        return text
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func short(_ path: SkyLight.MovePath) -> String {
        switch path {
        case .bridged:     return "bridged"
        case .compatID:    return "compatID"
        case .legacy:      return "legacy"
        case .unavailable: return "yok"
        }
    }

    // MARK: - Düz metin rapor

    private var report: String {
        var lines: [String] = []
        lines.append("Space Router tanılama — \(Date())")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")
        lines.append("[İzinler]")
        lines.append("Erişilebilirlik: \(permission.isTrusted ? "var" : "YOK")")
        lines.append("Ekran Kaydı (pencere adları): \(permission.canReadWindowNames ? "var" : "yok")")
        lines.append("")
        lines.append("[Space API]")
        lines.append("Kullanılabilir: \(sky.isAvailable)")
        lines.append("Taşıma yolu: \(sky.movePath.rawValue)")
        for symbol in sky.symbolReport {
            lines.append("  \(symbol.found ? "+" : "-") \(symbol.name)")
        }
        lines.append("  \(diagnostics.scan.remoteTokenAvailable ? "+" : "-") _AXUIElementCreateWithRemoteToken")
        lines.append("  \(diagnostics.scan.getWindowIDAvailable ? "+" : "-") _AXUIElementGetWindow")
        lines.append("")
        lines.append("[Son tarama]")
        if let at = diagnostics.lastSweepAt {
            let scan = diagnostics.scan
            lines.append("\(Self.time(at)) · \(Int(diagnostics.sweepDuration * 1000)) ms"
                         + " · kurala/pine uyan: \(router.status.routedWindows)")
            lines.append("AX listesi: \(scan.fromAXList) · uzak doğrulanmış: \(scan.fromServerVerified)"
                         + " · rol okunamadan alınan: \(scan.fromServerLenient.count)"
                         + " · elenen: \(scan.dropped.count)")
        } else {
            lines.append("henüz yok")
        }
        lines.append("")
        lines.append("[Ekranlar]")
        for display in diagnostics.displays {
            lines.append("\(display.name): \(display.desktops) masaüstü, görünen: "
                         + (display.currentIndex.map(String.init) ?? "-"))
        }
        lines.append("")
        lines.append("[Rol okunamadan listelenenler]")
        for entry in diagnostics.scan.fromServerLenient {
            lines.append("#\(entry.id) \(entry.appName) \"\(entry.name)\" — \(entry.reason)")
        }
        lines.append("")
        lines.append("[Elenenler]")
        for entry in diagnostics.scan.dropped {
            lines.append("#\(entry.id) \(entry.appName) \"\(entry.name)\" — \(entry.reason)")
        }
        lines.append("")
        lines.append("[Son taşımalar]")
        for move in diagnostics.moves {
            lines.append("\(Self.time(move.at)) \(move.verified ? "OK " : "?? ")\(move.text)"
                         + " [\(Self.short(move.path))]")
        }
        return lines.joined(separator: "\n")
    }
}
