import AppKit
import SwiftUI

/// Pinli bir kuralı temsil eden sürüklenebilir çip: uygulama simgesi,
/// başlık parçası ve çerçeve simgesi. Canlı penceresi olmayan pinler
/// (kapalı uygulama ya da diğer mod) böyle gösterilir. Tıklanınca alt
/// panelde kural bilgisi ve "pini kaldır" açılır.
struct RuleChip: View {

    let rule: Rule
    let mode: Mode
    var isGhost = false
    /// Penceresi açık ama bu kuralı geçen kuralın kimliği (gölgede kalan
    /// pin); çip soluk çizilir, ipucu nedenini söyler.
    var shadowedBy: String?
    /// Çip "Kurulumlar arasında farklı" kutusunda: ipucu ona göre, kutuya
    /// geri bırakmak pini kaldırmaz.
    var inTray = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    private var isSelected: Bool { ui.panel == .rule(rule.id) }
    private var isBeingDragged: Bool { !isGhost && ui.drag?.item == .rule(rule.id) }
    /// Harita şu anki modu gösteriyor mu? Eksik masaüstü rozeti yalnızca o zaman.
    private var isLive: Bool { mode == screens.mode }

    var body: some View {
        HStack(spacing: 5) {
            AppIcon(bundleID: rule.bundleID, size: 14)
            Image(systemName: "pin.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Text(rule.title.isEmpty ? rule.appName : rule.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if reopenLabel != nil {
                // Tam pencere (dosya/klasör/sayfa) yeniden açılabilir.
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if let target = store.nameTarget(rule[mode], mode: mode) {
                // Ad hedefi: "→ Nova Ek"; adın masaüstü yoksa "bekliyor".
                HStack(spacing: 2) {
                    Image(systemName: target.waiting ? "hourglass" : "arrow.right")
                        .font(.system(size: 8, weight: .semibold))
                    Text(target.name)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(target.waiting ? Color.orange : Color.secondary)
            }
            if let destination = rule[mode] {
                if let real = MissingDesktopBadge.clamped(for: destination,
                                                          desktopCounts: ui.desktopCounts,
                                                          isLive: isLive) {
                    MissingDesktopBadge(wanted: destination.desktop, real: real)
                }
                LayoutGlyph(layout: destination.layout, size: CGSize(width: 14, height: 10),
                            screenSize: store.screenSize(of: destination.screen))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.18)
                                              : Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: 1))
        .contentShape(Capsule())
        .opacity(isBeingDragged ? 0.35 : (shadowedBy == nil ? 1 : 0.5))
        .modifier(RuleInteractions(rule: rule, mode: mode, isGhost: isGhost, inTray: inTray))
        .help(helpText)
        .searchLook(dimmed: searchLook.dimmed, highlighted: searchLook.highlighted, cornerRadius: 12)
    }

    private var searchLook: (dimmed: Bool, highlighted: Bool) {
        isGhost ? (false, false) : ui.searchLook(appName: rule.appName, title: rule.title)
    }

    /// Çift tıklamayla açılacak şeyin kısa adı (dosya/klasör adı ya da
    /// site); hatırlanan hedef yoksa nil.
    private var reopenLabel: String? {
        guard let target = router.reopenTargets[rule.id], let url = URL(string: target.url) else {
            // Finder'ın özel konumu (Recents…) hedef olmadan da açılır.
            guard rule.bundleID == Reopen.finder else { return nil }
            return rule.tokens.first { Reopen.finderLocation(named: $0) != nil }
        }
        if url.pathExtension == "app" { return url.deletingPathExtension().lastPathComponent }
        return url.isFileURL ? url.lastPathComponent : (url.host ?? target.url)
    }

    private var helpText: String {
        let target = store.nameTarget(rule[mode], mode: mode)
        let base = "\(rule.appName): \(rule.title)"
            + (reopenLabel.map { "\n" + L("Double-click opens %@", $0) } ?? "")
            + (target.map { $0.waiting ? "\n" + L("Waiting for “%@”: that desktop does not exist yet", $0.name)
                                       : "\n" + L("Follows the desktop “%@” wherever it is", $0.name) } ?? "")
        if inTray {
            return base + "\n" + L("Drag onto a desktop to give it a place in this plan.")
        }
        guard let shadowedBy else {
            return base + "\n" + L("Its window is not open right now. Double-click to open it; drag to move.")
        }
        let winner = shadowedBy == Routing.sessionRuleID
            ? L("a temporary pin")
            : L("the “%@” pin", store.rule(shadowedBy)?.title ?? "")
        return base + "\n" + L("This window is matched first by %@; this pin does not take effect.", winner)
    }
}

// MARK: - Düzen simgesi

/// Ekranı temsil eden çerçeve içinde pencerenin kapladığı alan.
struct LayoutGlyph: View {

    let layout: WindowLayout
    let size: CGSize
    /// Sabit boyutlu düzeni ölçeklemek için ekranın kullanılabilir alanı
    /// (pt); bilinmiyorsa 1710 × 1074 pt (bu Mac'in dahili ekranı).
    var screenSize = CGSize(width: 1710, height: 1074)

    init(layout: WindowLayout, size: CGSize,
         screenSize: CGSize = CGSize(width: 1710, height: 1074)) {
        self.layout = layout
        self.size = size
        self.screenSize = screenSize
    }

    /// Hazır düzen düğmeleri için standart boy.
    init(preset: WindowLayout) {
        self.init(layout: preset, size: CGSize(width: 30, height: 20))
    }

    /// Hazır düzen düğmesi boyu, ekranın oranında (saf): ultra geniş ekranda
    /// sütunlar seçilebilsin diye daha geniş.
    static func presetSize(aspect: Double) -> CGSize {
        let a = max(aspect, 0.5)
        let height: CGFloat = a >= WindowLayout.ultrawideAspect ? 14 : 20
        return CGSize(width: min(max(height * a, 26), 50), height: height)
    }

    var body: some View {
        Canvas { context, canvasSize in
            let frame = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(
                Path(roundedRect: frame, cornerRadius: 2),
                with: .foreground, lineWidth: 1)
            let area = frame.insetBy(dx: 1.5, dy: 1.5)
            // Yalnız masaüstü: düzen yok, kesikli iç çerçeve.
            if layout.isDesktopOnly {
                context.stroke(Path(roundedRect: area.insetBy(dx: 1, dy: 1), cornerRadius: 1),
                               with: .foreground, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                return
            }
            let inner = layout.rect(in: area, pointsPerUnit: area.width / max(screenSize.width, 1))
            context.fill(Path(roundedRect: inner, cornerRadius: 1), with: .foreground)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Uygulama simgesi

struct AppIcon: View {

    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.icon(for: bundleID) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}
