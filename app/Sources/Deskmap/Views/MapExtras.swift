import SwiftUI

// MARK: - Masaüstü önizlemesi

/// Bir masaüstünün küçük resmi: ekranın oranında çerçeve, içinde pencereler
/// kayıtlı (ya da şu anki) düzenlerinde kutu olarak. Sabit pencere mavi
/// çerçeveli, sabit olmayan kesikli ve soluk, açık penceresi olmayan
/// sabitleme daha da soluk. Kutuya tıklamak satıra tıklamakla aynıdır.
struct DesktopPreview: View {

    struct Item: Identifiable {
        let id: String
        let bundleID: String
        /// Tam ad ("Uygulama — başlık"); imleç ipucunda.
        let title: String
        /// Kutuda simgenin yanındaki kısa yazı (`label(appName:title:)`).
        let label: String
        let layout: WindowLayout
        let pinned: Bool
        /// Penceresi açık mı (kapalı sabitleme soluk çizilir).
        let isOpen: Bool
        let isSelected: Bool
        let dimmed: Bool
        let highlighted: Bool
        let action: () -> Void
    }

    /// Kutu yazısı (saf): uygulamayı simge zaten gösterdiği için yalnız
    /// başlık; sondaki " — Uygulama" (ya da " - Uygulama") atılır. Başlık
    /// boşsa (ya da yalnız uygulama adıysa) uygulama adı.
    nonisolated static func label(appName: String, title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespaces)
        for separator in [" — ", " – ", " - "] where text.hasSuffix(separator + appName) {
            text = String(text.dropLast(separator.count + appName.count))
            break
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? appName : text
    }

    /// Önizlemenin genişliği; yükseklik ekranın oranından.
    nonisolated static let width: CGFloat = 150

    let screenSize: CGSize
    let items: [Item]

    /// Önizleme boyutu (saf): sabit genişlik, ekranın oranında yükseklik
    /// (ultra geniş ve dikey ekranda makul sınırlar içinde).
    nonisolated static func size(screenSize: CGSize) -> CGSize {
        let aspect = screenSize.height > 0 ? screenSize.width / screenSize.height : 1.6
        return CGSize(width: width, height: (width / min(max(aspect, 0.6), 3.6)).rounded())
    }

    var body: some View {
        let size = Self.size(screenSize: screenSize)
        let frame = CGRect(origin: .zero, size: size)
        let scale = size.width / max(screenSize.width, 1)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.06))
            // Sabit olmayanlar altta, sabitler üstte çizilir.
            let drawn = items.sorted { !$0.pinned && $1.pinned }
            let rects = drawn.map { $0.layout.rect(in: frame, pointsPerUnit: scale).insetBy(dx: 1, dy: 1) }
            let labeled = Self.labeled(rects)
            ForEach(Array(drawn.enumerated()), id: \.element.id) { index, item in
                box(item, size: rects[index].size, label: labeled[index])
                    .offset(x: rects[index].minX, y: rects[index].minY)
            }
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Desktop preview"))
    }

    /// Yazının yüksekliği: simge ve tek satır başlık.
    nonisolated static let labelHeight: CGFloat = 15

    /// Hangi kutu adını yazar (saf, çizim sırasıyla): sol üst köşesindeki
    /// yazı alanını sonra çizilen (üstteki) bir kutu örtmüyorsa. Aynı yeri
    /// kaplayan pencerelerin adları üst üste binip okunmaz olmasın; her
    /// kutunun adı yine de imleç ipucunda.
    nonisolated static func labeled(_ rects: [CGRect]) -> [Bool] {
        rects.indices.map { index in
            let rect = rects[index]
            let label = CGRect(x: rect.minX, y: rect.minY,
                               width: rect.width, height: min(labelHeight, rect.height))
            return !rects[(index + 1)...].contains { $0.intersects(label) }
        }
    }

    private func box(_ item: Item, size: CGSize, label: Bool) -> some View {
        let tint: Color = item.highlighted ? .orange : (item.pinned ? .accentColor : .secondary)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(item.pinned ? Color.accentColor.opacity(item.isOpen ? 0.22 : 0.08)
                                  : Color.primary.opacity(0.07))
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(tint.opacity(item.isSelected || item.highlighted ? 1 : 0.7),
                              style: StrokeStyle(lineWidth: item.isSelected || item.highlighted ? 1.6 : 1,
                                                 dash: item.pinned && item.isOpen ? [] : [3, 2]))
            if label, size.width > 18, size.height > 14 {
                HStack(spacing: 3) {
                    AppIcon(bundleID: item.bundleID, size: 11)
                    if size.width > 54 {
                        Text(item.label)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(2)
            }
        }
        .frame(width: max(size.width, 4), height: max(size.height, 4))
        .opacity(item.dimmed ? 0.25 : (item.isOpen ? 1 : 0.6))
        .contentShape(Rectangle())
        .onTapGesture(perform: item.action)
        .help(item.title)
    }
}

