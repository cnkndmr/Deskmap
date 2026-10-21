import AppKit
import SwiftUI

// MARK: - Düzenler

/// Ayarlar › Düzenler: kitaplığın üç bölümü (temel satır, gelişmiş ızgara,
/// gizli), bölüm içinde sıra, liste değiştirme, silme ve varsayılana dönüş.
/// Yeni ya da düzenlenen düzen, listenin yerine açılan taslakta ızgarada
/// çizilir; kaydedilene kadar kitaplığa dokunmaz. Her değişiklik geri
/// alınabilir (`Store.changeLayouts`). Sayfa kendi kaydırmasını yapar
/// (taslağın düğme çubuğu sabit); Ayarlar her açılışta onu yeniden kurar,
/// yarım taslak kapanan pencerede kalmaz (`SettingsState.session`).
struct LayoutSettings: View {

    /// Sekme başlığı (kaydırılan alanın üstünde).
    let title: String

    @EnvironmentObject private var store: Store

    /// Açık taslak; nil değilse düzenleyici listenin yerini alır.
    @State private var draft: LayoutDraft?
    @State private var confirmingReset = false

    var body: some View {
        if let draft {
            LayoutDraftEditor(title: title, draft: draft) { self.draft = nil }
        } else {
            SettingsPage(title: title) { list }
        }
    }

