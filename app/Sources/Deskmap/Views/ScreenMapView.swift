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

extension ScreenMapView {
    /// Masaüstü, tam ekran ve silinmiş satırların ortak etiket sütunu
    /// (saf): görselde önizleme genişliği; listede ekranda adlı masaüstü ya
    /// da silinmiş satır varsa geniş, yoksa dar. Satır kendi adına göre
    /// değişmez; pencereler bütün satırlarda aynı hizadan başlar.
    nonisolated static func labelWidth(visual: Bool, hasNamedRows: Bool) -> CGFloat {
        visual ? DesktopPreview.width : (hasNamedRows ? 132 : 84)
    }
}

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

    /// Liste görünümünün etiket sütunu: her satırın solunda önizleme var.
    private var labelWidth: CGFloat {
        ScreenMapView.labelWidth(visual: true, hasNamedRows: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: screen.isBuiltin ? "laptopcomputer" : "display")
                Text(screen.name)
                    .lineLimit(1)
                if ui.visualMap {
                    Text(L("· %ld desktops", realCount ?? tileCount))
                        .fontWeight(.regular)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if !isConnected {
                    Text(L("not connected"))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)

            if ui.visualMap { grid } else { rows }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1))
    }

    /// Görsel görünüm: masaüstü kartları ızgarada, sonda "+ Masaüstü ekle";
    /// altında silinmiş masaüstleri ve tam ekran space'ler (salt okunur).
    private var grid: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardGridLayout {
                ForEach(1..<(tileCount + 1), id: \.self) { desktop in
                    desktopRow(desktop, labelWidth: 0, asCard: true)
                }
                GhostRow(screen: screen, desktop: tileCount + 1, mode: mode,
                         isLive: isLive, canAdd: !isLive || isConnected, asCard: true)
            }
            ForEach(store.ghosts(on: screen.id, mode: mode)) { ghost in
                DeletedDesktopRow(ghost: ghost, mode: mode, canRestore: isLive && isConnected,
                                  labelWidth: ScreenMapView.labelWidth(visual: false, hasNamedRows: true))
            }
            let fullscreen = fullscreenSpaces.sorted { $0.key < $1.key }.flatMap(\.value)
            ForEach(fullscreen) { space in
                FullscreenRow(space: space, labelWidth: 84, showsNote: true)
            }
        }
    }

    private func desktopRow(_ desktop: Int, labelWidth: CGFloat, asCard: Bool) -> some View {
        DesktopRow(
            screen: screen, desktop: desktop, mode: mode, isLive: isLive,
            exists: realCount.map { desktop <= $0 } ?? true,
            realCount: realCount,
            rowCount: tileCount, tileCounts: tileCounts, shadowed: shadowed,
            labelWidth: labelWidth, asCard: asCard)
    }

    /// Liste görünümü: masaüstü başına satır, tam ekran space'ler gerçek sırasında.
    @ViewBuilder private var rows: some View {
        let fullscreen = fullscreenSpaces
        let labelWidth = labelWidth
        ForEach(fullscreen[0] ?? []) { FullscreenRow(space: $0, labelWidth: labelWidth) }
        ForEach(1..<(tileCount + 1), id: \.self) { desktop in
            desktopRow(desktop, labelWidth: labelWidth, asCard: false)
            ForEach(fullscreen[desktop] ?? []) { FullscreenRow(space: $0, labelWidth: labelWidth) }
        }
        ForEach(store.ghosts(on: screen.id, mode: mode)) { ghost in
            DeletedDesktopRow(ghost: ghost, mode: mode,
                              canRestore: isLive && isConnected, labelWidth: labelWidth)
        }
        GhostRow(screen: screen, desktop: tileCount + 1, mode: mode,
                 isLive: isLive, canAdd: !isLive || isConnected)
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
    let labelWidth: CGFloat

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
            .frame(width: labelWidth, alignment: .leading)
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
    let labelWidth: CGFloat
    /// Görsel görünümde açıklama satırda görünür (listede ipucunda).
    var showsNote = false

    @EnvironmentObject private var ui: UIState

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
            .frame(width: labelWidth, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(space.windows) { window in
                    // Arama her pencereye ayrı: Split View'da biri uyabilir.
                    let look = ui.searchLook(appName: window.appName, title: window.title)
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
                    .searchLook(dimmed: look.dimmed, highlighted: look.highlighted)
                    .id(WindowAnchor(id: window.id))
                }
                if showsNote {
                    Text(L("macOS gives a full-screen window its own desktop; Deskmap leaves it alone."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Hızlı başlangıç

/// Kenar çubuğunun başındaki kart: atanmamış pencere varken hepsini
/// olduğu yere sabitlemeyi önerir. Düğme toplu sabitleme çubuğunu açar
/// (ayrıntı sütununda onaylanır ya da ⌘-tıklayla daraltılır).
struct QuickStartCard: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService

    var body: some View {
        let placeable = Self.placeable(ScreenMapView.unownedWindows(
            ui.windows, rules: store.document.rules, sessionPins: router.sessionPins))
        if mode == screens.mode, !placeable.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("Quick start"), systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                Text(L("If your windows are fine where they are, pin them all where they are; then fix them one by one."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    ui.panel = nil
                    ui.selection = Set(placeable.map(\.id))
                } label: {
                    Label(placeable.count == 1 ? L("Pin it where it is…")
                          : L("Pin all where they are (%ld)", placeable.count),
                          systemImage: "pin.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(L("Each window is pinned to its current desktop with its current size and position. You confirm on the right."))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
    }

    /// Toplu sabitlenebilecek pencereler (saf): yeri bilinen, tam ekran olmayan.
    static func placeable(_ windows: [Router.WindowSnapshot]) -> [Router.WindowSnapshot] {
        windows.filter { $0.placement != nil && $0.fullscreen == nil }
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
                    VStack(spacing: 3) {
                        ForEach(windows) { window in
                            WindowRow(window: window, mode: mode, location: location(of: window))
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

    /// Satırın ikinci satırı: pencerenin şu an bulunduğu ekran ve masaüstü.
    private func location(of window: Router.WindowSnapshot) -> String? {
        guard let placement = window.placement else { return nil }
        let screenName = screens.screens.first { $0.id == placement.screen }?.name
            ?? store.screens(for: screens.mode).first { $0.id == placement.screen }?.name
            ?? placement.screen
        var place = L("%@ · Desktop %ld", screenName, placement.desktop)
        if let name = store.desktopName(screen: placement.screen, desktop: placement.desktop,
                                        mode: screens.mode) {
            place += " · " + name
        }
        return L("now: %@", place)
    }

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

/// Süreli serbest bırakılmış (zamanlı) pinli pencereler: bitişi en yakın
/// olan üstte. Liste boşsa kutu hiç görünmez; sayaçlar satırdaki rozette.
struct FreeMoveTray: View {

    let mode: Mode

    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    var body: some View {
        // Süre dolan satır, yönlendiricinin temizliğini beklemeden düşsün.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let windows = Self.timedWindows(ui.windows, freeMoves: router.freeMoves, now: context.date)
            if !windows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        TrayHeader(systemImage: "timer", title: L("Timed pins"), count: windows.count)
                        Spacer(minLength: 0)
                        if windows.count > 1 {
                            Button(L("End all")) { router.endFreeMove(windows.map(\.id)) }
                                .buttonStyle(.link)
                                .font(.caption)
                                .help(L("End free movement; the windows go back to their pins"))
                        }
                    }
                    .help(L("Pinned windows that are free to move for a while; Deskmap puts them back when the time is up"))
                    VStack(spacing: 3) {
                        ForEach(windows) { window in
                            WindowRow(window: window, mode: mode, location: nil)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
            }
        }
    }

    /// Süresi sürmekte olan pencereler (saf), bitişi en yakın önce.
    static func timedWindows(_ windows: [Router.WindowSnapshot], freeMoves: [CGWindowID: Date],
                             now: Date) -> [Router.WindowSnapshot] {
        windows
            .filter { (freeMoves[$0.id] ?? .distantPast) > now }
            .sorted { freeMoves[$0.id]! < freeMoves[$1.id]! }
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
    nonisolated static func unownedWindows(
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
