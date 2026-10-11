import SwiftUI

// MARK: - Kart önizlemesinin yerleşimi

/// Görsel haritada bir masaüstü kartının küçük ekranı: pencereler kendi
/// yerinde ve boyutunda kutu. Gerçek masaüstlerinde 8–10 pencere çoğu kez
/// aynı yeri (tam ekran düzeni) kaplar; kutular düz üst üste çizilse
/// yalnız en üstteki okunurdu. Kural (saf, `arrange`):
///
/// - Hemen hemen aynı yeri kaplayan kutular (kesişim / birleşim ≥
///   `overlap`) bir yığın olur. Yığın basamaklı çizilir: her kutu bir
///   öncekinin `tab` kadar altından başlar, böylece her pencerenin başlık
///   şeridi (simge + ad) bir sekme gibi görünür; en öndeki kutu kalan
///   alanı alır. Kutu yine gerçek kutudur: tıklanır, sürüklenir, sağ tık.
/// - Yığına sığan sekme sayısı yığının boyuna göredir (en öndeki kutuya
///   en az iki sekme boyu kalır) ve en çok `maxShown`; sığmayanlar
///   "+K daha" düğmesinde toplanır (düğme kartın pencere listesini açar).
///   Seçili ya da aramaya uyan pencere (`keep`) sığmayanlara düşmez: yığının
///   sonundaki sıradan bir kutunun yerini alır.
/// - Yığınlar büyükten küçüğe çizilir: küçük pencere (yarım, köşe) büyüğün
///   altında kaybolmaz.
/// - Her kutunun adı, sol üstteki şeridin sonra çizilen kutularca
///   örtülmeyen en geniş parçasına yazılır; yer yoksa ad yalnız ipucunda.
enum CardPreviewLayout {

    /// Çizilecek kutu: `item` girişteki sırası, `label` adın yeri (yoksa nil).
    struct Box: Equatable {
        let item: Int
        var rect: CGRect
        var label: CGRect?
    }

    /// Yığına sığmayan pencereler ve yığının alanı ("+K daha" düğmesi).
    struct More: Equatable {
        let rect: CGRect
        let items: [Int]
    }

    struct Result: Equatable {
        /// Arkadan öne çizim sırası.
        var boxes: [Box]
        var more: [More]
    }

    /// Sekme (başlık şeridi) yüksekliği.
    nonisolated static let tab: CGFloat = 16
    /// Bu oranda örtüşen kutular aynı yığına girer.
    nonisolated static let overlap: CGFloat = 0.6
    /// Bir yığında en çok bu kadar kutu çizilir.
    nonisolated static let maxShown = 8
    /// Adın yazılabileceği en dar şerit (yalnız simge sığar).
    nonisolated static let minLabelWidth: CGFloat = 16

