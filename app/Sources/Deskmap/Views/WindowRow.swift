import SwiftUI

/// Canlı bir pencere satırı: başlık ve pin düğmesi. Sürüklenerek başka
/// masaüstüne taşınır; pinsiz pencere yalnızca taşınır (kural yazılmaz),
/// pinli pencerenin hedefi güncellenir. Pinleme yalnızca pin düğmesiyle.
struct WindowRow: View {

    let window: Router.WindowSnapshot
    let mode: Mode
    /// Tek pencereli uygulamada simge + ad satırda gösterilir; gruplu
    /// uygulamada başlık satırı zaten gösterdiği için gizlenir.
    var showsApp = true
    var isGhost = false
    /// Başlığın altında küçük ikinci satır (ör. kenar çubuğunda "şu an: …").
    var location: String?

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState

    /// Tıklama, sürükleme ve menülerin ortak davranışı (`WindowActions`).
    private var actions: WindowActions {
        WindowActions(window: window, mode: mode, store: store, router: router, ui: ui,
                      screens: screens)
    }

    private var isSelected: Bool {
        let actions = actions
        if actions.sessionPin != nil { return ui.panel == .session(window.id) }
        return actions.pinnedRule.map { ui.panel == .rule($0.id) } ?? false
    }
    private var isMultiSelected: Bool { !isGhost && ui.selection.contains(window.id) }
    private var isBeingDragged: Bool { !isGhost && ui.drag?.item == .window(window.id) }

