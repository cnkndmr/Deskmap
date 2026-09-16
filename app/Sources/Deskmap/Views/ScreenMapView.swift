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
                    realCount: ui.desktopCounts[screen.id],
                    shadowed: shadowed)
            }

            UnassignedTray(mode: mode)
        }
        .coordinateSpace(name: MapSpace.name)
        .onPreferenceChange(DropTargetPreference.self) { ui.targets = $0 }
        .overlay(alignment: .topLeading) {
            // Sürüklenen öğenin hayaleti; imleci izler.
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
        let real = ui.desktopCounts[screen.id] ?? 0
        return max(real, used, live, session, 1)
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

    var body: some View {
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

            ForEach(1..<(tileCount + 1), id: \.self) { desktop in
                DesktopRow(
                    screen: screen, desktop: desktop, mode: mode, isLive: isLive,
                    exists: realCount.map { desktop <= $0 } ?? true,
                    rowCount: tileCount, shadowed: shadowed)
            }
            GhostRow(screen: screen, desktop: tileCount + 1, mode: mode)
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
                let sessionMoved = router.moveDesktop(on: screenID, from: from, to: to, count: count)
                store.moveDesktop(
                    on: screenID, from: from, to: to, count: count, mode: mode,
                    undoingSessionPins: sessionMoved
                        ? { router.moveDesktop(on: screenID, from: to, to: from, count: count) }
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

    @EnvironmentObject private var ui: UIState

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    private var isTargeted: Bool {
        guard ui.drag?.hover == target else { return false }
        if case .desktop(let fromScreen, _) = ui.drag?.item { return fromScreen == screen.id }
        return true
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
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
    }
}

// MARK: - Atanmamış kurallar

/// Bu modda hedefi olmayan pinler (diğer modda pinli). Bir öğeyi buraya
/// bırakmak bu moddaki pini kaldırır.
private struct UnassignedTray: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    private var isTargeted: Bool {
        guard ui.drag?.hover == .tray else { return false }
        if case .desktop = ui.drag?.item { return false }
        return true
    }

    private var rules: [Rule] {
        store.document.rules.filter { $0[mode] == nil }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
                .padding(.top, 3)

            if rules.isEmpty {
                Text(mode == .docked
                     ? L("Drop a window here to unpin it while a monitor is connected.")
                     : L("Drop a window here to unpin it while on the laptop only."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(rules) { rule in
                        RuleChip(rule: rule, mode: mode)
                    }
                }
            }
            Spacer(minLength: 0)
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
                proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews)
        -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
