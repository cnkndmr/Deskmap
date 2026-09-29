import SwiftUI

/// Seçili mod için ekranlar, masaüstleri ve üzerlerindeki pencereler.
/// Şu anki modda canlı pencereler bulundukları masaüstünde listelenir;
/// diğer modda yalnızca pinli kurallar görünür. Satırlar masaüstleri
/// arasında sürüklenir (taşımak = pinlemek).
struct ScreenMapView: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    private var isLive: Bool { mode == screens.mode }

    var body: some View {
        // Bir pencereye uyduğu hâlde daha özgül bir kurala (ya da geçici
        // pine) yenilen kurallar; bir kez hesaplanır, satırlara dağıtılır.
        let shadowed = isLive
            ? Self.shadows(rules: store.document.rules, windows: ui.windows,
                           sessionPins: router.sessionPins, mode: mode).shadowedBy
            : [:]
        VStack(spacing: 12) {
            ForEach(store.screens(for: mode)) { screen in
                ScreenCard(
                    screen: screen,
                    mode: mode,
                    isLive: isLive,
                    isConnected: screens.screens.contains { $0.id == screen.id },
                    tileCount: tileCount(for: screen),
                    realCount: realCount(for: screen),
                    shadowed: shadowed)
            }

        }
    }

    /// Bağlı ekrandaki masaüstü sayısı; etkin olmayan modda o moda
    /// bekleyen silmeler düşülür (silinen satır haritadan kalkar).
    private func realCount(for screen: KnownScreen) -> Int? {
        guard let real = ui.desktopCounts[screen.id] else { return nil }
        guard !isLive else { return real }
        let pending = store.document.pendingRemovals(mode: mode, screen: screen.id)
            .filter { $0.space != nil }.count
        return max(real - pending, 0)
    }

    private func tileCount(for screen: KnownScreen) -> Int {
        let used = store.document.rules
            .compactMap { $0[mode] }
            .filter { $0.screen == screen.id }
            .map(\.desktop)
            .max() ?? 0
        let live = isLive
            ? ui.windows.compactMap(\.placement).filter { $0.screen == screen.id }
                .map(\.desktop).max() ?? 0
            : 0
        let session = isLive
            ? router.sessionPins.values.filter { $0.screen == screen.id }
                .map(\.desktop).max() ?? 0
            : 0
        let real = realCount(for: screen) ?? 0
        let planned = store.document.plannedDesktops(mode: mode, screen: screen.id)
        return max(real, used, live, session, planned, 1)
    }

    // MARK: - Gölgede kalan kurallar

    /// Canlı pencerelere göre kuralların durumu.
    struct RuleShadows: Equatable {
        /// En az bir pencerede geçerli hedef olan kural kimlikleri
        /// (geçici pin için `Routing.sessionRuleID`).
        var winners: Set<String> = []
        /// Bir pencereye uyduğu hâlde hiçbir pencerede kazanamayan kural →
        /// onu geçen kuralın kimliği (ilk görülen pencereye göre).
        var shadowedBy: [String: String] = [:]
    }

    /// Her pencere için Router ile aynı seçimi yapar (`Routing.select`);
    /// seçilmeyen ama uyan kurallar gölgede sayılır. Böylece "penceresi
    /// açık ama kazanamayan" pin haritada kaybolmaz.
    static func shadows(
        rules: [Rule], windows: [Router.WindowSnapshot],
        sessionPins: [CGWindowID: Destination], mode: Mode
    ) -> RuleShadows {
        var result = RuleShadows()
        for window in windows {
            guard let match = Routing.select(
                rules: rules, sessionPins: sessionPins, mode: mode, windowID: window.id,
                bundleID: window.bundleID, appName: window.appName, title: window.title)
            else { continue }
            result.winners.insert(match.ruleID)
            for rule in rules
            where rule.id != match.ruleID && rule[mode] != nil
                && rule.matches(bundleID: window.bundleID, appName: window.appName,
                                title: window.title) {
                if result.shadowedBy[rule.id] == nil { result.shadowedBy[rule.id] = match.ruleID }
            }
        }
        // Başka bir pencerede kazanan kural gölgede değildir (o satırda görünür).
        result.shadowedBy = result.shadowedBy.filter { !result.winners.contains($0.key) }
        return result
    }
}

// MARK: - Ekran kartı

private struct ScreenCard: View {

    let screen: KnownScreen
    let mode: Mode
    let isLive: Bool
    let isConnected: Bool
    let tileCount: Int
    let realCount: Int?
    /// Gölgede kalan kural → onu geçen kural (ScreenMapView.shadows).
    let shadowed: [String: String]