    /// Kesişim / birleşim (saf); boş kutularda 0.
    nonisolated static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }

    /// Yığınlar (saf): giriş sırasıyla, her kutu ilk kutusuyla yeterince
    /// örtüşen ilk yığına girer, yoksa yeni yığın açar.
    nonisolated static func stacks(_ rects: [CGRect], overlap: CGFloat = overlap) -> [[Int]] {
        var result: [[Int]] = []
        for index in rects.indices {
            if let s = result.firstIndex(where: { overlapRatio(rects[$0[0]], rects[index]) >= overlap }) {
                result[s].append(index)
            } else {
                result.append([index])
            }
        }
        return result
    }

    /// Kutuları yerleştirir (saf). `rects` ekran içindeki gerçek kutular
    /// (giriş sırası = öncelik: yığında üstteki sekme ilk pencere).
    nonisolated static func arrange(_ rects: [CGRect], bounds: CGRect, keep: Set<Int> = [],
                                    tab: CGFloat = tab, maxShown: Int = maxShown,
                                    overlap: CGFloat = overlap) -> Result {
        let clipped = rects.map { $0.intersection(bounds) }
        let valid = clipped.indices.filter { !clipped[$0].isNull && clipped[$0].width > 0
            && clipped[$0].height > 0 }
        let groups = stacks(valid.map { clipped[$0] }, overlap: overlap)
            .map { $0.map { valid[$0] } }
        // Büyük yığın arkada; eşitlikte giriş sırası (kararlı).
        let area = { (group: [Int]) -> CGFloat in
            let r = clipped[group[0]]
            return r.width * r.height
        }
        let ordered = groups.enumerated()
            .sorted { area($0.element) != area($1.element)
                ? area($0.element) > area($1.element) : $0.offset < $1.offset }
            .map(\.element)

        var boxes: [Box] = []
        var more: [More] = []
        for group in ordered {
            guard group.count > 1 else {
                boxes.append(Box(item: group[0], rect: clipped[group[0]]))
                continue
            }
            let frame = group.dropFirst().reduce(clipped[group[0]]) { $0.union(clipped[$1]) }
                .intersection(bounds)
            let shown = min(group.count, capacity(height: frame.height, tab: tab, maxShown: maxShown))
            let visible = visibleMembers(group, count: shown, keep: keep)
            let step = min(4, frame.width * 0.015)
            for (offset, item) in visible.enumerated() {
                let dx = CGFloat(offset) * step, dy = CGFloat(offset) * tab
                boxes.append(Box(item: item, rect: CGRect(
                    x: frame.minX + dx, y: frame.minY + dy,
                    width: frame.width - dx, height: frame.height - dy)))
            }
            if group.count > shown {
                more.append(More(rect: frame, items: group.filter { !visible.contains($0) }))
            }
        }
        let drawn = boxes.map(\.rect)
        for index in boxes.indices {
            boxes[index].label = labelSlot(index, in: drawn, height: tab)
        }
        return Result(boxes: boxes, more: more)
    }

    /// Yığının çizilen üyeleri (saf): ilk `count` üye; `keep` içindekiler
    /// dışarıda kaldıysa sondan, `keep`'te olmayan üyelerin yerine geçer.
    /// Sıra yığının sırasıdır.
    nonisolated static func visibleMembers(_ group: [Int], count: Int, keep: Set<Int>) -> [Int] {
        var visible = Array(group.prefix(count))
        for member in group.dropFirst(count) where keep.contains(member) {
            guard let slot = visible.lastIndex(where: { !keep.contains($0) }) else { break }
            visible.remove(at: slot)
            visible.append(member)
        }
        let order = Dictionary(uniqueKeysWithValues: group.enumerated().map { ($1, $0) })
        return visible.sorted { order[$0, default: 0] < order[$1, default: 0] }
    }

    /// Bir yığında çizilebilecek kutu sayısı (saf): en öndeki kutuya en az
    /// iki sekme boyu kalır; en az 1, en çok `maxShown`.
    nonisolated static func capacity(height: CGFloat, tab: CGFloat = tab,
                                     maxShown: Int = maxShown) -> Int {
        guard tab > 0 else { return 1 }
        let fits = Int(((height - 2 * tab) / tab).rounded(.down)) + 1
        return min(max(fits, 1), max(maxShown, 1))
    }

    /// Adın yeri (saf): kutunun üst şeridinden, sonra çizilen kutuların
    /// örtmediği en geniş yatay parça; `minLabelWidth`'ten darsa nil.
    nonisolated static func labelSlot(_ index: Int, in rects: [CGRect], height: CGFloat = tab)
        -> CGRect? {
        let rect = rects[index]
        guard rect.height >= 12 else { return nil }
        let strip = CGRect(x: rect.minX, y: rect.minY, width: rect.width,
                           height: min(height, rect.height))
        var free: [(CGFloat, CGFloat)] = [(strip.minX, strip.maxX)]
        for later in rects[(index + 1)...] {
            // Kenarı değen (alt alta basamak) kutu şeridi örtmez.
            guard later.minY < strip.maxY - 0.5, later.maxY > strip.minY + 0.5,
                  later.minX < strip.maxX, later.maxX > strip.minX else { continue }
            free = free.flatMap { lo, hi -> [(CGFloat, CGFloat)] in
                guard later.maxX > lo, later.minX < hi else { return [(lo, hi)] }
                return [(lo, min(later.minX, hi)), (max(later.maxX, lo), hi)]
                    .filter { $0.1 - $0.0 > 0.5 }
            }
        }
        guard let widest = free.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }),
              widest.1 - widest.0 >= minLabelWidth else { return nil }
        return CGRect(x: widest.0, y: strip.minY, width: widest.1 - widest.0, height: strip.height)
    }
}

// MARK: - Kart ızgarası