    private var list: some View {
        let library = store.document.layouts
        return VStack(alignment: .leading, spacing: 0) {
            Text(L("Choose the layouts a pin offers and draw your own on the grid. Changing a layout here moves no window: pins keep the layout they have."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            ForEach(LayoutList.allCases) { list in
                section(list, library: library)
            }

            HStack(spacing: 8) {
                Button {
                    draft = .new(in: library)
                } label: {
                    Label(L("New layout"), systemImage: "plus")
                }
                Spacer()
                Button(L("Reset to Defaults…")) { confirmingReset = true }
                    .disabled(library == .defaults)
            }
            .controlSize(.small)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Divider() }
        }
        .confirmationDialog(L("Reset layouts?"), isPresented: $confirmingReset) {
            Button(L("Reset"), role: .destructive) { store.resetLayouts() }
        } message: {
            Text(L("Built-in layouts get their original area, name and list back; your own layouts are removed. Pins keep their layouts."))
        }
    }

    private func section(_ list: LayoutList, library: LayoutLibrary) -> some View {
        let entries = library.entries(in: list)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(list.title).font(.headline)
                Text(list.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            .padding(.bottom, 6)
            if entries.isEmpty {
                Text(L("No layouts here."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Divider() }
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                row(entry, isFirst: index == 0, isLast: index == entries.count - 1, library: library)
            }
        }
    }

    private func row(_ entry: LayoutEntry, isFirst: Bool, isLast: Bool,
                     library: LayoutLibrary) -> some View {
        HStack(spacing: 8) {
            LayoutGlyph(layout: entry.layout, size: CGSize(width: 30, height: 20))
                .foregroundStyle(.secondary)
                .frame(width: 50)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .lineLimit(1)
                let detail = Self.subtitle(entry, in: library)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                move(entry, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help(L("Move up"))
            .accessibilityLabel(Self.moveUpLabel(entry))
            Button {
                move(entry, by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help(L("Move down"))
            .accessibilityLabel(Self.moveDownLabel(entry))
            Menu {
                menuItems(entry, library: library)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("Edit, move or delete this layout"))
            .accessibilityLabel(Self.menuLabel(entry))
        }
        // VoiceOver satırı düzenin adıyla duyurur; içindeki düğmeler ayrı kalır.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.displayName)
        .controlSize(.small)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func menuItems(_ entry: LayoutEntry, library: LayoutLibrary) -> some View {
        Button(L("Edit…")) { draft = .editing(entry) }
            .disabled(entry.id == LayoutLibrary.asIsID)
        Divider()
        Section(L("Show in")) {
            ForEach(LayoutList.allCases) { list in
                MenuCheck(list.shortTitle, checked: entry.list == list) {
                    store.changeLayouts(L("Layout moved: %@", entry.displayName)) {
                        $0.setList(entry.id, to: list)
                    }
                }
                .disabled(!Self.canShow(entry, in: list, library: library))
            }
        }
        if library.isModified(entry.id) {
            Divider()
            Button(L("Restore original")) {
                store.changeLayouts(L("Layout changed: %@", entry.displayName)) {
                    $0.restore(entry.id)
                }
            }
            .disabled(!Self.canRestore(entry, in: library))
            // Özgün alan başka girişteyse `restore` reddeder; neden yazılır.
            if let other = library.restoreConflict(entry.id) {
                Text(L("The original area is now used by “%@”.", other.displayName))
            }
        }
        if !entry.isBuiltIn {
            Divider()
            Button(L("Delete"), role: .destructive) {
                store.changeLayouts(L("Layout deleted: %@", entry.displayName)) {
                    $0.remove(entry.id)
                }
            }
        }
    }

    private func move(_ entry: LayoutEntry, by offset: Int) {
        store.changeLayouts(L("Layout moved: %@", entry.displayName)) {
            $0.move(entry.id, by: offset)
        }
    }

    /// Girişin bu listeye konabilir mi (saf): "olduğu gibi" gelişmişe
    /// konamaz, dolu temel satıra yenisi giremez. Bulunduğu liste hep seçilebilir.
    nonisolated static func canShow(_ entry: LayoutEntry, in list: LayoutList, library: LayoutLibrary) -> Bool {
        if entry.list == list { return true }
        if entry.id == LayoutLibrary.asIsID && list == .advanced { return false }
        return !(list == .basic && library.isBasicFull)
    }

    /// "Özgüne dön" işe yarar mı (saf): hazır düzen değiştirilmiş ve özgün
    /// alanı başka giriş kaplamıyor (yoksa `LayoutLibrary.restore` reddeder).
    nonisolated static func canRestore(_ entry: LayoutEntry, in library: LayoutLibrary) -> Bool {
        library.isModified(entry.id) && library.restoreConflict(entry.id) == nil
    }

    /// Satır alt yazısı (saf): adlandırılmışsa alanı, kullanıcının
    /// düzeni mi, hazır düzen değiştirildi mi.
    nonisolated static func subtitle(_ entry: LayoutEntry, in library: LayoutLibrary) -> String {
        var parts: [String] = []
        if entry.name != nil { parts.append(entry.layout.label) }
        if !entry.isBuiltIn { parts.append(L("Your layout")) }
        if library.isModified(entry.id) { parts.append(L("Changed")) }
        return parts.joined(separator: " · ")
    }

    /// Satır düğmelerinin VoiceOver etiketleri (saf): düzenin adını taşır,
    /// yoksa her satırda aynı "Yukarı taşı" okunur ve yanlış düzen taşınır/silinir.
    nonisolated static func moveUpLabel(_ entry: LayoutEntry) -> String {
        L("Move up: %@", entry.displayName)
    }

    nonisolated static func moveDownLabel(_ entry: LayoutEntry) -> String {
        L("Move down: %@", entry.displayName)
    }

    nonisolated static func menuLabel(_ entry: LayoutEntry) -> String {
        L("Edit, move or delete: %@", entry.displayName)
    }
}

// MARK: - Taslak düzenleyici

/// Yeni ya da var olan düzenin taslağı: ad, liste, ızgara ve
/// kenar boşlukları. Kaydet kitaplığa işler; İptal (sekmeden çıkmak ya da
/// pencereyi kapatmak) taslağı atar: yarım çizilmiş alan sessizce kaydedilmez.
/// Kaydet/İptal kaydırılan alanın dışında, pencerenin altında sabit.
struct LayoutDraftEditor: View {

    let title: String
    @EnvironmentObject private var store: Store
    @State private var draft: LayoutDraft
    let close: () -> Void

    init(title: String, draft: LayoutDraft, close: @escaping () -> Void) {
        self.title = title
        _draft = State(initialValue: draft)
        self.close = close
    }

    /// Kaydet ⌘Return'dür, yalın Return değil: ad ve kenar boşluğu alanında
    /// Return yazılanı bağlar (iğne düzenleyicisindeki gibi); varsayılan düğme
    /// olsaydı taslağı kaydedip düzenleyiciyi kapatırdı.
    static let saveShortcut = KeyboardShortcut(.return, modifiers: .command)

    /// Ad, ekran ve liste etiketlerinin sütunu.
    private static let labelWidth: CGFloat = 70

    var body: some View {
        let problem = draft.problem(in: store.document.layouts)
        VStack(spacing: 0) {
            SettingsPage(title: title) { form(problem: problem) }
            HStack(spacing: 8) {
                Spacer()
                Button(L("Cancel"), action: close)
                    .keyboardShortcut(.cancelAction)
                Button(L("Save"), action: save)
                    .keyboardShortcut(Self.saveShortcut)
                    .help(L("Save (⌘Return)"))
                    .buttonStyle(.borderedProminent)
                    .disabled(problem != nil)
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func form(problem: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.id == nil ? L("New layout") : L("Edit layout"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                row(L("Name")) {
                    TextField(L("Name"), text: $draft.name, prompt: Text(draft.layout.label))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                row(L("Show in")) {
                    Picker(L("Show in"), selection: $draft.list) {
                        ForEach(lists) { list in
                            Text(list.shortTitle).tag(list)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                LayoutGrid(layout: $draft.layout,
                           screenSize: LayoutDraft.previewSize(screens: store.document.screens),
                           maxWidth: 420)
                Text(draft.layout.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("Drag across the grid to choose an area."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            MarginFields(layout: $draft.layout)

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Olduğu gibi" gelişmişe konamaz (düzenleyicide zaten açılmaz).
    private var lists: [LayoutList] {
        LayoutList.allCases.filter { draft.id != LayoutLibrary.asIsID || $0 != .advanced }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
        }
        .controlSize(.small)
    }

    /// Kenar boşluğu alanı (biçimli `TextField`) yazılanı ancak Return'de ya
    /// da odak kaybında bağlar; düğmeye tıklamak odağı almaz. Önce düzenleme
    /// bitirilir, taslak bir sonraki turda (bağlama yazıldıktan sonra) okunur.
    private func save() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async { commit() }
    }

    private func commit() {
        let library = store.document.layouts
        guard draft.problem(in: library) == nil else { return }
        let draft = draft
        let name = LayoutLibrary.cleanName(draft.name) ?? draft.layout.label
        store.changeLayouts(draft.id == nil ? L("Layout added: %@", name)
                                            : L("Layout changed: %@", name)) {
            draft.apply(to: &$0) != nil
        }
        close()
    }
}
