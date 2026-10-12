import SwiftUI

// MARK: - Pencere davranışı

/// Bir canlı pencerenin haritadaki davranışı: tıklama, pin düğmesi,
/// sürükle-bırak ve "Gönder". Liste satırı (`WindowRow`) ile görsel
/// haritadaki kutu (`CardScreen`) aynı işi yapsın diye tek yerde.
@MainActor
struct WindowActions {

    let window: Router.WindowSnapshot
    let mode: Mode
    let store: Store
    let router: Router
    let ui: UIState
    let screens: ScreenService

    var isLive: Bool { mode == screens.mode }

    /// Bu pencereye uyan ve bu modda hedefi olan kural; router ile aynı
    /// seçim. Oturum pini ayrı tutulduğu için burada verilmez.
    var pinnedRule: Rule? {
        Routing.select(rules: store.document.rules, sessionPins: [:], mode: mode,
                       windowID: window.id, bundleID: window.bundleID,
                       appName: window.appName, title: window.title, document: window.document)?.rule
    }

    /// Bu pencerenin kimliğine bağlı oturum pini (kalıcı kuraldan önce gelir).
    var sessionPin: Destination? { router.sessionPins[window.id] }

    var isPinned: Bool { sessionPin != nil || pinnedRule != nil }
    var isDrafting: Bool { ui.pinDraft?.window.id == window.id }

    /// Gösterilen hedef: oturum pini varsa onun, yoksa kuralın.
    var pinnedDestination: Destination? { sessionPin ?? pinnedRule?[mode] }

    /// Hedef masaüstü bu ekranda yoksa router'ın kırptığı sayı.
    var clampedDesktop: Int? {
        pinnedDestination.flatMap {
            MissingDesktopBadge.clamped(for: $0, desktopCounts: ui.desktopCounts, isLive: isLive)
        }
    }

    /// Serbest hareket süresi sürüyorsa bitiş anı (yalnız pinli pencerede anlamlı).
    var freeUntil: Date? {
        guard isPinned, let until = router.freeMoves[window.id], until > Date() else { return nil }
        return until
    }

    /// "Neden burada?": eşleşen kural (ya da oturum pini) ve hedefi.
    var whyHere: String? {
        let match = Routing.select(
            rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
            windowID: window.id, bundleID: window.bundleID,
            appName: window.appName, title: window.title, document: window.document)
        let name = match.flatMap { m in screens.screens.first { $0.id == m.destination.screen }?.name }
        return Routing.explanation(for: match, screenName: name)
    }

    var rowHelp: String {
        if isPinned {
            return L("Click to change the layout; drag to change the pin's target; double-click to go to the window; ⌘-click to select several")
        }
        if isLive {
            return L("Drag to move (does not pin); click the pin to keep it here; double-click to go to the window; ⌘-click to select several")
        }
        return L("Drag onto a desktop to pin it for %@; the window is not moved", mode.title)
    }

    var pinButtonHelp: String {
        if sessionPin != nil {
            return L("Temporary pin (this window only, this session). Click to remove.")
        }
        return isPinned
            ? L("Pinned: %@. Click to remove.", pinnedRule?.title ?? "")
            : (isLive ? L("Pin to this desktop") : L("Pin for %@", mode.title))
    }

    /// Tek tıklama (hemen işlenir; çift tıklamada `UIState.handleClick` geri alır).
    func click(isGhost: Bool) {
        // ⌘-tıklama: toplu pinleme için seçime ekle/çıkar.
        if ui.commandAtMouseDown, !isGhost, isLive,
           window.placement != nil, window.fullscreen == nil {
            ui.panel = nil
            if ui.selection.contains(window.id) {
                ui.selection.remove(window.id)
            } else {
                ui.selection.insert(window.id)
            }
            return
        }
        // Düz tıklama çoklu seçimi bırakır; yoksa açılan panel çubuğun
        // arkasında kalırdı.
        ui.selection = []
        // Pinli satıra tıklamak düzen panelini açar (tekrar tıklamak kapatır).
        if sessionPin != nil {
            ui.toggle(.session(window.id))
        } else if let rule = pinnedRule {
            ui.toggle(.rule(rule.id), from: window.id)
        } else if !isGhost, window.fullscreen == nil {
            // Pinsiz satır: pin düğmesiyle aynı taslak (tekrar tıklamak kapatır).
            togglePin()
        }
    }

