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

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    /// Haritanın her ekran için gösterdiği masaüstü satırı sayısı ("Gönder" menüsü).
    @Environment(\.mapTileCounts) private var tileCounts
    @Environment(\.dismiss) private var dismiss

    /// Bu pencereye uyan ve bu modda hedefi olan kural; router ile aynı
    /// seçim. Oturum pini ayrı tutulduğu için burada verilmez.
    private var pinnedRule: Rule? {
        Routing.select(rules: store.document.rules, sessionPins: [:], mode: mode,
                       windowID: window.id, bundleID: window.bundleID,
                       appName: window.appName, title: window.title, document: window.document)?.rule
    }

    /// Bu pencerenin kimliğine bağlı oturum pini (kalıcı kuraldan önce gelir).
    private var sessionPin: Destination? { router.sessionPins[window.id] }

    private var isPinned: Bool { sessionPin != nil || pinnedRule != nil }
    private var isDrafting: Bool { ui.pinDraft?.window.id == window.id }
    private var isSelected: Bool {
        if sessionPin != nil { return ui.panel == .session(window.id) }
        return pinnedRule.map { ui.panel == .rule($0.id) } ?? false
    }
    /// Satırda gösterilen hedef: oturum pini varsa onun, yoksa kuralın.
    private var pinnedDestination: Destination? {
        sessionPin ?? pinnedRule?[mode]
    }
    private var pinnedLayout: WindowLayout? { pinnedDestination?.layout }
    /// Hedef masaüstü bu ekranda yoksa router'ın kırptığı sayı (canlı
    /// pencereler yalnızca şu anki modda listelenir; yine de mod denetlenir).
    private var clampedDesktop: Int? {
        pinnedDestination.flatMap {
            MissingDesktopBadge.clamped(for: $0, desktopCounts: ui.desktopCounts,
                                        isLive: mode == screens.mode)
        }
    }
    /// "Neden burada?": eşleşen kural (ya da oturum pini) ve hedefi.
    private var whyHere: String? {
        let match = Routing.select(
            rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
            windowID: window.id, bundleID: window.bundleID,
            appName: window.appName, title: window.title, document: window.document)
        let name = match.flatMap { m in screens.screens.first { $0.id == m.destination.screen }?.name }
        return Routing.explanation(for: match, screenName: name)
    }
    private var isMultiSelected: Bool { !isGhost && ui.selection.contains(window.id) }
    private var isBeingDragged: Bool { !isGhost && ui.drag?.item == .window(window.id) }

    var body: some View {
        HStack(spacing: 6) {
            if showsApp {
                AppIcon(bundleID: window.bundleID, size: 16)
                Text(window.appName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            if isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
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
                .help(whyHere ?? window.title)

            Spacer(minLength: 4)

            if let destination = pinnedDestination, let real = clampedDesktop {
                MissingDesktopBadge(wanted: destination.desktop, real: real)
            }

            if isPinned, let until = router.freeMoves[window.id] {
                FreeMoveBadge(until: until)
            }

            if let layout = pinnedLayout {
                LayoutGlyph(layout: layout, size: CGSize(width: 14, height: 10),
                            screenSize: store.screenSize(of: pinnedDestination?.screen ?? ""))
                    .foregroundStyle(.tertiary)
                    .help(L("Layout: %@", layout.label))
            }

            Button {
                togglePin()
            } label: {
                Image(systemName: pinSymbol)
                    .font(.system(size: sessionPin != nil ? 13 : 11))
                    .foregroundStyle(pinColor)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(pinButtonHelp)
            .accessibilityLabel(pinButtonHelp)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowFill))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(rowStroke, lineWidth: 1))
        .contentShape(Rectangle())
        .opacity(isBeingDragged ? 0.35 : 1)
        .onTapGesture(count: 2) {
            // Çift tıklama: harita kapanır, pencere öne gelir, masaüstüne
            // geçilir. Harita odak gidince kendiliğinden kapanmıyor; `dismiss`
            // simgenin durumunu da günceller (`close()`/`hide` sonraki tıkı
            // boşa düşürüyor; ölçüldü 07.10).
            guard !isGhost else { return }
            dismiss()
            AX.focus(windowID: window.id, pid: window.pid)
        }
        .onTapGesture {
            // ⌘-tıklama: toplu pinleme için seçime ekle/çıkar.
            if ui.commandAtMouseDown, !isGhost, mode == screens.mode,
               window.placement != nil, window.fullscreen == nil {
                ui.panel = nil
                if ui.selection.contains(window.id) {
                    ui.selection.remove(window.id)
                } else {
                    ui.selection.insert(window.id)
                }
                return
            }
            // Pinli satıra tıklamak düzen panelini açar (tekrar tıklamak kapatır).
            if sessionPin != nil {
                ui.toggle(.session(window.id))
            } else if let rule = pinnedRule {
                ui.toggle(.rule(rule.id), from: window.id)
            }
        }
        .gesture(dragGesture, including: isGhost ? .none : .all)
        .contextMenu {
            if !isGhost, isPinned { sendMenu }
            if !isGhost, isPinned, mode == screens.mode, window.fullscreen == nil { freeMoveMenu }
            // Sabit olmayan pencere: pin düğmesiyle aynı taslak (sağda açılır).
            if !isGhost, !isPinned, window.fullscreen == nil,
               mode != screens.mode || window.placement != nil {
                Button(pinButtonHelp + "…") { togglePin() }
            }
        }
        .help(rowHelp)
        .searchLook(dimmed: searchLook.dimmed, highlighted: searchLook.highlighted)
    }

    private var searchLook: (dimmed: Bool, highlighted: Bool) {
        isGhost ? (false, false) : ui.searchLook(appName: window.appName, title: window.title)
    }

    // Derleyici tür denetimi zaman aşımına düşmesin diye `body` dışında.
    private var rowFill: Color {
        if isMultiSelected { return Color.accentColor.opacity(0.28) }
        if isDrafting || isSelected { return Color.accentColor.opacity(0.18) }
        return Color(nsColor: .controlBackgroundColor).opacity(isGhost ? 1 : 0.7)
    }

    private var rowStroke: Color {
        if isDrafting || isSelected || isMultiSelected { return Color.accentColor }
        if sessionPin != nil { return Color.orange.opacity(0.5) }
        return isPinned ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }

    private var pinSymbol: String {
        sessionPin != nil ? "pin.circle.fill" : (isPinned ? "pin.fill" : "pin")
    }

    private var pinColor: Color {
        if sessionPin != nil { return Color.orange }
        return isPinned ? Color.accentColor : Color.secondary.opacity(0.6)
    }

    private var rowHelp: String {
        if isPinned {
            return L("Click to change the layout; drag to change the pin's target; double-click to go to the window; ⌘-click to select several")
        }
        if mode == screens.mode {
            return L("Drag to move (does not pin); click the pin to keep it here; double-click to go to the window; ⌘-click to select several")
        }
        return L("Drag onto a desktop to pin it for %@; the window is not moved", mode.title)
    }

    // MARK: - Serbest hareket menüsü

    /// Sağ tık: sabit pencereyi bir süre serbest bırak; serbestse bitir.
    @ViewBuilder private var freeMoveMenu: some View {
        if let until = router.freeMoves[window.id], until > Date() {
            Button(L("End free movement; the window goes back to its pin")) {
                router.endFreeMove([window.id])
            }
        } else {
            Menu(L("Free move")) {
                ForEach(Router.freeMoveDurations, id: \.self) { duration in
                    Button(FreeMoveRow.label(duration)) {
                        router.allowFreeMove([window.id], for: duration)
                    }
                }
            }
        }
    }

    // MARK: - "Gönder" menüsü

    /// Sağ tık menüsündeki hedef listesi: haritadaki her ekran ve masaüstleri,
    /// pinin şu anki hedefi işaretli. Tam ekran pencerede devre dışı.
    @ViewBuilder private var sendMenu: some View {
        let targets = Self.sendTargets(screens: store.screens(for: mode),
                                       tileCounts: tileCounts, current: pinnedDestination)
        Menu(L("Send to")) {
            if sessionPin == nil, let rule = pinnedRule {
                // Kural birden çok pencereye uyabilir: taşınan kuralın kendisi.
                Section(rule.isAppWide ? L("Moves the pin for all %@ windows", rule.appName)
                                       : L("Moves the pin \"%@\" (all matching windows)", rule.title)) {
                    targetButtons(targets)
                }
            } else {
                targetButtons(targets)
            }
        }
        .disabled(window.fullscreen != nil || targets.isEmpty)
    }

    @ViewBuilder private func targetButtons(_ targets: [SendTargetScreen]) -> some View {
        ForEach(targets, id: \.screen) { target in
            Menu(target.name) {
                ForEach(target.desktops, id: \.desktop) { item in
                    let title = store.desktopName(screen: target.screen, desktop: item.desktop, mode: mode)
                        .map { "\(item.desktop) · \($0)" } ?? L("Desktop %ld", item.desktop)
                    MenuCheck(title, checked: item.isCurrent) {
                        send(to: Router.Placement(screen: target.screen, desktop: item.desktop))
                    }
                    .disabled(item.isCurrent)
                }
            }
        }
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

    /// Pinin bu moddaki hedefini değiştirir (düzen korunur, geri alınabilir);
    /// canlı modda pencere kural değişikliğiyle birlikte taşınır.
    private func send(to placement: Router.Placement) {
        guard window.fullscreen == nil else { return }
        switch ui.panel {
        case .rule, .session: ui.panel = nil
        default: break
        }
        if let current = sessionPin {
            let next = Destination(screen: placement.screen, desktop: placement.desktop,
                                   layout: current.layout)
            guard next != current else { return }
            router.pinSession(window.id, destination: next)
            let router = router, id = window.id
            store.recordSessionChange(L("Temporary pin moved")) {
                if router.sessionPins[id] != nil { router.pinSession(id, destination: current) }
            }
        } else if let rule = pinnedRule, let current = rule[mode] {
            let next = Destination(screen: placement.screen, desktop: placement.desktop,
                                   layout: current.layout)
            guard next != current else { return }
            store.moveRule(rule.id, to: next, mode: mode)
        }
    }

    private var pinButtonHelp: String {
        if sessionPin != nil {
            return L("Temporary pin (this window only, this session). Click to remove.")
        }
        return isPinned
            ? L("Pinned: %@. Click to remove.", pinnedRule?.title ?? "")
            : (mode == screens.mode ? L("Pin to this desktop") : L("Pin for %@", mode.title))
    }

    private func togglePin() {
        let wasDrafting = isDrafting
        ui.panel = nil
        if sessionPin != nil {
            router.unpinSession(window.id)
        } else if let rule = pinnedRule {
            store.unpin(rule.id, mode: mode)
        } else if !wasDrafting,
                  let target = Self.draftTarget(window.placement, isLive: mode == screens.mode,
                                                screens: store.screens(for: mode)) {
            ui.panel = .pin(PinDraft(window: window, target: target,
                                     followsWindow: mode == screens.mode))
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
            .onChanged { value in
                if ui.drag == nil { ui.holdFocusForDrag() }
                ui.drag = ChipDrag(
                    item: .window(window.id),
                    location: value.location,
                    hover: ui.target(at: value.location))
            }
            .onEnded { value in
                defer { ui.drag = nil }
                guard let target = ui.target(at: value.location) else { return }
                // Hiçbir şey yapmayacak bırakma (pinsiz pencereyi tepsiye ya da
                // olduğu masaüstüne, tam ekran/yersiz pencereyi bir yere) açık
                // paneli de kapatmaz.
                if sessionPin == nil, pinnedRule == nil,
                   !Self.unpinnedDropActs(target, window: window, isLive: mode == screens.mode) {
                    return
                }
                // Bilgi panelleri kapanır; başka pencerenin pin taslağı ve
                // profil paneli tek seferlik taşımadan etkilenmez.
                switch ui.panel {
                case .rule, .session: ui.panel = nil
                default: break
                }
                switch target {
                case .desktop(let screen, let desktop):
                    let placement = Router.Placement(screen: screen, desktop: desktop)
                    if let current = sessionPin {
                        // Oturum pini: hedef doğrudan güncellenir; geri alma
                        // pin hâlâ duruyorsa eski hedefe döndürür (pencere
                        // kapanıp pin düştüyse dokunmaz).
                        let next = Destination(screen: screen, desktop: desktop,
                                               layout: current.layout)
                        router.pinSession(window.id, destination: next)
                        if next != current {
                            let router = router, id = window.id
                            store.recordSessionChange(L("Temporary pin moved")) {
                                if router.sessionPins[id] != nil {
                                    router.pinSession(id, destination: current)
                                }
                            }
                        }
                        ui.panel = nil
                    } else if let rule = pinnedRule, let current = rule[mode] {
                        // Pinli pencere: hedef doğrudan güncellenir (geri alınabilir).
                        store.moveRule(
                            rule.id,
                            to: Destination(screen: screen, desktop: desktop,
                                            layout: current.layout),
                            mode: mode)
                        ui.panel = nil
                    } else if mode != screens.mode {
                        // Diğer kurulumun haritası: pencere şimdi taşınmaz,
                        // o kurulum için pin taslağı açılır.
                        ui.panel = .pin(PinDraft(window: window, target: placement,
                                                 followsWindow: false))
                    } else if placement != window.placement,
                              window.fullscreen == nil, window.placement != nil {
                        // Pinsiz pencere: tek seferlik taşınır, kural yazılmaz.
                        // Tam ekran ya da yeri bilinmeyen pencereye dokunulmaz.
                        router.moveWindow(window.id, to: placement)
                        // Bu pencerenin açık taslağı yeni masaüstünü hedefler;
                        // eski hedefle Pin pencereyi geri çekerdi.
                        if var draft = ui.pinDraft, draft.window.id == window.id {
                            draft.target = placement
                            ui.panel = .pin(draft)
                        }
                    }
                case .tray:
                    // Yalnız bir pin kalktıysa panel kapanır; pinsiz pencere
                    // bırakıldığında açık taslak/panel korunur.
                    if sessionPin != nil {
                        router.unpinSession(window.id)
                        ui.panel = nil
                    } else if let rule = pinnedRule {
                        store.unpin(rule.id, mode: mode)
                        ui.panel = nil
                    }
                }
            }
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