    @EnvironmentObject private var ui: UIState

    /// Bu ekrandaki tam ekran space'ler, `afterDesktop` → soldan sağa.
    private var fullscreenSpaces: [Int: [FullscreenSpace]] {
        guard isLive else { return [:] }
        return FullscreenSpace.grouped(ui.windows, screen: screen.id, rowCount: tileCount)
    }

    var body: some View {
        let fullscreen = fullscreenSpaces
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: screen.isBuiltin ? "laptopcomputer" : "display")
                Text(screen.name)
                if !isConnected {
                    Text(L("not connected"))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)

            ForEach(fullscreen[0] ?? []) { FullscreenRow(space: $0) }
            ForEach(1..<(tileCount + 1), id: \.self) { desktop in
                DesktopRow(
                    screen: screen, desktop: desktop, mode: mode, isLive: isLive,
                    exists: realCount.map { desktop <= $0 } ?? true,
                    realCount: realCount,
                    rowCount: tileCount, shadowed: shadowed)
                ForEach(fullscreen[desktop] ?? []) { FullscreenRow(space: $0) }
            }
            GhostRow(screen: screen, desktop: tileCount + 1, mode: mode,
                     isLive: isLive, canAdd: !isLive || isConnected)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1))
    }
}

// MARK: - Tam ekran space satırı

/// Tam ekran (ya da Split View) bir space ve içindeki pencereler.
struct FullscreenSpace: Identifiable, Equatable {
    let id: UInt64
    let order: Int
    var windows: [Router.WindowSnapshot]

    /// Bir ekrandaki tam ekran space'ler: kendisinden önceki masaüstü
    /// sayısı → Mission Control sırasıyla space'ler. Saf. `rowCount`'tan
    /// büyük `afterDesktop` son satırın altına toplanır.
    static func grouped(
        _ windows: [Router.WindowSnapshot], screen: String, rowCount: Int
    ) -> [Int: [FullscreenSpace]] {
        var result: [Int: [FullscreenSpace]] = [:]
        for window in windows {
            guard let slot = window.fullscreen, slot.screen == screen else { continue }
            let key = min(slot.afterDesktop, rowCount)
            if let i = result[key]?.firstIndex(where: { $0.id == slot.space }) {
                result[key]?[i].windows.append(window)
            } else {
                result[key, default: []].append(
                    FullscreenSpace(id: slot.space, order: slot.order, windows: [window]))
            }
        }
        return result.mapValues { $0.sorted { $0.order < $1.order } }
    }
}

/// Masaüstü satırlarının arasında, gerçek sırasında duran salt okunur
/// satır. Tam ekran pencerelere router dokunmaz; bu yüzden sürüklenmez,
/// bırakma hedefi değildir ve masaüstü numarası almaz.
private struct FullscreenRow: View {

    let space: FullscreenSpace

