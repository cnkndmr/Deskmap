import SwiftUI

// MARK: - Pin grubu kutusu

/// Bir masaüstündeki pin grubu kutusu (`PinGroupBox`): başlıkta grup simgesi,
/// ad, sayı, "başka yerde de" ipucu ve aç/kapat düğmesi; altında üyelerin
/// açık pencereleri ve kapalı pin çipleri. Başlık tek tıklamayla katlanır,
/// çift tıklamayla adlandırılır, sürüklenince bütün grup taşınır (K3).
/// Uygulama gruplarından görsel olarak ayrılır: dolgulu, ince vurgu kenarlı kutu.
struct PinGroupBoxView: View {

    let box: PinGroupBox
    let screen: KnownScreen
    let desktop: Int
    let mode: Mode
    let isLive: Bool
    /// Gölgede kalan kural → onu geçen kural (soluk çip).
    let shadowed: [String: String]
    /// Haritadaki her ekranın satır sayısı ("Grubu gönder" menüsü).
    let tileCounts: [String: Int]

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService

    @State private var isRenaming = false
    @State private var nameDraft = ""
    /// Boş adla Return: düzenleme açık kalır, alan kırmızı kenarlı.
    @State private var nameInvalid = false
    @FocusState private var nameFocused: Bool
    /// "Tümünü aç" sürerken düğme kapalı (çift basma iki kez açmasın).
    @State private var isOpening = false

    private var groupID: String { box.group.id }
    private var name: String { box.group.name }
    private var placement: Router.Placement { Router.Placement(screen: screen.id, desktop: desktop) }
    /// `UIState.textEditors` kimliği; aynı grup birden çok masaüstünde çizilebilir.
    private var editorID: String { "pg:\(groupID)|\(screen.id)|\(desktop)" }
    private var collapseKey: String {
        UIState.collapseKey(mode: mode, screen: screen.id, desktop: desktop, group: box.id)
    }
    private var collapsed: Bool { ui.collapsed.contains(collapseKey) }
    private var usable: Set<String> { isLive ? screens.usableRoles : [] }
    private var dragItem: DragItem {
        .pinGroup(screen: screen.id, desktop: desktop, id: groupID, name: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                header
                toggleButton
            }
            if !collapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(box.windows) { window in
                        WindowRow(window: window, mode: mode, showsApp: true)
                            .id(WindowAnchor(id: window.id))
                    }
                    // Kapalı üyeler açık pencerelerden sonra; çip uygulama simgesini taşır.
                    if !box.closed.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(box.closed) { rule in
                                RuleChip(rule: rule, mode: mode, shadowedBy: shadowed[rule.id])
                            }
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        .opacity(ui.drag?.item == dragItem ? 0.4 : 1)
        .onAppear { takeRenameRequest() }
        .onChange(of: ui.renamePinGroupRequest) { _ in takeRenameRequest() }
    }