    func togglePin() {
        let wasDrafting = isDrafting
        ui.panel = nil
        if sessionPin != nil {
            router.unpinSession(window.id)
        } else if let rule = pinnedRule {
            store.unpin(rule.id, mode: mode)
        } else if !wasDrafting,
                  let target = WindowRow.draftTarget(window.placement, isLive: isLive,
                                                     screens: store.screens(for: mode)) {
            ui.panel = .pin(PinDraft(window: window, target: target, followsWindow: isLive))
        }
    }

    /// Pinin bu moddaki hedefini değiştirir (düzen korunur, geri alınabilir);
    /// canlı modda pencere kural değişikliğiyle birlikte taşınır.
    func send(to placement: Router.Placement) {
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

    func dragChanged(to location: CGPoint) {
        if ui.drag == nil { ui.holdFocusForDrag() }
        ui.drag = ChipDrag(item: .window(window.id), location: location,
                           hover: ui.target(at: location))
    }

    func dragEnded(at location: CGPoint) {
        defer { ui.drag = nil }
        guard let target = ui.target(at: location) else { return }
        // Hiçbir şey yapmayacak bırakma (pinsiz pencereyi tepsiye ya da
        // olduğu masaüstüne, tam ekran/yersiz pencereyi bir yere) açık
        // paneli de kapatmaz.
        if sessionPin == nil, pinnedRule == nil,
           !WindowRow.unpinnedDropActs(target, window: window, isLive: isLive) {
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
                let next = Destination(screen: screen, desktop: desktop, layout: current.layout)
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
                    to: Destination(screen: screen, desktop: desktop, layout: current.layout),
                    mode: mode)
                ui.panel = nil
            } else if !isLive {
                // Diğer kurulumun haritası: pencere şimdi taşınmaz,
                // o kurulum için pin taslağı açılır.
                ui.panel = .pin(PinDraft(window: window, target: placement, followsWindow: false))
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

/// Pencere satırının ve kutusunun ortak jestleri: tıklama / çift tıklama
/// (pencereye git), sürükleme ve sağ tık menüsü.
struct WindowInteractions: ViewModifier {

    let window: Router.WindowSnapshot
    let mode: Mode
    var isGhost = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    /// Haritanın her ekran için gösterdiği masaüstü satırı sayısı ("Gönder" menüsü).
    @Environment(\.mapTileCounts) private var tileCounts
    @Environment(\.dismiss) private var dismiss

    private var actions: WindowActions {
        WindowActions(window: window, mode: mode, store: store, router: router, ui: ui,
                      screens: screens)
    }

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                ui.handleClick(single: { actions.click(isGhost: isGhost) }, double: {
                    // Çift tıklama: harita kapanır, pencere öne gelir, masaüstüne
                    // geçilir. Harita odak gidince kendiliğinden kapanmıyor; `dismiss`
                    // simgenin durumunu da günceller (`close()`/`hide` sonraki tıkı
                    // boşa düşürüyor; ölçüldü 07.10).
                    guard !isGhost else { return }
                    dismiss()
                    AX.focus(windowID: window.id, pid: window.pid)
                })
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
                    .onChanged { actions.dragChanged(to: $0.location) }
                    .onEnded { actions.dragEnded(at: $0.location) },
                including: isGhost ? .none : .all)
            .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        let actions = actions
        if !isGhost, actions.isPinned { sendMenu(actions) }
        if !isGhost, actions.isPinned, actions.isLive, window.fullscreen == nil { freeMoveMenu }
        // Sabit olmayan pencere: pin düğmesiyle aynı taslak (sağda açılır).
        if !isGhost, !actions.isPinned, window.fullscreen == nil,
           !actions.isLive || window.placement != nil {
            Button(actions.pinButtonHelp + "…") { actions.togglePin() }
        }
    }

    // MARK: Serbest hareket menüsü

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

    // MARK: "Gönder" menüsü

    /// Sağ tık menüsündeki hedef listesi: haritadaki her ekran ve masaüstleri,
    /// pinin şu anki hedefi işaretli. Tam ekran pencerede devre dışı.
    @ViewBuilder private func sendMenu(_ actions: WindowActions) -> some View {
        let targets = WindowRow.sendTargets(screens: store.screens(for: mode),
                                            tileCounts: tileCounts,
                                            current: actions.pinnedDestination)
        Menu(L("Send to")) {
            if actions.sessionPin == nil, let rule = actions.pinnedRule {
                // Kural birden çok pencereye uyabilir: taşınan kuralın kendisi.
                Section(rule.isAppWide ? L("Moves the pin for all %@ windows", rule.appName)
                                       : L("Moves the pin \"%@\" (all matching windows)", rule.title)) {
                    targetButtons(targets, actions)
                }
            } else {
                targetButtons(targets, actions)
            }
        }
        .disabled(window.fullscreen != nil || targets.isEmpty)
    }

    @ViewBuilder private func targetButtons(_ targets: [WindowRow.SendTargetScreen],
                                            _ actions: WindowActions) -> some View {
        // Önce adlar (B 17): ada gönderilen pin o adı izler.
        let named = store.namedPlaces(mode: mode)
        if !named.isEmpty {
            ForEach(named, id: \.id) { item in
                let current = actions.pinnedDestination?.nameID == item.id
                MenuCheck(item.name, checked: current) {
                    actions.send(to: Router.Placement(screen: item.place.screen,
                                                      desktop: item.place.desktop))
                }
                .disabled(current)
            }
            Divider()
        }
        ForEach(targets, id: \.screen) { target in
            Menu(target.name) {
                ForEach(target.desktops, id: \.desktop) { item in
                    let title = store.desktopName(screen: target.screen, desktop: item.desktop, mode: mode)
                        .map { "\(item.desktop) · \($0)" } ?? L("Desktop %ld", item.desktop)
                    MenuCheck(title, checked: item.isCurrent) {
                        actions.send(to: Router.Placement(screen: target.screen, desktop: item.desktop))
                    }
                    .disabled(item.isCurrent)
                }
            }
        }
    }
}

// MARK: - Pin çipi davranışı

/// Pin çipinin ve görsel haritada kuralı temsil eden kutunun ortak
/// jestleri: tıklama paneli açar, çift tıklama penceresini açar (ya da
/// ona gider), sürükleme hedefi taşır, tepsiye bırakmak pini kaldırır.
struct RuleInteractions: ViewModifier {