/// Masaüstü kartlarını sütunlara dizer: sütun sayısı genişliğe göre (her
/// kart en az `minWidth`), kartlar sütunu eşit paylaşır, bir satırdaki
/// kartlar aynı boydadır. Tembel değil: bütün kartlar (bırakma hedefleri)
/// her zaman çizilir.
struct CardGridLayout: SwiftUI.Layout {

    var minWidth: CGFloat = CardGridLayout.minCardWidth
    var spacing: CGFloat = 10

    /// Kartın en dar hâli: küçük ekran ve başlık şeritleri okunur kalır.
    nonisolated static let minCardWidth: CGFloat = 250

    /// Sütun sayısı (saf): en az 1.
    nonisolated static func columns(width: CGFloat, minWidth: CGFloat, spacing: CGFloat) -> Int {
        let fits = (width + spacing) / max(minWidth + spacing, 1)
        guard fits.isFinite else { return 1 }
        return max(1, Int(fits.rounded(.down)))
    }

    /// Kart genişliği (saf).
    nonisolated static func columnWidth(width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        max((width - CGFloat(columns - 1) * spacing) / CGFloat(columns), 0)
    }

    private func rows(width: CGFloat, subviews: Subviews)
        -> (columns: Int, column: CGFloat, heights: [CGFloat]) {
        let columns = Self.columns(width: width, minWidth: minWidth, spacing: spacing)
        let column = Self.columnWidth(width: width, columns: columns, spacing: spacing)
        let proposal = ProposedViewSize(width: column, height: nil)
        var heights: [CGFloat] = []
        for (index, subview) in subviews.enumerated() {
            let height = subview.sizeThatFits(proposal).height
            if index % columns == 0 { heights.append(height) } else {
                heights[heights.count - 1] = max(heights[heights.count - 1], height)
            }
        }
        return (columns, column, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Önerisiz ya da sınırsız ölçümde iki sütunluk ideal genişlik.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? (2 * minWidth + spacing)
        let layout = rows(width: width, subviews: subviews)
        let height = layout.heights.reduce(0, +) + CGFloat(max(layout.heights.count - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let layout = rows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in layout.heights.enumerated() {
            for column in 0..<layout.columns {
                let index = row * layout.columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + CGFloat(column) * (layout.column + spacing), y: y),
                    proposal: ProposedViewSize(width: layout.column, height: height))
            }
            y += height + spacing
        }
    }
}

// MARK: - Kartın küçük ekranı

/// Kartın küçük ekranı: ekranın oranında çerçeve, kutular
/// `CardPreviewLayout` ile. Kutu, temsil ettiği pencere satırının (ya da pin
/// çipinin) jestlerini taşır.
struct CardScreen: View {

    struct Item: Identifiable {
        enum Source {
            case window(Router.WindowSnapshot)
            case rule(Rule)
        }
        enum Look { case pinned, unpinned, session }

        let id: String
        let source: Source
        let bundleID: String
        /// Kutudaki kısa ad (`DesktopPreview.label`).
        let label: String
        /// İmleç ipucu: tam ad ve neden burada.
        let help: String
        let layout: WindowLayout
        let look: Look
        var freeMove = false
        /// Hedef masaüstü yok; pencere şimdilik başka masaüstünde.
        var missing = false
        var isSelected = false
        var isMultiSelected = false
        var dimmed = false
        var highlighted = false
    }

    let screenSize: CGSize
    let items: [Item]
    let mode: Mode
    let emptyText: String
    /// "+K daha" düğmesi: kartın pencere listesini açar/kapatır.
    let showMore: () -> Void

