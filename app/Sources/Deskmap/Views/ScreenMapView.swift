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
        let shown = store.screens(for: mode)
        // Ekranlar arası masaüstü sürüklemesi hedef ekranın satır sayısını ister.
        let counts = Dictionary(shown.map { ($0.id, tileCount(for: $0)) },
                                uniquingKeysWith: { first, _ in first })
        VStack(spacing: 12) {
            ForEach(shown) { screen in
                ScreenCard(
                    screen: screen,
                    mode: mode,
                    isLive: isLive,
                    isConnected: screens.screens.contains { $0.id == screen.id },
                    tileCount: counts[screen.id] ?? 1,
                    realCount: realCount(for: screen),
                    tileCounts: counts,
                    shadowed: shadowed)
            }

        }
        .environment(\.mapTileCounts, counts)
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
                bundleID: window.bundleID, appName: window.appName, title: window.title, document: window.document)
            else { continue }
            result.winners.insert(match.ruleID)
            for rule in rules
            where rule.id != match.ruleID && rule[mode] != nil
                && rule.matches(bundleID: window.bundleID, appName: window.appName,
                                title: window.title, document: window.document) {
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
    /// Haritadaki her ekranın satır sayısı (ekranlar arası sürükleme için).
    let tileCounts: [String: Int]
    /// Gölgede kalan kural → onu geçen kural (ScreenMapView.shadows).
    let shadowed: [String: String]

    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var store: Store

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
                    rowCount: tileCount, tileCounts: tileCounts, shadowed: shadowed)
                ForEach(fullscreen[desktop] ?? []) { FullscreenRow(space: $0) }
            }
            ForEach(store.ghosts(on: screen.id, mode: mode)) { ghost in
                DeletedDesktopRow(ghost: ghost, mode: mode,
                                  canRestore: isLive && isConnected)
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

// MARK: - Silinmiş masaüstü (hayalet)

/// Mission Control'de silinmiş, adı ya da pini olan masaüstü: ekranın
/// sonunda kesik çizgili, soluk satır. Pinler burada bekler (pencereleri
/// taşınmaz); "Geri getir" yeni masaüstü açar, ad ve pinler ona döner.
private struct DeletedDesktopRow: View {

    let ghost: GhostDesktop
    let mode: Mode
    let canRestore: Bool

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @State private var isRestoring = false

    /// Bu kurulumun pinleri, uygulamaya göre gruplu.
    private var chipGroups: [(app: String, details: [String])] {
        AppGroup.groupedLabels(ghost.pins.filter { $0.mode == mode }.map { pin in
            let tokens = pin.rule.path != nil ? pin.rule.title : pin.rule.tokens.joined(separator: " ")
            return (pin.rule.appName, pin.rule.bundleID, tokens)
        })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Label(ghost.name ?? L("Deleted desktop"), systemImage: "trash.slash")
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text(L("deleted"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 132, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Deleted in Mission Control · %ld pins", ghost.pins.filter { $0.mode == mode }.count))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if !chipGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(chipGroups, id: \.app) { group in
                            if group.details.count >= 2 {
                                Text(group.app).font(.caption.weight(.medium))
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(group.details, id: \.self) { detail in
                                    let single = group.details.count < 2
                                    let label = single
                                        ? (detail.isEmpty ? group.app : "\(group.app) · \(detail)")
                                        : (detail.isEmpty ? group.app : detail)
                                    HStack(spacing: 3) {
                                        Image(systemName: "pin").font(.system(size: 8))
                                        Text(label).lineLimit(1)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Capsule().strokeBorder(
                                        Color.secondary.opacity(0.4),
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                restore()
            } label: {
                if isRestoring {
                    ProgressView().controlSize(.mini)
                } else {
                    Label(L("Restore"), systemImage: "arrow.uturn.backward")
                }
            }
            .controlSize(.small)
            .disabled(!canRestore || isRestoring)
            .help(canRestore ? L("Open a new desktop on this display and bring the name and pins back")
                  : L("Connect this display to restore the desktop"))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .opacity(0.75)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
        .contextMenu {
            Button(L("Forget Deleted Desktop"), role: .destructive) {
                store.discardGhost(ghost.id)
            }
        }
    }

    private func restore() {
        isRestoring = true
        let router = router, store = store, ghost = ghost
        Task {
            if await router.addDesktop(on: ghost.screen),
               let count = router.realDesktopCount(on: ghost.screen) {
                store.restoreGhost(ghost.id, desktop: count,
                                   space: router.currentSpace(on: ghost.screen, desktop: count),
                                   mode: mode)
                router.updateBaseline(addingNewIds: true)
                router.sweep()
            } else {
                store.report(L("Could not add a desktop to %@", ghost.screen))
            }
            isRestoring = false
        }
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
                    .id(WindowAnchor(id: window.id))
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

// MARK: - Uygulama grubu

/// Bir masaüstü satırındaki uygulama grubu: açık pencereler ve aynı
/// uygulamanın penceresi kapalı pinleri (soluk çip).
struct AppGroup: Identifiable {
    let bundleID: String
    let appName: String
    var windows: [Router.WindowSnapshot]
    var closed: [Rule] = []
    var id: String { bundleID.isEmpty ? appName : bundleID }

    /// Açık + kapalı toplam öğe sayısı.
    var total: Int { windows.count + closed.count }

    /// Saf. Başlık/aç-kapa yalnız uygulamanın o masaüstünde en az 2 öğesi
    /// (açık + kapalı) varsa; tek öğe düz satır/çip olarak çizilir.
    var showsHeader: Bool { total >= 2 }

    /// Saf. Silinmiş masaüstü çipleri: etiket (uygulama + başlık parçaları)
    /// uygulamaya göre gruplanır, tekrarlar atılır; sıra ilk görünüşe göre.
    static func groupedLabels(_ entries: [(app: String, bundleID: String, detail: String)])
        -> [(app: String, details: [String])] {
        var order: [String] = []
        var apps: [String: String] = [:]
        var details: [String: [String]] = [:]
        for e in entries {
            let key = e.bundleID.isEmpty ? e.app : e.bundleID
            if apps[key] == nil { apps[key] = e.app; order.append(key) }
            if !(details[key] ?? []).contains(e.detail) { details[key, default: []].append(e.detail) }
        }
        return order.map { (apps[$0] ?? $0, details[$0] ?? []) }
    }

    /// Saf. Sıra: açık pencerelerin sırası, ardından yalnız kapalı
    /// pini olan uygulamalar kuralların sırasıyla. Eşleşme bundleID ile,
    /// bundleID boşsa uygulama adıyla.
    static func grouped(windows: [Router.WindowSnapshot], closed: [Rule]) -> [AppGroup] {
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
        for rule in closed {
            let key = rule.bundleID.isEmpty ? rule.appName : rule.bundleID
            if let i = result.firstIndex(where: { $0.id == key }) {
                result[i].closed.append(rule)
            } else {
                result.append(AppGroup(bundleID: rule.bundleID, appName: rule.appName,
                                       windows: [], closed: [rule]))
            }
        }
        return result
    }
}

// MARK: - Masaüstü satırı

/// Masaüstü etiketi: ad varsa ad (iki satıra kadar) ve altında küçük
/// numara, yoksa "Masaüstü N".
private struct DesktopLabel: View {
    let desktop: Int
    let name: String?
    let exists: Bool

    var body: some View {
        if let name {
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
    /// Haritadaki her ekranın satır sayısı (ekranlar arası sürükleme için).
    let tileCounts: [String: Int]
    /// Gölgede kalan kural → onu geçen kural; soluk çip olarak gösterilir.
    let shadowed: [String: String]

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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
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
                        .onExitCommand { isRenaming = false }
                        .onChange(of: nameFocused) { focused in
                            ui.setEditing(editorID, focused)
                            if !focused && isRenaming { commitName() }
                        }
                        .onDisappear { ui.setEditing(editorID, false) }
                } else {
                    DesktopLabel(desktop: desktop, name: name, exists: exists)
                }
            }
            .frame(width: name == nil && !isRenaming ? 84 : 132, alignment: .leading)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { startRenaming() }
            .gesture(desktopDrag, including: isRenaming ? .none : .all)
            .help(L("Double-click to name this desktop; drag to move it (with its pins) up, down or to another display"))

                if ui.visualMap {
                    DesktopPreview(screenSize: screen.visibleSize, items: previewItems)
                }
            }

            if groups.isEmpty {
                Text(exists ? L("empty") : L("doesn't exist yet"))
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups) { group in
                        groupView(group)
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
    }

    private func startRenaming() {
        nameDraft = name ?? ""
        isRenaming = true
        nameFocused = true
    }

    private func commitName() {
        isRenaming = false
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
                store.moveDesktop(
                    on: screenID, from: from, to: to, count: count, mode: mode, sharedLaptop: live,
                    liveSpaces: liveSpaces,
                    undoingSessionPins: sessionMoved
                        ? { router.moveDesktop(on: screenID, from: to, to: from, count: count,
                                               reorderWindows: live) }
                        : nil)
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
        let router = router, store = store, mode = mode, live = isLive
        let fromScreen = screen.id, from = desktop
        let apply = {
            let sessionMoved = router.moveDesktopAcross(
                from: fromScreen, desktop: from, to: toScreen, at: to, moveWindows: live)
            store.moveDesktopAcross(
                from: fromScreen, desktop: from, to: toScreen, at: to, toCount: toCount, mode: mode,
                undoingSessionPins: sessionMoved
                    ? { router.moveDesktopAcross(from: toScreen, desktop: to, to: fromScreen,
                                                 at: from, moveWindows: live) }
                    : nil)
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
        // Masaüstü sürüklemesinde de her ekranın "+ Masaüstü" satırı hedeftir.
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
              : L("Click to add a desktop to this plan; it is created when this plan takes effect."))
    }
}

// MARK: - Kurulumlar arasında farklı

/// İki kurulum (monitör bağlı / yalnız laptop) arasında farklı kalan
/// pinler: yalnız diğer kurulumda yeri olanlar (bu haritada yerleri yok;
/// bir masaüstüne sürüklemek burada da pinler), yalnız bu kurulumda yeri
/// olanlar (diğer kurulumda dokunulmaz). İki kurulumda da yeri olan pinler
/// (başka ekran ya da masaüstü olsa bile) listelenmez. Bir öğeyi buraya bırakmak bu moddaki pini kaldırır.
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
        case .desktop, .group:
            return false
        case .rule(let id):
            return store.rule(id)?[mode] != nil
        case .window(let id):
            guard let window = ui.windows.first(where: { $0.id == id }) else { return false }
            return Routing.select(
                rules: store.document.rules, sessionPins: router.sessionPins, mode: mode,
                windowID: id, bundleID: window.bundleID, appName: window.appName,
                title: window.title, document: window.document) != nil
        }
    }

    var body: some View {
        let groups = ScreenMapView.setupDifferences(rules: store.document.rules, mode: mode)
        VStack(alignment: .leading, spacing: 8) {
            TrayHeader(systemImage: "rectangle.2.swap",
                       title: L("Placed in one plan only"),
                       count: groups.onlyOther.count + groups.onlyThis.count)

            if groups.onlyOther.isEmpty && groups.onlyThis.isEmpty {
                Text(mode == .docked
                     ? L("Drop a window here to unpin it while a monitor is connected.")
                     : L("Drop a window here to unpin it while on the laptop only."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                if !groups.onlyOther.isEmpty {
                    section(L("Pinned only in the %@ plan", other.title), rules: groups.onlyOther,
                            help: L("No place in this plan; drag onto a desktop to pin it here too."))
                }
                if !groups.onlyThis.isEmpty {
                    section(L("Pinned only in the %@ plan", mode.title), rules: groups.onlyThis,
                            help: L("Left alone in the other plan."))
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
    @EnvironmentObject private var screens: ScreenService

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
            .help(L("Open windows with no pin in either plan; Deskmap leaves them alone"))

            if !collapsed {
                if windows.isEmpty {
                    // İzin yokken ya da ilk taramadan önce pencere bilinmiyor.
                    Text(Self.emptyText(trusted: permission.isTrusted, windows: ui.windows,
                                        rules: store.document.rules,
                                        sessionPins: router.sessionPins))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    let placeable = windows.filter { $0.placement != nil && $0.fullscreen == nil }
                    if mode == screens.mode, !placeable.isEmpty {
                        Button {
                            // Toplu sabitleme çubuğu ayrıntı sütununda açılır;
                            // kullanıcı orada onaylar (ya da ⌘-tıkla daraltır).
                            ui.panel = nil
                            ui.selection = Set(placeable.map(\.id))
                        } label: {
                            Label(placeable.count == 1 ? L("Pin it where it is…")
                                  : L("Pin all %ld where they are…", placeable.count),
                                  systemImage: "pin.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.small)
                        .help(L("Each window is pinned to its current desktop with its current size and position. You confirm on the right."))
                    }
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
                && !pinned.contains { $0.matches(window) }
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

    /// Masaüstü satırı buraya bırakılabilir mi: yalnız kendi yerine değil. Saf.
    static func acceptsDesktopDrop(fromScreen: String, from: Int,
                                   toScreen: String, to: Int) -> Bool {
        fromScreen != toScreen || from != to
    }

    /// Kurulumlar arasında farklı kalan pinler (saf): yalnız diğer modda
    /// yeri olanlar ve yalnız bu modda yeri olanlar. İki modda da yeri olan
    /// (başka ekran/masaüstü olsa bile) ve hiçbir modda yeri olmayan kurallar
    /// listelenmez. Kural sırası korunur.
    static func setupDifferences(rules: [Rule], mode: Mode)
        -> (onlyOther: [Rule], onlyThis: [Rule]) {
        let other: Mode = mode == .docked ? .undocked : .docked
        return (rules.filter { $0[mode] == nil && $0[other] != nil },
                rules.filter { $0[mode] != nil && $0[other] == nil })
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
                $0.matches(window)
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
                case .group(_, _, _, let name):
                    Label(name, systemImage: "square.stack")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                case .desktop(let screen, let desktop):
                    Label(store.desktopName(screen: screen, desktop: desktop, mode: mode)
                            .map { "\(desktop) · \($0)" } ?? L("Desktop %ld", desktop),
                          systemImage: "line.3.horizontal")
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
        // Satırdan geniş öğe satır genişliğine sığdırılır (metin kısalır ya
        // da kırılır, dar kenar çubuğunda taşmaz) ve satırın tamamını alır:
        // ardından gelen parça kırılan metnin yanına sıkışmaz.
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let sizes = zip(subviews, ideals).map { subview, ideal in
            ideal.width > width
                ? CGSize(width: width,
                         height: subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
                : ideal
        }
        let placed = Self.place(sizes: sizes, width: width, spacing: spacing)
        return (placed.size, placed.origins, ideals.map(\.width))
    }

    /// Ölçülmüş öğeleri satırlara dizer (saf). Küçülmeyen öğe de satırdan
    /// geniş sayılmaz: düzen önerilenden geniş rapor etmez, içinde durduğu
    /// sütunu (ör. sağdaki ayrıntı sütunu) itmez.
    static func place(sizes: [CGSize], width: CGFloat, spacing: CGFloat)
        -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for size in sizes {
            let itemWidth = min(size.width, width)
            if x > 0, x + itemWidth > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