    // MARK: Başlık

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            Image(systemName: "square.stack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            if isRenaming {
                nameField
            } else {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(name)
            }
            Text(Self.countLabel(windows: box.windows.count, closed: box.closed.count))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
            if let elsewhere = Self.elsewhereLabel(box) {
                Text(elsewhere)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming else { return }
            // Tek tıklama hemen katlar; çift tıklamanın ikinci basışı katlamayı geri alıp adlandırır.
            ui.handleClick(single: toggleCollapsed, double: {
                toggleCollapsed()
                startRenaming()
            })
        }
        .gesture(pinGroupDrag, including: isRenaming ? .none : .all)
        .help(L("Drag to move every pin of the group to another desktop; click to collapse; double-click to rename"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Pin group %@", name))
        .contextMenu { menu }
    }

    private var nameField: some View {
        TextField(L("Group name"), text: $nameDraft)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .frame(minWidth: 80, maxWidth: 220)
            .focused($nameFocused)
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.red, lineWidth: nameInvalid ? 1 : 0))
            .help(nameInvalid ? L("Group name can't be empty") : L("Group name"))
            .onSubmit { commitName(focusLost: false) }
            .onExitCommand { endRenaming() }
            .onChange(of: nameDraft) { _ in if nameInvalid { nameInvalid = false } }
            .onChange(of: nameFocused) { focused in
                ui.setEditing(editorID, focused)
                if !focused && isRenaming { commitName(focusLost: true) }
            }
            .onDisappear {
                ui.setEditing(editorID, false)
                if isRenaming { endRenaming() }
            }
    }

    /// "3 pencere", "3 + 2 kapalı" ya da "2 kapalı" (uygulama grubuyla aynı metin).
    static func countLabel(windows: Int, closed: Int) -> String {
        if closed == 0 { return L("%ld windows", windows) }
        if windows == 0 { return L("%ld closed", closed) }
        return L("%ld + %ld closed", windows, closed)
    }

    /// "Masaüstü 2, 5 üzerinde de" / "başka ekranda da"; grup tek yerdeyse nil.
    static func elsewhereLabel(_ box: PinGroupBox) -> String? {
        var parts: [String] = []
        if !box.elsewhere.isEmpty {
            parts.append(L("also on Desktop %@", box.elsewhere.map(String.init).joined(separator: ", ")))
        }
        if box.otherScreens { parts.append(L("also on another screen")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func toggleCollapsed() {
        if collapsed { ui.collapsed.remove(collapseKey) } else { ui.collapsed.insert(collapseKey) }
    }

    // MARK: Adlandırma

    /// Yeni kurulan grup: kutusu görünür görünmez adlandırmaya girer.
    private func takeRenameRequest() {
        guard ui.renamePinGroupRequest == groupID else { return }
        ui.renamePinGroupRequest = nil
        if collapsed { ui.collapsed.remove(collapseKey) }
        startRenaming()
    }

    private func startRenaming() {
        nameDraft = name
        nameInvalid = false
        isRenaming = true
        // Alan bu çizimde kuruluyor; odak bir sonraki turda verilir.
        DispatchQueue.main.async { nameFocused = true }
    }

    private func endRenaming() {
        isRenaming = false
        nameInvalid = false
    }

    /// Return ya da odak kaybı. Boş ad: Return'de düzenleme açık kalır
    /// (kırmızı kenar), odak kaybında eski ad kalır ve düzenleme kapanır.
    private func commitName(focusLost: Bool) {
        guard isRenaming else { return }
        guard Document.normalizedGroupName(nameDraft) != nil else {
            if focusLost {
                endRenaming()
            } else {
                nameInvalid = true
                nameFocused = true
            }
            return
        }
        store.renamePinGroup(groupID, to: nameDraft)
        endRenaming()
    }

    // MARK: Aç / kapat (K3: grubun bu moddaki bütün üyeleri)

    /// Her basışta güncel belge ve pencerelerden hesaplanır.
    private var toggleInput: (openPinned: [Router.WindowSnapshot], closed: [Rule]) {
        let rules = store.document.rules, sessions = router.sessionPins, mode = mode
        let context = router.context(for: mode)
        return PinBatch.pinGroupInput(
            members: store.document.pinGroupMembers(groupID, mode: mode), windows: ui.windows,
            shadowed: shadowed,
            ruleFor: { PinGroupLayout.winningRule($0, rules: rules, sessionPins: sessions,
                                                  mode: mode, context: context) })
    }

    @ViewBuilder private var toggleButton: some View {
        if isLive {
            let input = toggleInput
            switch PinBatch.groupAction(openPinned: input.openPinned.count, closed: input.closed.count) {
            case .open:
                toggleButton(symbol: "arrow.up.forward.app",
                             help: L("Open all closed pins in %@", name), action: openAll)
                    .disabled(isOpening)
            case .close:
                toggleButton(symbol: "xmark.app", help: L("Close all open pins in %@", name),
                             action: closeAll)
            case .none:
                EmptyView()
            }
        }
    }

    private func toggleButton(symbol: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func openAll() {
        guard !isOpening else { return }
        let closed = toggleInput.closed
        guard !closed.isEmpty else { return }
        isOpening = true
        let router = router, store = store, mode = mode
        Task {
            await PinBatch.openAll(closed, mode: mode, router: router, store: store)
            isOpening = false
        }
    }

    private func closeAll() {
        PinBatch.close(toggleInput.openPinned, store: store)
    }

    // MARK: Menü

    @ViewBuilder private var menu: some View {
        Button(L("Rename group…")) { startRenaming() }
        if isLive {
            let input = toggleInput
            if !input.closed.isEmpty {
                Button(L("Open all")) { openAll() }
                    .disabled(isOpening)
            }
            if !input.openPinned.isEmpty {
                Button(L("Close all")) { closeAll() }
            }
        }
        sendMenu
        Divider()
        Button(L("Ungroup (keeps pins)")) { store.dissolvePinGroup(groupID) }
    }

    /// "Grubu gönder": haritadaki her masaüstü; grup bu masaüstünde
    /// toplanmışsa burası hariç (dağınık grup buraya da toplanabilir).
    @ViewBuilder private var sendMenu: some View {
        let current = box.isScattered ? Router.Placement(screen: "", desktop: 0) : placement
        let targets = GroupMovePlan.sendTargets(screens: store.screens(for: mode),
                                                tileCounts: tileCounts, current: current)
        if !targets.isEmpty {
            Menu(L("Send group to")) {
                ForEach(targets, id: \.screen) { target in
                    Section(target.name) {
                        ForEach(target.desktops, id: \.desktop) { item in
                            Button(store.desktopName(screen: target.screen, desktop: item.desktop,
                                                     mode: mode)
                                    .map { L("Desktop %ld (%@)", item.desktop, $0) }
                                    ?? L("Desktop %ld", item.desktop)) {
                                move(to: Router.Placement(screen: target.screen, desktop: item.desktop))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Sürükle-bırak

    /// Başlığı sürüklemek: bırakılan masaüstüne grubun bu moddaki bütün
    /// üyeleri gider (dağınık grup orada birleşir). Tepsi yok sayılır.
    private var pinGroupDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
            .onChanged { value in
                if ui.drag == nil { ui.holdFocusForDrag() }
                ui.drag = ChipDrag(item: dragItem, location: value.location,
                                   hover: ui.target(at: value.location))
            }
            .onEnded { value in
                defer { ui.drag = nil }
                guard case .desktop(let toScreen, let toDesktop)? = ui.target(at: value.location)
                else { return }
                let target = Router.Placement(screen: toScreen, desktop: toDesktop)
                guard target != placement || box.isScattered else { return }
                move(to: target)
            }
    }

    /// Grubu taşır (`GroupMovePlan.forPinGroup`): kural hedefleri tek geri
    /// alma adımıyla belgede; canlı planda Router pencereleri kural
    /// değişimiyle taşır.
    private func move(to target: Router.Placement) {
        let mode = mode, live = isLive, usable = usable
        let plan = GroupMovePlan.forPinGroup(
            groupID, rules: store.document.rules, mode: mode, to: target,
            winner: { MapPlaces.winner($0, mode: mode, live: live, usable: usable)?.destination })
        guard !plan.isEmpty else { return }
        switch ui.panel {
        case .rule, .session: ui.panel = nil
        default: break
        }
        store.movePinGroup(plan.rules, mode: mode)
    }
}

// MARK: - Pin grubu menüsü (çip ve pencere satırı)

/// Kalıcı kuralı olan çipin ve pencere satırının sağ tık menüsündeki grup
/// komutları: "Gruba ekle" (var olan gruplar, "Yeni grup…") ve "Gruptan
/// çıkar". Tıklanan öğe çoklu seçimdeyse bütün seçime uygulanır.
struct PinGroupMenu: View {

    let ruleID: String
    let mode: Mode
    /// Menü bir pencere satırından açıldıysa o pencere.
    var windowID: CGWindowID?

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState
    @EnvironmentObject private var router: Router

    /// Menünün uygulanacağı kural kimlikleri (belge sırasıyla).
    private var targetIDs: [String] {
        let inSelection = ui.selectedRules.contains(ruleID)
            || windowID.map { ui.selection.contains($0) } == true
        guard inSelection else { return [ruleID] }
        let rules = store.document.rules, sessions = router.sessionPins, mode = mode
        let context = router.context(for: mode)
        var ids = ui.selectedRules
        for window in ui.windows where ui.selection.contains(window.id) {
            if let rule = PinGroupLayout.winningRule(window, rules: rules, sessionPins: sessions,
                                                     mode: mode, context: context) {
                ids.insert(rule.id)
            }
        }
        ids.insert(ruleID)
        return rules.map(\.id).filter(ids.contains)
    }

    var body: some View {
        if let rule = store.rule(ruleID) {
            let ids = targetIDs
            let targets = PinGroupLayout.addTargets(
                groups: store.document.pinGroups,
                members: PinGroupLayout.groupsWithMembers(store.document.rules, mode: mode),
                excluding: ids.count == 1 ? rule.groupID : nil)
            Menu(L("Add to group")) {
                ForEach(targets) { group in
                    Button(group.name) {
                        store.addToPinGroup(group.id, ruleIDs: ids)
                        ui.clearSelection()
                    }
                }
                if !targets.isEmpty { Divider() }
                Button(L("New group…")) {
                    if let id = store.createPinGroup(name: nil, ruleIDs: ids) {
                        ui.renamePinGroupRequest = id
                    }
                    ui.clearSelection()
                }
            }
            if ids.contains(where: { id in
                store.rule(id)?.groupID.flatMap { store.document.pinGroup($0) } != nil
            }) {
                Button(L("Remove from group")) {
                    store.removeFromPinGroup(ruleIDs: ids)
                    ui.clearSelection()
                }
            }
        }
    }
}