    var body: some View {
        let actions = actions
        VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
            if showsApp {
                // Seçim işareti simgenin köşesinde: satırda yer kaplamaz,
                // ⌘-tıklama başlığı kaydırmaz.
                AppIcon(bundleID: window.bundleID, size: 16)
                    .overlay(alignment: .bottomTrailing) {
                        if isMultiSelected { selectionMark(size: 9).offset(x: 3, y: 3) }
                    }
                Text(window.appName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if window.isMinimized {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help(L("Minimized"))
            }
            Text(window.title.isEmpty ? L("Untitled window") : window.title)
                .font(.caption)
                .foregroundStyle(window.title.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(actions.whyHere ?? window.title)

            Spacer(minLength: 4)

            if let destination = actions.pinnedDestination, let real = actions.clampedDesktop {
                MissingDesktopBadge(wanted: destination.desktop, real: real)
            }

            if actions.isPinned, let until = router.freeMoves[window.id] {
                FreeMoveBadge(until: until)
            }

            if let destination = actions.pinnedDestination {
                LayoutGlyph(layout: destination.layout, size: CGSize(width: 14, height: 10),
                            screenSize: store.screenSize(of: destination.screen))
                    .foregroundStyle(.tertiary)
                    .help(L("Layout: %@", destination.layout.label))
            }

            Button {
                actions.togglePin()
            } label: {
                Image(systemName: pinSymbol(actions))
                    .font(.system(size: actions.sessionPin != nil ? 13 : 11))
                    .foregroundStyle(pinColor(actions))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(actions.pinButtonHelp)
            .accessibilityLabel(actions.pinButtonHelp)
        }
            // İkinci satır satırın tamamını kullanır (dar kenar çubuğunda
            // başlığın yanına sıkışmaz); simgenin hizasından başlar.
            if let location {
                Text(location)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, showsApp ? 22 : 0)
                    .padding(.trailing, 24)
                    .help(location)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            // Gruplu satırda simge yok: işaret grubun 16 pt'lik girintisinde.
            if !showsApp, isMultiSelected { selectionMark(size: 12).offset(x: -15) }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill(actions)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(rowStroke(actions), lineWidth: 1))
        .contentShape(Rectangle())
        .opacity(isBeingDragged ? 0.35 : 1)
        .modifier(WindowInteractions(window: window, mode: mode, isGhost: isGhost))
        .help(actions.rowHelp)
        .searchLook(dimmed: searchLook.dimmed, highlighted: searchLook.highlighted)
    }

    private var searchLook: (dimmed: Bool, highlighted: Bool) {
        isGhost ? (false, false) : ui.searchLook(appName: window.appName, title: window.title)
    }

    private func selectionMark(size: CGFloat) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size))
            .foregroundStyle(Color.white, Color.accentColor)
    }

    // Derleyici tür denetimi zaman aşımına düşmesin diye `body` dışında.
    private func rowFill(_ actions: WindowActions) -> Color {
        if isMultiSelected { return Color.accentColor.opacity(0.28) }
        if actions.isDrafting || isSelected { return Color.accentColor.opacity(0.18) }
        return Color(nsColor: .controlBackgroundColor).opacity(isGhost ? 1 : 0.7)
    }

    private func rowStroke(_ actions: WindowActions) -> Color {
        if actions.isDrafting || isSelected || isMultiSelected { return Color.accentColor }
        if actions.sessionPin != nil { return Color.orange.opacity(0.5) }
        return actions.isPinned ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }

    private func pinSymbol(_ actions: WindowActions) -> String {
        actions.sessionPin != nil ? "pin.circle.fill" : (actions.isPinned ? "pin.fill" : "pin")
    }

    private func pinColor(_ actions: WindowActions) -> Color {
        if actions.sessionPin != nil { return Color.orange }
        return actions.isPinned ? Color.accentColor : Color.secondary.opacity(0.6)
    }

    /// Menüde bir ekranın hedefleri.
    struct SendTargetScreen: Equatable {
        struct Desktop: Equatable { var desktop: Int; var isCurrent: Bool }
        var screen: String
        var name: String
        var desktops: [Desktop]
    }

    /// "Gönder" hedefleri (saf): haritanın sırasıyla ekranlar, her biri
    /// haritadaki satır sayısı kadar masaüstü (en az 1; hedef daha ilerideyse
    /// o da listelenir), şu anki hedef işaretli.
    static func sendTargets(screens: [KnownScreen], tileCounts: [String: Int],
                            current: Destination?) -> [SendTargetScreen] {
        screens.map { screen in
            var count = max(tileCounts[screen.id] ?? 1, 1)
            if let current, current.screen == screen.id { count = max(count, current.desktop) }
            return SendTargetScreen(
                screen: screen.id, name: screen.name,
                desktops: (1...count).map {
                    .init(desktop: $0,
                          isCurrent: current?.screen == screen.id && current?.desktop == $0)
                })
        }
    }

    /// Pinsiz pencerenin bırakılması bir şey yapar mı (saf): diğer kurulumda
    /// masaüstüne bırakmak taslak açar; canlı kurulumda yalnız başka bir
    /// masaüstüne ve tam ekran/yersiz olmayan pencere taşınır; tepsi hiçbir
    /// şey yapmaz.
    static func unpinnedDropActs(_ target: DropTarget, window: Router.WindowSnapshot,
                                 isLive: Bool) -> Bool {
        guard case .desktop(let screen, let desktop) = target else { return false }
        if !isLive { return true }
        return window.fullscreen == nil && window.placement != nil
            && window.placement != Router.Placement(screen: screen, desktop: desktop)
    }

    /// Pin düğmesiyle açılan taslağın hedefi (saf): canlı kurulumda
    /// pencerenin bulunduğu yer; diğer kurulumda o yer o kurulumda da varsa
    /// orası, yoksa kurulumun ilk ekranının ilk masaüstü.
    static func draftTarget(_ placement: Router.Placement?, isLive: Bool,
                            screens: [KnownScreen]) -> Router.Placement? {
        if isLive { return placement }
        if let placement, screens.contains(where: { $0.id == placement.screen }) {
            return placement
        }
        return screens.first.map { Router.Placement(screen: $0.id, desktop: 1) }
    }
}

private struct MapTileCountsKey: EnvironmentKey {
    static let defaultValue: [String: Int] = [:]
}

extension EnvironmentValues {
    /// Ekran haritasının ekran başına gösterdiği masaüstü satırı sayısı.
    var mapTileCounts: [String: Int] {
        get { self[MapTileCountsKey.self] }
        set { self[MapTileCountsKey.self] = newValue }
    }
}