    private var isSplit: Bool { space.windows.count > 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: isSplit
                      ? "rectangle.split.2x1"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9))
                Text(isSplit ? L("Split View") : L("Full screen"))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.purple)
            .frame(width: 84, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(space.windows) { window in
                    HStack(spacing: 6) {
                        AppIcon(bundleID: window.bundleID, size: 16)
                        Text(window.appName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(window.title.isEmpty ? L("Untitled window") : window.title)
                            .font(.caption)
                            .foregroundStyle(window.title.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1))
        .help(L("Full-screen space. Deskmap leaves these windows alone; exit full screen to pin them."))
    }
}

// MARK: - Masaüstü satırı

/// Her masaüstü tam genişlikte bir satır: solda numara, sağda uygulama
/// başına gruplanmış pencereler ve penceresi kapalı pinler.
private struct DesktopRow: View {

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
    /// Gölgede kalan kural → onu geçen kural; soluk çip olarak gösterilir.
    let shadowed: [String: String]

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    private var isTargeted: Bool { ui.drag?.hover == target && acceptsDrag }
    private var placement: Router.Placement {
        Router.Placement(screen: screen.id, desktop: desktop)
    }

    /// Masaüstü sürüklemesi yalnızca aynı ekran içinde kabul edilir.
    private var acceptsDrag: Bool {
        if case .desktop(let fromScreen, let from) = ui.drag?.item {
            return fromScreen == screen.id && from != desktop
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

    /// Uygulama başına gruplar; sıra pencere listesinin sırası.
    private struct AppGroup: Identifiable {
        let bundleID: String
        let appName: String
        var windows: [Router.WindowSnapshot]
        var id: String { bundleID.isEmpty ? appName : bundleID }
    }

    private var groups: [AppGroup] {
        var result: [AppGroup] = []
        for window in windows {
            let key = window.bundleID.isEmpty ? window.appName : window.bundleID
            if let i = result.firstIndex(where: { $0.id == key }) {
                result[i].windows.append(window)
            } else {
                result.append(AppGroup(bundleID: window.bundleID,
                                       appName: window.appName, windows: [window]))
            }
        }
        return result
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
                rule.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                Text(L("Desktop %ld", desktop))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(exists ? .secondary : .tertiary)
            }
            .frame(width: 84, alignment: .leading)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .gesture(desktopDrag)
            .help(L("Drag to move this desktop (with its pins) up or down"))

            if groups.isEmpty && orphanRules.isEmpty {
                Text(exists ? L("empty") : L("doesn't exist yet"))
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                    if !orphanRules.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(orphanRules) { rule in
                                RuleChip(rule: rule, mode: mode, shadowedBy: shadowed[rule.id])
                            }
                        }
                        .padding(.top, groups.isEmpty ? 0 : 2)
                    }
                }
            }
            Spacer(minLength: 0)
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
        .contextMenu {
            Button(L("Remove Desktop %ld", desktop), role: .destructive) { remove() }
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
        if isLive && existing {
            let router = router, store = store, screenID = screen.id, desktop = desktop
            Task {
                if await !router.removeDesktop(on: screenID, desktop: desktop) {
                    store.report(L("Could not remove desktop %ld on %@", desktop, screenID))
                }
            }
            return
        }
        store.removeDesktopLater(
            on: screen.id, desktop: desktop, mode: mode, existing: !isLive && existing,
            space: !isLive && existing
                ? router.spaceForPendingRemoval(on: screen.id, desktop: desktop, mode: mode)
                : nil)
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
                guard case .desktop(let toScreen, let dropped)? = ui.target(at: value.location),
                      toScreen == screen.id else { return }
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
                let sessionMoved = router.moveDesktop(on: screenID, from: from, to: to, count: count,
                                                      reorderWindows: live)
                store.moveDesktop(
                    on: screenID, from: from, to: to, count: count, mode: mode,
                    undoingSessionPins: sessionMoved
                        ? { router.moveDesktop(on: screenID, from: to, to: from, count: count,
                                               reorderWindows: live) }
                        : nil)
            }
    }

    @ViewBuilder
    private func groupView(_ group: AppGroup) -> some View {
        if group.windows.count == 1, let window = group.windows.first {
            WindowRow(window: window, mode: mode, showsApp: true)
        } else {
            let key = "\(screen.id)|\(desktop)|\(group.id)"
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
                        Text(L("%ld windows", group.windows.count))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if collapsed {
                            let pinned = group.windows.filter(isPinned).count
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

                if !collapsed {
                    ForEach(group.windows) { window in
                        WindowRow(window: window, mode: mode, showsApp: false)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    /// Oturum pini ya da bu modda hedefi olan bir kural var mı (router ile
    /// aynı seçim).
    private func isPinned(_ window: Router.WindowSnapshot) -> Bool {
        Routing.select(rules: store.document.rules, sessionPins: router.sessionPins,
                       mode: mode, windowID: window.id, bundleID: window.bundleID,
                       appName: window.appName, title: window.title) != nil
    }
}

/// Yeni bir masaüstü numarası oluşturmak için bırakma satırı.
private struct GhostRow: View {

    let screen: KnownScreen
    let desktop: Int
    let mode: Mode
    /// Etkin modda tıklama gerçek masaüstü ekler; değilse plana yazar.
    let isLive: Bool
    let canAdd: Bool

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router
    @State private var isAdding = false

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    private var isTargeted: Bool {
        guard ui.drag?.hover == target else { return false }
        if case .desktop(let fromScreen, _) = ui.drag?.item { return fromScreen == screen.id }
        return true
    }

    var body: some View {
        HStack(spacing: 6) {
            if isAdding {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "plus")
            }
            Text(L("Desktop %ld", desktop))
        }
        .font(.caption)
        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
              : L("Click to add a desktop to this setup; it is created when this setup becomes active."))
    }
}

// MARK: - Kurulumlar arasında farklı

/// İki kurulum (monitör bağlı / yalnız laptop) arasında farklı kalan
/// pinler: yalnız diğer kurulumda yeri olanlar (bu haritada yerleri yok;
/// bir masaüstüne sürüklemek burada da pinler), yalnız bu kurulumda yeri
/// olanlar (diğer kurulumda dokunulmaz) ve iki kurulumda başka ekrana ya da
/// masaüstüne gidenler. Bir öğeyi buraya bırakmak bu moddaki pini kaldırır.
struct SetupDifferenceTray: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    private var other: Mode { mode == .docked ? .undocked : .docked }

    /// Yalnız bırakma bir şey yapacaksa vurgulanır: bu kurulumda pini olan
    /// pencere ya da çip. Kutudan başlayan sürükleme kutuya geri bırakılırsa
    /// hiçbir şey olmaz.
    private var isTargeted: Bool {
        guard let drag = ui.drag, drag.hover == .tray, !drag.fromTray else { return false }
        switch drag.item {
        case .desktop:
            return false
        case .rule(let id):
            return store.rule(id)?[mode] != nil
        case .window(let id):
            guard let window = ui.windows.first(where: { $0.id == id }) else { return false }
            return Routing.select(
                rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
                windowID: id, bundleID: window.bundleID, appName: window.appName,
                title: window.title) != nil
        }
    }

    var body: some View {
        let groups = ScreenMapView.setupDifferences(rules: store.document.rules, mode: mode)
        VStack(alignment: .leading, spacing: 8) {
            TrayHeader(systemImage: "rectangle.2.swap",
                       title: L("Different between setups"),
                       count: groups.onlyOther.count + groups.onlyThis.count
                           + groups.placedDifferently.count)

            if groups.onlyOther.isEmpty && groups.onlyThis.isEmpty
                && groups.placedDifferently.isEmpty {
                Text(mode == .docked
                     ? L("Drop a window here to unpin it while a monitor is connected.")
                     : L("Drop a window here to unpin it while on the laptop only."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                if !groups.onlyOther.isEmpty {
                    section(L("Pinned only for %@", other.title), rules: groups.onlyOther,
                            help: L("No place in this setup; drag onto a desktop to pin here too."))
                }
                if !groups.onlyThis.isEmpty {
                    section(L("Pinned only for %@", mode.title), rules: groups.onlyThis,
                            help: L("Left alone in the other setup."))
                }
                if !groups.placedDifferently.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Placed differently for %@", other.title))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(groups.placedDifferently) { rule in
                                VStack(alignment: .leading, spacing: 2) {
                                    RuleChip(rule: rule, mode: mode, inTray: true)
                                    if let there = rule[other] {
                                        Text("→ " + placeLabel(there, mode: other))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .padding(.leading, 8)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .dropTarget(.tray)
    }

    /// "Ekran · Masaüstü N" (diğer kurulumdaki yer).
    private func placeLabel(_ destination: Destination, mode: Mode) -> String {
        let name = store.screens(for: mode).first { $0.id == destination.screen }?.name
            ?? destination.screen
        return L("%@ · Desktop %ld", name, destination.desktop)
    }

    private func section(_ title: String, rules: [Rule], help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .help(help)
            FlowLayout(spacing: 6) {
                ForEach(rules) { rule in
                    RuleChip(rule: rule, mode: mode, inTray: true)
                }
            }
        }
    }
}

// MARK: - Sahipsiz pencereler

/// Hiçbir kurulumda pini olmayan (ne kuralı ne geçici pini olan) açık
/// pencereler. Masaüstü satırlarında da görünürler; burada toplu durur.
/// Sürüklemek tek seferlik taşır, pin düğmesi pinler.
struct UnownedWindowsTray: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    @EnvironmentObject private var permission: AccessibilityPermission
    @Environment(\.demoRoom) private var demoRoom
    @AppStorage("unownedTrayCollapsed") private var storedCollapsed = false

    /// Shots modunda kullanıcının tercihi karelere karışmaz: hep açık.
    private var collapsed: Bool {
        get { demoRoom == nil && storedCollapsed }
        nonmutating set { storedCollapsed = newValue }
    }

    var body: some View {
        let windows = ScreenMapView.unownedWindows(
            ui.windows, rules: store.document.rules, sessionPins: router.sessionPins)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                collapsed.toggle()
            } label: {
                HStack(spacing: 4) {
                    TrayHeader(systemImage: "questionmark.square.dashed",
                               title: L("Unassigned windows"), count: windows.count)
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Open windows with no pin in either setup"))

            if !collapsed {
                if windows.isEmpty {
                    // İzin yokken ya da ilk taramadan önce pencere bilinmiyor.
                    Text(Self.emptyText(trusted: permission.isTrusted, windows: ui.windows,
                                        rules: store.document.rules,
                                        sessionPins: router.sessionPins))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 3) {
                        ForEach(windows) { window in
                            WindowRow(window: window, mode: mode)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.1),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

extension UnownedWindowsTray {

    /// Kutu boşken metin (saf): izin yoksa listelenmedi; hiç pencere yoksa
    /// açık pencere yok; pinsiz olanların hepsi tam ekran/yersizse onlara
    /// dokunulmadığı; yoksa her pencerenin pini var.
    static func emptyText(trusted: Bool, windows: [Router.WindowSnapshot], rules: [Rule],
                          sessionPins: [CGWindowID: Destination]) -> String {
        guard trusted else { return L("Windows are not listed yet.") }
        guard !windows.isEmpty else { return L("No open windows.") }
        let pinned = rules.filter { $0.docked != nil || $0.undocked != nil }
        let skipped = windows.contains { window in
            (window.fullscreen != nil || window.placement == nil)
                && sessionPins[window.id] == nil
                && !pinned.contains { $0.matches(bundleID: window.bundleID, appName: window.appName,
                                                 title: window.title) }
        }
        return skipped ? L("Full-screen windows without a pin are left alone.")
                       : L("Every open window has a pin.")
    }
}

/// Alt kutuların başlık satırı: simge, başlık, sayı.
private struct TrayHeader: View {

    let systemImage: String
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

extension ScreenMapView {

    /// Kurulumlar arasında farklı kalan pinler (saf): bu modda yeri
    /// olmayanlar, yalnız bu modda yeri olanlar ve iki modda başka ekrana ya
    /// da masaüstüne gidenler (yalnız düzen farkı sayılmaz). Kural sırası
    /// korunur.
    static func setupDifferences(rules: [Rule], mode: Mode)
        -> (onlyOther: [Rule], onlyThis: [Rule], placedDifferently: [Rule]) {
        let other: Mode = mode == .docked ? .undocked : .docked
        return (rules.filter { $0[mode] == nil },
                rules.filter { $0[mode] != nil && $0[other] == nil },
                rules.filter {
                    guard let here = $0[mode], let there = $0[other] else { return false }
                    return here.screen != there.screen || here.desktop != there.desktop
                })
    }

    /// Hiçbir kurulumda pini olmayan pencereler (saf): geçici pini yok ve
    /// hiçbir modda hedefi olan kural uymuyor. Tam ekran ya da yeri
    /// bilinmeyen pencereler Deskmap'in hiç dokunmadığı pencerelerdir;
    /// listelenmez (sürüklenip taşınamasın, rozette sayılmasın).
    static func unownedWindows(
        _ windows: [Router.WindowSnapshot], rules: [Rule],
        sessionPins: [CGWindowID: Destination]
    ) -> [Router.WindowSnapshot] {
        let pinned = rules.filter { $0.docked != nil || $0.undocked != nil }
        return windows.filter { window in
            window.fullscreen == nil && window.placement != nil
                && sessionPins[window.id] == nil && !pinned.contains {
                $0.matches(bundleID: window.bundleID, appName: window.appName, title: window.title)
            }
        }
    }
}

// MARK: - Sürükleme hayaleti

/// Sürüklenen öğenin hayaleti; imleci izler. Pencerenin tamamını kaplayan
/// katmanda çizilir ki kenar çubuğundan haritaya giderken kırpılmasın.
struct DragGhost: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    var body: some View {
        if let drag = ui.drag {
            Group {
                switch drag.item {
                case .rule(let id):
                    if let rule = store.rule(id) {
                        RuleChip(rule: rule, mode: mode, isGhost: true)
                    }
                case .window(let id):
                    if let window = ui.windows.first(where: { $0.id == id }) {
                        WindowRow(window: window, mode: mode, isGhost: true)
                            .frame(width: 260)
                    }
                case .desktop(_, let desktop):
                    Label(L("Desktop %ld", desktop), systemImage: "line.3.horizontal")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                }
            }
            .offset(x: drag.location.x - 12, y: drag.location.y - 12)
            .allowsHitTesting(false)
            .shadow(radius: 6, y: 2)
        }
    }
}

// MARK: - Akış düzeni

/// Çipleri satır satır dizer.
struct FlowLayout: SwiftUI.Layout {

    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: result.widths[index] > bounds.width
                    ? ProposedViewSize(width: bounds.width, height: nil) : .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews)
        -> (size: CGSize, origins: [CGPoint], widths: [CGFloat]) {
        var origins: [CGPoint] = []
        var widths: [CGFloat] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            // Satırdan geniş öğe satır genişliğine sığdırılır (metin kısalır,
            // dar kenar çubuğunda taşmaz).
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width > width
                ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                : ideal
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            widths.append(subview.sizeThatFits(.unspecified).width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins, widths)
    }
}