    /// Ekran oranı; ultra geniş ve dikey ekranda makul sınırlar içinde.
    nonisolated static func aspect(of size: CGSize) -> CGFloat {
        let aspect = size.height > 0 ? size.width / size.height : 1.6
        return min(max(aspect, 0.9), 3.6)
    }

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspect(of: screenSize), contentMode: .fit)
            .overlay(GeometryReader { geometry in
                content(size: geometry.size)
            })
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Desktop preview"))
    }

    private func content(size: CGSize) -> some View {
        let bounds = CGRect(origin: .zero, size: size)
        let scale = size.width / max(screenSize.width, 1)
        let rects = items.map { $0.layout.rect(in: bounds, pointsPerUnit: scale).insetBy(dx: 1, dy: 1) }
        let keep = Set(items.indices.filter {
            items[$0].isSelected || items[$0].isMultiSelected || items[$0].highlighted
        })
        let result = CardPreviewLayout.arrange(rects, bounds: bounds, keep: keep)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.primary.opacity(0.07)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .frame(width: size.width, height: size.height)
            }
            ForEach(result.boxes, id: \.item) { box in
                self.box(items[box.item], rect: box.rect, label: box.label)
            }
            ForEach(Array(result.more.enumerated()), id: \.offset) { _, more in
                moreButton(more.items.map { items[$0] })
                    .frame(width: more.rect.width, height: more.rect.height, alignment: .bottomTrailing)
                    .offset(x: more.rect.minX, y: more.rect.minY)
            }
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func tint(_ item: Item) -> Color {
        switch item.look {
        case .pinned: return item.freeMove ? .teal : .accentColor
        case .session: return .orange
        case .unpinned: return .secondary
        }
    }

    private func box(_ item: Item, rect: CGRect, label: CGRect?) -> some View {
        let tint = tint(item)
        let emphasized = item.isSelected || item.isMultiSelected
        let dashed = item.look == .unpinned || item.freeMove
        return ZStack(alignment: .topLeading) {
            // Opak zemin: yığındaki sekmeler birbirinin içinden görünmesin.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor))
            RoundedRectangle(cornerRadius: 4)
                .fill(item.isMultiSelected ? Color.accentColor.opacity(0.30)
                      : tint.opacity(item.look == .unpinned ? 0.06 : (emphasized ? 0.24 : 0.14)))
            if let label {
                labelRow(item, width: label.width)
                    .frame(width: label.width, height: label.height, alignment: .leading)
                    .offset(x: label.minX - rect.minX, y: label.minY - rect.minY)
            }
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(item.highlighted ? Color.orange
                              : (emphasized ? Color.accentColor : tint.opacity(0.75)),
                              style: StrokeStyle(lineWidth: emphasized || item.highlighted ? 2 : 1,
                                                 dash: dashed && !emphasized ? [3, 2] : []))
        }
        .frame(width: max(rect.width, 4), height: max(rect.height, 4))
        .opacity(item.dimmed ? 0.3 : 1)
        .contentShape(Rectangle())
        .modifier(BoxInteractions(source: item.source, mode: mode))
        .help(item.help)
        .offset(x: rect.minX, y: rect.minY)
        .id(item.anchor)
    }

    private func labelRow(_ item: Item, width: CGFloat) -> some View {
        HStack(spacing: 3) {
            AppIcon(bundleID: item.bundleID, size: 12)
            if width > 40 {
                Text(item.label)
                    .font(.system(size: 10, weight: item.isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(item.look == .unpinned ? .secondary : .primary)
            }
            Spacer(minLength: 0)
            if item.missing, width > 60 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.orange)
            }
            if item.freeMove, width > 60 {
                Image(systemName: "timer")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.teal)
            }
            if item.isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white, Color.accentColor)
            }
        }
        .padding(.horizontal, 3)
    }

    private func moreButton(_ hidden: [Item]) -> some View {
        let highlighted = hidden.contains(where: \.highlighted)
        let selected = hidden.contains { $0.isSelected || $0.isMultiSelected }
        return Button(action: showMore) {
            Text(L("+%ld more", hidden.count))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(highlighted ? Color.orange
                                           : (selected ? Color.accentColor : Color.secondary)))
        }
        .buttonStyle(.plain)
        .padding(4)
        .help(L("Not drawn here: %@. Click to list this desktop's windows.",
                hidden.map(\.label).joined(separator: ", ")))
    }
}

extension CardScreen.Item {
    /// Görünüm kimliği: pencere kutusunda haritanın kaydırma kimliği
    /// (`WindowAnchor`), kural kutusunda kendi kimliği.
    var anchor: AnyHashable {
        if case .window(let window) = source { return AnyHashable(WindowAnchor(id: window.id)) }
        return AnyHashable(id)
    }
}

/// Kutunun jestleri: pencere kutusunda satırınki, kural kutusunda çipinki.
private struct BoxInteractions: ViewModifier {
    let source: CardScreen.Item.Source
    let mode: Mode

    func body(content: Content) -> some View {
        switch source {
        case .window(let window):
            content.modifier(WindowInteractions(window: window, mode: mode))
        case .rule(let rule):
            content.modifier(RuleInteractions(rule: rule, mode: mode))
        }
    }
}