    let rule: Rule
    let mode: Mode
    var isGhost = false
    /// Sürükleme "Kurulumlar arasında farklı" kutusundan başlıyor: kutuya
    /// geri bırakmak pini kaldırmaz.
    var inTray = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                ui.handleClick(single: { ui.toggle(.rule(rule.id)) }, double: reopen)
            }
            .gesture(dragGesture, including: isGhost ? .none : .all)
    }

    /// Çift tıklama: kapalı pencereyi açar (hatırlanan dosya/klasör/sayfa
    /// ya da yalnız uygulama); Router onu pinli masaüstüne yerleştirir.
    /// Penceresi açıksa (gölgede kalan pin) ona gidilir.
    private func reopen() {
        guard !isGhost else { return }
        if let window = ui.windows.first(where: {
            rule.matches($0)
        }) {
            dismiss()
            AX.focus(windowID: window.id, pid: window.pid)
            return
        }
        let target = router.reopenTargets[rule.id]
        if Reopen.isSafari(rule) {
            dismiss()
            let rule = rule, router = router, store = store
            let destination = rule[screens.mode]
            Task {
                if await !Reopen.openSafari(rule: rule, target: target,
                                             destination: destination, router: router) {
                    store.report(L("Could not open a %@ window", rule.appName))
                }
            }
            return
        }
        switch Reopen.open(rule: rule, target: target) {
        case .opened:
            dismiss()
        case .appOnly:
            store.report(L("%@ is open, but Deskmap does not know this window's file or folder yet. Open it once; after that a double-click opens it.", rule.appName))
        case .noApp:
            store.report(L("Could not find the app %@", rule.appName))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
            .onChanged { value in
                if ui.drag == nil { ui.holdFocusForDrag() }
                ui.drag = ChipDrag(
                    item: .rule(rule.id),
                    location: value.location,
                    hover: ui.target(at: value.location),
                    fromTray: inTray)
            }
            .onEnded { value in
                defer { ui.drag = nil }
                guard let target = ui.target(at: value.location) else { return }
                switch target {
                case .desktop(let screen, let desktop):
                    let layout = rule[mode]?.layout ?? .full
                    store.moveRule(
                        rule.id,
                        to: Destination(screen: screen, desktop: desktop, layout: layout),
                        mode: mode)
                case .tray:
                    // Kutudan başlayıp kutuya bırakılan çip: vazgeçildi.
                    guard !inTray else { return }
                    store.unpin(rule.id, mode: mode)
                }
            }
    }
}