// MARK: - Son hareketler

/// Üst çubuktaki "Son hareketler" düğmesinin paneli: iki sekme. "Değişiklikler"
/// bu oturumun ayar geçmişi (geri al / yinele / bir satıra dön), "Pencere
/// hareketleri" Deskmap'in hangi pencereyi ne zaman nereye taşıdığı.
struct ActivityLogView: View {

    enum Tab: Hashable { case changes, moves }

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var store: Store
    @State private var tab: Tab = .changes

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Recent moves")).font(.headline)
            Picker("", selection: $tab) {
                Text(L("Changes")).tag(Tab.changes)
                Text(L("Window moves")).tag(Tab.moves)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch tab {
            case .changes: ChangeHistoryList()
            case .moves: windowMoves
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private var windowMoves: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Pinned windows Deskmap sent to their desktop, newest first: a window opens, or was moved away by hand, and Deskmap puts it back."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if router.actionLog.isEmpty {
                Text(L("Deskmap has not moved any window since it started."))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(router.actionLog) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.date, format: .dateTime.hour().minute())
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    // 12 saatlik biçim ("12:49 PM") 44 pt'ye sığmıyordu.
                                    .lineLimit(1)
                                    .frame(width: 54, alignment: .leading)
                                Text(entry.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                            .padding(.vertical, 5)
                            .overlay(alignment: .top) { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }
}

/// "Değişiklikler" sekmesi: en yeni üstte; imleçteki satır ● ve "ŞİMDİ",
/// imlecin üstündekiler soluk (yinelenebilir), hover'da "Buraya dön".
private struct ChangeHistoryList: View {

    @EnvironmentObject private var store: Store
    @State private var hovered: Int?

    private struct Row: Identifiable {
        /// Geçmişteki konum: 0 = açılış, i = i. girişten hemen sonra.
        let id: Int
        let label: String
        let at: Date
        let redoable: Bool
    }

    private var rows: [Row] {
        let history = store.history
        var rows = [Row(id: 0,
                        label: history.originTrimmed ? L("Earliest kept state") : L("Deskmap opened"),
                        at: history.originAt, redoable: true)]
        for (i, entry) in history.entries.enumerated() {
            rows.append(Row(id: i + 1, label: entry.label, at: entry.at, redoable: entry.isRedoable))
        }
        return rows.reversed()
    }

    var body: some View {
        let history = store.history
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Settings changes this session, newest first. Return to any row to put the settings back the way they were right after it; faded rows can be redone. Not kept after Deskmap quits."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { store.undo() } label: {
                    Label(L("Undo (⌘Z)"), systemImage: "arrow.uturn.backward")
                }
                .disabled(!history.canUndo)
                Button { store.redo() } label: {
                    Label(L("Redo (⇧⌘Z)"), systemImage: "arrow.uturn.forward")
                }
                .disabled(!history.canRedo)
            }
            .buttonStyle(.link)
            .controlSize(.small)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        line(row, history: history)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func line(_ row: Row, history: ChangeHistory) -> some View {
        let isNow = row.id == history.cursor
        let ahead = row.id > history.cursor
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(isNow ? "●" : " ")
                .foregroundStyle(Color.accentColor)
                .frame(width: 10)
            Text(row.at, format: .dateTime.hour().minute().second())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            Text(row.label)
                .fixedSize(horizontal: false, vertical: true)
            if !row.redoable {
                Text(L("cannot be redone"))
                    .foregroundStyle(.tertiary)
                    .help(L("Session-only changes (temporary pins) can be undone but not redone."))
            }
            Spacer(minLength: 0)
            if isNow {
                Text(L("NOW")).bold().foregroundStyle(Color.accentColor)
            } else if hovered == row.id, history.canMove(to: row.id) {
                Button(L("Return here")) { store.returnTo(row.id) }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
        .opacity(ahead ? 0.45 : 1)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? row.id : (hovered == row.id ? nil : hovered) }
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Arama vurgusu

extension View {
    /// Arama sürerken uymayan öğeyi soluklaştırır, uyanı turuncu çerçeveyle
    /// vurgular.
    func searchLook(dimmed: Bool, highlighted: Bool, cornerRadius: CGFloat = 6) -> some View {
        self
            .opacity(dimmed ? 0.3 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.orange, lineWidth: highlighted ? 1.5 : 0)
                    .allowsHitTesting(false))
    }
}
