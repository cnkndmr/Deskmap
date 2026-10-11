import SwiftUI

// MARK: - Masaüstü satırı

/// Masaüstü etiketi: ad varsa ad (iki satıra kadar) ve altında küçük
/// numara, yoksa "Masaüstü N". `inline` (kart başlığı): "Masaüstü N" ve
/// yanında tek satır ad.
struct DesktopLabel: View {
    let desktop: Int
    let name: String?
    let exists: Bool
    var inline = false

    var body: some View {
        if inline {
            HStack(spacing: 6) {
                Text(L("Desktop %ld", desktop))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(exists ? .primary : .tertiary)
                    .lineLimit(1)
                    .fixedSize()
                if let name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(exists ? .secondary : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(name)
                }
            }
        } else if let name {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(exists ? .primary : .tertiary)
                    .lineLimit(2)
                Text(L("Desktop %ld", desktop))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text(L("Desktop %ld", desktop))
                .font(.caption.weight(.medium))
                .foregroundStyle(exists ? .secondary : .tertiary)
        }
    }
}

/// Bir masaüstü: Liste görünümünde tam genişlikte satır (solda numara ve
/// küçük önizleme, sağda uygulama başına gruplanmış pencereler ve penceresi
/// kapalı pinler), Görsel görünümde kart (`asCard`: başlık, pencerelerin
/// kendi yerinde çizildiği küçük ekran, altında kapalı pinler). İki biçim
/// aynı veriyi, jestleri ve menüleri paylaşır.
struct DesktopRow: View {

    let screen: KnownScreen
    let desktop: Int
    let mode: Mode
    let isLive: Bool
    /// Bağlı ekranda bu masaüstü gerçekten var mı?
    let exists: Bool
    /// Bağlı ekrandaki gerçek masaüstü sayısı (bağlı değilse nil).
    let realCount: Int?
    /// Bu ekran kartındaki satır sayısı (sıralama için).
    let rowCount: Int
    /// Haritadaki her ekranın satır sayısı (ekranlar arası sürükleme için).
    let tileCounts: [String: Int]
    /// Gölgede kalan kural → onu geçen kural; soluk çip olarak gösterilir.
    let shadowed: [String: String]
    /// Ekran kartının ortak etiket sütunu (`ScreenCard.labelWidth`).
    let labelWidth: CGFloat
    /// Görsel görünümün kartı olarak çizilir.
    var asCard = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    /// Ad düzenleniyor mu (etikete çift tıklama ya da sağ tık menüsü).
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private var name: String? { store.desktopName(screen: screen.id, desktop: desktop, mode: mode) }

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    /// `UIState.textEditors` içindeki ad alanı kimliği.
    private var editorID: String { "desktop|\(screen.id)|\(desktop)" }
    private var isTargeted: Bool { ui.drag?.hover == target && acceptsDrag }
    private var placement: Router.Placement {
        Router.Placement(screen: screen.id, desktop: desktop)
    }

    /// Masaüstü sürüklemesi kendi satırına bırakılamaz; başka ekrana olur.
    private var acceptsDrag: Bool {
        if case .desktop(let fromScreen, let from) = ui.drag?.item {
            return ScreenMapView.acceptsDesktopDrop(fromScreen: fromScreen, from: from,
                                           toScreen: screen.id, to: desktop)
        }
        return true
    }
    private var isBeingDragged: Bool {
        ui.drag?.item == .desktop(screen: screen.id, desktop: desktop)
    }

    /// Bu masaüstündeki canlı pencereler (yalnızca şu anki modda).
    private var windows: [Router.WindowSnapshot] {
        guard isLive else { return [] }
        return ui.windows.filter { $0.placement == placement }
    }

    private var groups: [AppGroup] {
        AppGroup.grouped(windows: windows, closed: orphanRules)
    }

    /// Önizlemedeki kutular: açık pencereler (sabitse kayıtlı düzeninde,
    /// değilse şu anki yerinde) ve açık penceresi olmayan sabitlemeler.
    private var previewItems: [DesktopPreview.Item] {
        let openItems: [DesktopPreview.Item] = windows.filter { $0.fullscreen == nil }.map { window in
            let match = Routing.select(
                rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
                windowID: window.id, bundleID: window.bundleID, appName: window.appName,
                title: window.title, document: window.document)
            let current = window.currentLayout(screens: screens.screens) ?? .center
            let layout = match.map { $0.destination.layout.isDesktopOnly ? current : $0.destination.layout }
                ?? current
            let look = ui.searchLook(appName: window.appName, title: window.title)
            return DesktopPreview.Item(
                id: "w\(window.id)", bundleID: window.bundleID,
                title: window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)",
                label: DesktopPreview.label(appName: window.appName, title: window.title),
                layout: layout, pinned: match != nil, isOpen: true,
                isSelected: isShown(window, ruleID: match?.rule?.id),
                dimmed: look.dimmed, highlighted: look.highlighted,
                action: { openPanel(for: window) })
        }
        let closed: [DesktopPreview.Item] = orphanRules.compactMap { rule in
            guard let destination = rule[mode] else { return nil }
            let look = ui.searchLook(appName: rule.appName, title: rule.title)
            return DesktopPreview.Item(
                id: "r\(rule.id)", bundleID: rule.bundleID,
                title: "\(rule.appName) — \(rule.title)",
                label: rule.isAppWide ? rule.appName
                                      : DesktopPreview.label(appName: rule.appName, title: rule.title),
                layout: destination.layout.isDesktopOnly ? .center : destination.layout,
                pinned: true, isOpen: false, isSelected: ui.panel == .rule(rule.id),
                dimmed: look.dimmed, highlighted: look.highlighted,
                action: { ui.toggle(.rule(rule.id)) })
        }
        return closed + openItems
    }

    /// Bu pencerenin paneli açık mı.
    private func isShown(_ window: Router.WindowSnapshot, ruleID: String?) -> Bool {
        switch ui.panel {
        case .session(let id): return id == window.id
        case .pin(let draft): return draft.window.id == window.id
        case .rule(let id): return id == ruleID && (ui.panelSourceWindowID ?? window.id) == window.id
        default: return false
        }
    }

    /// Önizlemedeki kutuya tıklama: satırına tıklanmış gibi panel açılır
    /// (aynısı açıksa kapanır); sabit olmayan pencerede sabitleme taslağı.
    private func openPanel(for window: Router.WindowSnapshot) {
        let sessionPinned = router.sessionPins[window.id] != nil
        let rule = Routing.select(
            rules: store.document.rules, sessionPins: [:], mode: mode,
            windowID: window.id, bundleID: window.bundleID, appName: window.appName,
            title: window.title, document: window.document)?.rule
        guard let panel = UIState.openingPanel(for: window, sessionPinned: sessionPinned,
                                               ruleID: rule?.id) else { return }
        ui.selection = []
        if isShown(window, ruleID: rule?.id) {
            ui.panel = nil
            ui.panelSourceWindowID = nil
        } else {
            ui.panel = panel
            ui.panelSourceWindowID = sessionPinned || rule == nil ? nil : window.id
        }
    }

    /// Hedefi burası olan ama şu an açık penceresi olmayan pinler; canlı
    /// modda ayrıca penceresi olduğu hâlde başka kurala yenilen (gölgede)
    /// pinler, yoksa haritada hiç görünmezlerdi.
    private var orphanRules: [Rule] {
        store.document.rules.filter { rule in
            guard let destination = rule[mode],
                  destination.screen == screen.id, destination.desktop == desktop
            else { return false }
            guard isLive else { return true }
            if shadowed[rule.id] != nil { return true }
            return !ui.windows.contains {
                rule.matches($0)
            }
        }
    }

    var body: some View {
        if asCard { card } else { row }
    }

    /// Satırın / kart başlığının tutamağı: ≡ simgesi, ad (ya da ad alanı).
    /// Çift tıklama ad verir, sürükleme masaüstünü taşır.
    /// `width`: satırda etiket sütununun genişliği; kartta nil (başlığın
    /// kalanını kaplar). Boş yeri de tutulur.
    @ViewBuilder private func handle(inline: Bool, width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            if isRenaming {
                TextField(L("Desktop %ld", desktop), text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onExitCommand { endRenaming() }
                    .onChange(of: nameFocused) { focused in
                        ui.setEditing(editorID, focused)
                        if !focused && isRenaming { commitName() }
                    }
                    // Satır düzenlemedeyken kaybolursa sütun geniş kalmasın, alan da düzenleyici sayılmasın.
                    .onDisappear {
                        ui.setEditing(editorID, false)
                        if isRenaming { endRenaming() }
                    }
            } else {
                DesktopLabel(desktop: desktop, name: name, exists: exists, inline: inline)
            }
        }
        .frame(width: width, alignment: .leading)
        .padding(.top, inline ? 0 : 2)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRenaming() }
        .gesture(desktopDrag, including: isRenaming ? .none : .all)
        .help(L("Double-click to name this desktop; drag to move it (with its pins) up, down or to another display"))
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                handle(inline: false, width: labelWidth)
                // Liste görünümü: satırın solunda küçük önizleme.
                DesktopPreview(screenSize: screen.visibleSize, items: previewItems)
            }

            // Sondaki boşluk yok: satırlar kartın sağ kenarına da 8 pt kalır.
            if groups.isEmpty {
                Text(exists ? L("empty") : L("doesn't exist yet"))
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.18)
                                 : Color.primary.opacity(exists ? 0.05 : 0.02)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                    style: StrokeStyle(lineWidth: 1, dash: exists ? [] : [4, 3])))
        .opacity(isBeingDragged ? 0.4 : 1)
        .dropTarget(target)
        .contextMenu { desktopMenu }
    }

    /// Masaüstünün sağ tık menüsü: ad, başka ekrana gönderme, silme.
    @ViewBuilder private var desktopMenu: some View {
        Button(name == nil ? L("Name Desktop…") : L("Rename Desktop…")) { startRenaming() }
        if name != nil {
            Button(L("Remove Name")) {
                store.setDesktopName(nil, screen: screen.id, desktop: desktop, mode: mode)
            }
        }
        let others = store.screens(for: mode).filter { $0.id != screen.id && tileCounts[$0.id] != nil }
        if !others.isEmpty {
            Divider()
            // Sürükle-bırakla aynı taşıma: masaüstü pencereleri, pinleri
            // ve adıyla hedef ekranın sonuna gider.
            ForEach(others) { other in
                Button(L("Send Desktop to %@", other.name)) {
                    moveAcross(to: other.id, at: (tileCounts[other.id] ?? 0) + 1)
                }
            }
        }
        Divider()
        Button(L("Remove Desktop %ld", desktop), role: .destructive) { remove() }
    }

    /// Kartta pencere listesi açık mı ("+K daha" ya da başlıktaki düğme).
    private var showsList: Bool {
        get { ui.listedDesktops.contains(listKey) }
        nonmutating set {
            if newValue { ui.listedDesktops.insert(listKey) } else { ui.listedDesktops.remove(listKey) }
        }
    }
    private var listKey: String { UIState.listKey(mode: mode, screen: screen.id, desktop: desktop) }

    private var renamingKey: String { "\(mode.rawValue)|\(screen.id)|\(desktop)" }

    private func startRenaming() {
        nameDraft = name ?? ""
        isRenaming = true
        nameFocused = true
        ui.renamingDesktop = renamingKey
    }

    private func endRenaming() {
        isRenaming = false
        // Başka satırda düzenleme başladıysa onunkine dokunma.
        if ui.renamingDesktop == renamingKey { ui.renamingDesktop = nil }
    }

    private func commitName() {
        endRenaming()
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (name ?? "") else { return }
        if !store.setDesktopName(
            trimmed, screen: screen.id, desktop: desktop, mode: mode,
            space: isLive ? router.currentSpace(on: screen.id, desktop: desktop) : nil) {
            store.report(L("A desktop named %@ already exists", trimmed))
        }
    }

    /// Satırı siler; kısıt yok. Etkin modda gerçekte var olan masaüstü
    /// Mission Control ile hemen silinir (pinler kayar); etkin olmayan modda
    /// silme o mod etkinleşince yapılır. Gerçekte olmayan (plan/pin) satırda
    /// yalnız numaralar kayar. Bu ikisi ⌘Z ile geri alınır.
    private func remove() {
        // Bu ekrana açık pin taslağı varsa masaüstü numaraları kayacak:
        // eski numarayla yanlış masaüstüne pin yazılmasın.
        if let draft = ui.pinDraft, draft.target.screen == screen.id { ui.panel = nil }
        let existing = desktop <= (realCount ?? 0)
        let ui = ui, screenID = screen.id, removed = desktop
        // Daraltılmış gruplar numarayla tutulur: silinenin anahtarları düşer,
        // sonrakiler bir yukarı kayar. Gerçek silme Router'da bütün planlarda
        // kayar; öbürü yalnız bu planda.
        let remapCollapsed = { (modes: [Mode]) in
            ui.remapCollapsed(modes: modes) { s, d in
                guard s == screenID, d >= removed else { return (s, d) }
                return d == removed ? nil : (s, d - 1)
            }
        }
        if isLive && existing {
            let router = router, store = store, desktop = desktop
            Task {
                if await router.removeDesktop(on: screenID, desktop: desktop) {
                    remapCollapsed(Mode.allCases)
                } else {
                    store.report(L("Could not remove desktop %ld on %@", desktop, screenID))
                }
            }
            return
        }
        let queued = !isLive && existing
        let space = queued
            ? router.spaceForPendingRemoval(on: screen.id, desktop: desktop, mode: mode) : nil
        // Başka yerde adlı gerçek masaüstü sıraya alınmaz (Store bildirir);
        // reddedilirse daraltılmış gruplar da kaymaz.
        guard !store.refusesPendingRemoval(on: screen.id, desktop: desktop, mode: mode,
                                           existing: queued, space: space) else { return }
        let undoCollapsed = remapCollapsed([mode])
        store.removeDesktopLater(
            on: screen.id, desktop: desktop, mode: mode, existing: queued, space: space,
            undoing: undoCollapsed)
    }

    /// Satırı tutup sürüklemek: bırakılan masaüstü sırasına taşınır, o
    /// ekrandaki pinler yeniden numaralanır; router pencereleri taşır.
    /// Geri alma belgeyle birlikte oturum pinlerini de ters taşımayla
    /// (to → from, aynı satır sayısı) geri getirir.
    private var desktopDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
            .onChanged { value in
                ui.drag = ChipDrag(
                    item: .desktop(screen: screen.id, desktop: desktop),
                    location: value.location,
                    hover: ui.target(at: value.location))
            }
            .onEnded { value in
                defer { ui.drag = nil }
                guard case .desktop(let toScreen, let dropped)? = ui.target(at: value.location)
                else { return }
                if toScreen != screen.id {
                    moveAcross(to: toScreen, at: dropped)
                    return
                }
                // "+ Masaüstü N" satırına bırakmak = en sona.
                let to = min(dropped, rowCount)
                guard to != desktop else { return }
                // Pin hedefleri yeniden numaralanıyor; pin ve taslak panelleri kapanır.
                switch ui.panel {
                case .rule, .pin: ui.panel = nil
                default: break
                }
                let router = router
                let screenID = screen.id, from = desktop, count = rowCount
                // Etkin modda pencereler de taşınır: masaüstü sırası gerçekten değişir.
                let live = isLive
                let liveSpaces = router.reorderedSpaces(on: screenID, from: from, to: to,
                                                        reorderWindows: live)
                let sessionMoved = router.moveDesktop(on: screenID, from: from, to: to, count: count,
                                                      reorderWindows: live)
                // Belgeyle aynı planlar: etkin modda laptop masaüstleri iki planda ortak.
                let modes = live && screenID == "builtin" ? Mode.allCases : [mode]
                let undoCollapsed = Document.desktopMapping(from: from, to: to, count: count)
                    .flatMap { mapping in
                        ui.remapCollapsed(modes: modes) { s, d in
                            s == screenID ? (s, mapping[d] ?? d) : (s, d)
                        }
                    }
                store.moveDesktop(
                    on: screenID, from: from, to: to, count: count, mode: mode, sharedLaptop: live,
                    liveSpaces: liveSpaces,
                    undoingSessionPins: UIState.chain(
                        sessionMoved
                            ? { router.moveDesktop(on: screenID, from: to, to: from, count: count,
                                                   reorderWindows: live) }
                            : nil,
                        undoCollapsed))
            }
    }

    /// Masaüstünü başka ekranın `at` sırasına taşır (bkz.
    /// `Document.moveDesktopAcross`). Etkin modda hedefte bir gerçek
    /// masaüstü eksikse önce Mission Control ile eklenir; eklenemezse hiçbir
    /// şey değişmez. Kaynakta kalan boş gerçek masaüstü silinmez.
    private func moveAcross(to toScreen: String, at dropped: Int) {
        guard let toCount = tileCounts[toScreen] else { return }
        let to = min(max(dropped, 1), toCount + 1)
        switch ui.panel {
        case .rule, .pin: ui.panel = nil
        default: break
        }
        let router = router, store = store, mode = mode, live = isLive, ui = ui
        let fromScreen = screen.id, from = desktop
        let apply = {
            let undoCollapsed = ui.remapCollapsed(modes: [mode]) { s, d in
                Document.acrossPlacement(screen: s, desktop: d, from: fromScreen, desktop: from,
                                         to: toScreen, at: to) ?? (s, d)
            }
            let sessionMoved = router.moveDesktopAcross(
                from: fromScreen, desktop: from, to: toScreen, at: to, moveWindows: live)
            store.moveDesktopAcross(
                from: fromScreen, desktop: from, to: toScreen, at: to, toCount: toCount, mode: mode,
                undoingSessionPins: UIState.chain(
                    sessionMoved
                        ? { router.moveDesktopAcross(from: toScreen, desktop: to, to: fromScreen,
                                                     at: from, moveWindows: live) }
                        : nil,
                    undoCollapsed))
        }
        let real = router.desktopCounts[toScreen] ?? 0
        let missing = live ? Document.desktopsToAddAcross(real: real, at: to) : 0
        guard missing > 0 else { apply(); return }
        Task {
            for _ in 0..<missing {
                guard await router.addDesktop(on: toScreen) else {
                    store.report(L("Could not add a desktop to %@", toScreen))
                    return
                }
            }
            apply()
        }
    }

    @ViewBuilder
    private func groupView(_ group: AppGroup) -> some View {
        if !group.showsHeader {
            if let window = group.windows.first {
                WindowRow(window: window, mode: mode, showsApp: true)
                    .id(WindowAnchor(id: window.id))
            } else if let rule = group.closed.first {
                RuleChip(rule: rule, mode: mode, shadowedBy: shadowed[rule.id])
            }
        } else {
            let key = UIState.collapseKey(mode: mode, screen: screen.id, desktop: desktop,
                                          group: group.id)
            let collapsed = ui.collapsed.contains(key)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if collapsed { ui.collapsed.remove(key) } else { ui.collapsed.insert(key) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 10)
                        AppIcon(bundleID: group.bundleID, size: 16)
                        Text(group.appName)
                            .font(.caption.weight(.medium))
                        Text(countLabel(group))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if collapsed {
                            let pinned = group.windows.filter(isPinned).count + group.closed.count
                            if pinned > 0 {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.accentColor)
                                Text("\(pinned)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .gesture(groupDrag(group))
                .help(L("Drag to move the whole group to another desktop; click to collapse"))
                .opacity(ui.drag?.item == groupItem(group) ? 0.4 : 1)
                .contextMenu { groupSendMenu(group) }

                if !collapsed {
                    ForEach(group.windows) { window in
                        WindowRow(window: window, mode: mode, showsApp: false)
                            .padding(.leading, 16)
                            .id(WindowAnchor(id: window.id))
                    }
                    // Kapalı pinler açık pencerelerden sonra, soluk çip olarak.
                    if !group.closed.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(group.closed) { rule in
                                RuleChip(rule: rule, mode: mode, shadowedBy: shadowed[rule.id])
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func groupItem(_ group: AppGroup) -> DragItem {
        .group(screen: screen.id, desktop: desktop, app: group.id, name: group.appName)
    }

    /// Grup başlığını sürüklemek: bırakılan masaüstüne grubun her öğesi,
    /// tek sürüklemeyle aynı kurallarla taşınır.
    private func groupDrag(_ group: AppGroup) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
            .onChanged { value in
                if ui.drag == nil { ui.holdFocusForDrag() }
                ui.drag = ChipDrag(item: groupItem(group), location: value.location,
                                   hover: ui.target(at: value.location))
            }
            .onEnded { value in
                defer { ui.drag = nil }
                guard case .desktop(let toScreen, let toDesktop)? = ui.target(at: value.location)
                else { return }
                moveGroup(group, to: Router.Placement(screen: toScreen, desktop: toDesktop))
            }
    }

    @ViewBuilder private func groupSendMenu(_ group: AppGroup) -> some View {
        let targets = GroupMovePlan.sendTargets(screens: store.screens(for: mode),
                                                tileCounts: tileCounts, current: placement)
        if !targets.isEmpty {
            Menu(L("Send group to")) {
                ForEach(targets, id: \.screen) { target in
                    Section(target.name) {
                        ForEach(target.desktops, id: \.desktop) { item in
                            Button(store.desktopName(screen: target.screen, desktop: item.desktop,
                                                     mode: mode)
                                    .map { L("Desktop %ld (%@)", item.desktop, $0) }
                                    ?? L("Desktop %ld", item.desktop)) {
                                moveGroup(group, to: Router.Placement(screen: target.screen,
                                                                      desktop: item.desktop))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Grubu taşır (bkz. `GroupMovePlan`): oturum pinleri ve pinsiz
    /// pencereler router'da, kural hedefleri tek geri alma adımıyla belgede.
    private func moveGroup(_ group: AppGroup, to target: Router.Placement) {
        let plan = GroupMovePlan.make(group: group, to: target, mode: mode, isLive: isLive,
                                      rules: store.document.rules, sessionPins: router.sessionPins)
        guard !plan.isEmpty else { return }
        switch ui.panel {
        case .rule, .session: ui.panel = nil
        default: break
        }
        let router = router
        for move in plan.sessions { router.pinSession(move.window, destination: move.to) }
        for id in plan.windows {
            router.moveWindow(id, to: target)
            if var draft = ui.pinDraft, draft.window.id == id {
                draft.target = target
                ui.panel = .pin(draft)
            }
        }
        let sessions = plan.sessions
        store.moveGroup(
            plan.rules, mode: mode,
            undoingSessionPins: sessions.isEmpty ? nil : {
                for move in sessions where router.sessionPins[move.window] != nil {
                    router.pinSession(move.window, destination: move.from)
                }
            })
    }

    /// Grup başlığındaki sayı: "3 pencere", "3 + 2 kapalı" ya da "2 kapalı".
    private func countLabel(_ group: AppGroup) -> String {
        if group.closed.isEmpty { return L("%ld windows", group.windows.count) }
        if group.windows.isEmpty { return L("%ld closed", group.closed.count) }
        return L("%ld + %ld closed", group.windows.count, group.closed.count)
    }

    /// Oturum pini ya da bu modda hedefi olan bir kural var mı (router ile
    /// aynı seçim).
    private func isPinned(_ window: Router.WindowSnapshot) -> Bool {
        Routing.select(rules: store.document.rules, sessionPins: router.sessionPins,
                       mode: mode, windowID: window.id, bundleID: window.bundleID,
                       appName: window.appName, title: window.title, document: window.document) != nil
    }
}

// MARK: - Görsel görünümün kartı

extension DesktopRow {

    /// Kart: başlık (tutamak, ad, sayı, liste düğmesi), pencerelerin
    /// yerinde çizildiği küçük ekran, altında kapalı pinler ya da istenince
    /// satırdaki gibi pencere listesi. Kartın tamamı bırakma hedefidir; boş
    /// yerine sağ tık masaüstü menüsünü açar.
    var card: some View {
        let items = cardItems
        let closed = AppGroup.grouped(windows: [], closed: closedRules)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                handle(inline: true, width: nil)
                if !exists {
                    Text(L("doesn't exist yet"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                if let count = cardCountLabel(items: items) {
                    Text(count)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if !groups.isEmpty {
                    Button {
                        showsList.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(showsList ? Color.accentColor : Color.secondary)
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showsList ? L("Hide the window list")
                                    : L("Show this desktop's windows as a list"))
                    .accessibilityLabel(showsList ? L("Hide the window list")
                                                  : L("Show this desktop's windows as a list"))
                }
            }

            CardScreen(screenSize: screen.visibleSize, items: items, mode: mode,
                       emptyText: L("Empty · drag a window here"),
                       showMore: { showsList.toggle() })

            if showsList {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
            } else if !closed.isEmpty {
                // Penceresi kapalı pinler küçük ekranın altında, uygulamaya göre gruplu.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(closed) { group in
                        groupView(group)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.18)
                                 : Color.primary.opacity(exists ? 0.05 : 0.02)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: exists ? [] : [4, 3])))
        .opacity(isBeingDragged ? 0.4 : 1)
        .dropTarget(target)
        // Satırdaki gibi: kutuların ve çiplerin kendi menüsü öncelikli.
        .contextMenu { desktopMenu }
    }

    /// Başlığın sağındaki sayı: canlı planda kutulardaki pencere sayısı,
    /// öbür planda bu masaüstüne sabitli pin sayısı; boşsa yok.
    private func cardCountLabel(items: [CardScreen.Item]) -> String? {
        if isLive {
            return items.isEmpty ? nil : (items.count == 1 ? L("1 window") : L("%ld windows", items.count))
        }
        return orphanRules.isEmpty ? nil : pinCount(orphanRules.count)
    }

    /// Küçük ekranın altındaki çipler: canlı planda penceresi açık olmayan
    /// (ya da gölgede kalan) pinler, öbür planda penceresi şu an kapalı pinler.
    private var closedRules: [Rule] {
        guard !isLive else { return orphanRules }
        return orphanRules.filter { rule in !ui.windows.contains { rule.matches($0) } }
    }

    /// Küçük ekrandaki kutular. Canlı planda bu masaüstündeki açık
    /// pencereler: sabitse kayıtlı düzeninde ("olduğu gibi" düzende şu anki
    /// yerinde), değilse şu anki yerinde, yeri bilinmiyorsa tam ekran
    /// boyunda. Öbür planda penceresi şu an açık olan pinler hedef
    /// düzenlerinde (o plan etkinleşince pencereler buraya gelir).
    private var cardItems: [CardScreen.Item] {
        guard isLive else {
            return orphanRules.filter { rule in ui.windows.contains { rule.matches($0) } }
                .compactMap { rule -> CardScreen.Item? in
                    guard let destination = rule[mode] else { return nil }
                    let look = ui.searchLook(appName: rule.appName, title: rule.title)
                    let why = Routing.explanation(
                        for: Routing.Match(destination: destination, ruleID: rule.id, rule: rule),
                        screenName: screen.name)
                    return CardScreen.Item(
                        id: "r\(rule.id)", source: .rule(rule), bundleID: rule.bundleID,
                        label: rule.isAppWide ? rule.appName
                            : DesktopPreview.label(appName: rule.appName, title: rule.title),
                        help: "\(rule.appName) — \(rule.title)" + (why.map { "\n" + $0 } ?? ""),
                        layout: destination.layout.isDesktopOnly ? .full : destination.layout,
                        look: .pinned, isSelected: ui.panel == .rule(rule.id),
                        dimmed: look.dimmed, highlighted: look.highlighted)
                }
        }
        return windows.filter { $0.fullscreen == nil }.map { window in
            let actions = WindowActions(window: window, mode: mode, store: store, router: router,
                                        ui: ui, screens: screens)
            let match = Routing.select(
                rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
                windowID: window.id, bundleID: window.bundleID, appName: window.appName,
                title: window.title, document: window.document)
            let current = window.currentLayout(screens: screens.screens) ?? .full
            let layout = match.map { $0.destination.layout.isDesktopOnly ? current : $0.destination.layout }
                ?? current
            let look = ui.searchLook(appName: window.appName, title: window.title)
            let title = window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"
            return CardScreen.Item(
                id: "w\(window.id)", source: .window(window), bundleID: window.bundleID,
                label: DesktopPreview.label(appName: window.appName, title: window.title),
                help: title + "\n" + (actions.whyHere ?? actions.rowHelp),
                layout: layout,
                look: actions.sessionPin != nil ? .session : (match != nil ? .pinned : .unpinned),
                freeMove: actions.freeUntil != nil,
                missing: actions.clampedDesktop != nil,
                isSelected: isShown(window, ruleID: match?.rule?.id),
                isMultiSelected: ui.selection.contains(window.id),
                dimmed: look.dimmed, highlighted: look.highlighted)
        }
    }
}

/// Yeni bir masaüstü numarası oluşturmak için bırakma satırı.
struct GhostRow: View {

    let screen: KnownScreen
    let desktop: Int
    let mode: Mode
    /// Etkin modda tıklama gerçek masaüstü ekler; değilse plana yazar.
    let isLive: Bool
    let canAdd: Bool
    /// Görsel görünümde ızgaranın son kartı ("+ Masaüstü ekle").
    var asCard = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router
    @State private var isAdding = false

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    private var isTargeted: Bool {
        guard ui.drag?.hover == target else { return false }
        // Masaüstü sürüklemesinde de her ekranın "+ Masaüstü" satırı hedeftir.
        return true
    }

    var body: some View {
        Group {
            if asCard {
                VStack(spacing: 4) {
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus").font(.title3)
                    }
                    Text(L("Add desktop"))
                        .font(.callout)
                    Text(L("Desktop %ld", desktop))
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 120)
            } else {
                HStack(spacing: 6) {
                    if isAdding {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(L("Desktop %ld", desktop))
                }
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 24)
            }
        }
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        .background(
            RoundedRectangle(cornerRadius: asCard ? 10 : 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: asCard ? 10 : 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .dropTarget(target)
        .opacity(ui.drag == nil ? 0.7 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAdd, !isAdding, ui.drag == nil else { return }
            guard isLive else {
                store.planDesktop(on: screen.id, mode: mode, count: desktop)
                return
            }
            isAdding = true
            let router = router, store = store, screenID = screen.id, name = screen.name
            Task {
                if await !router.addDesktop(on: screenID) {
                    store.report(L("Could not add a desktop to %@", name))
                }
                isAdding = false
            }
        }
        .help(!canAdd ? L("Connect this display to add desktops.")
              : isLive ? L("Click to add a desktop to this display (opens Mission Control briefly).")
              : L("Click to add a desktop to this plan; it is created when this plan takes effect."))
    }
}

