import SwiftUI

/// Düzen düzenleyici: hedef ekranın oranında ızgara (fareyle hücre seçerek
/// düzen), ekranın şekline göre hazır düzenler, yüzde kenar boşlukları ya da
/// sabit boyut (pt) + sabitleme noktası.
struct LayoutEditor: View {

    @Binding var layout: WindowLayout
    /// Hedef ekran (oran ve kullanılabilir boyut); bilinmiyorsa 16:10 varsayılır.
    var screen: KnownScreen?

    private var target: KnownScreen {
        screen ?? KnownScreen(id: "", name: "", aspect: 1.6)
    }

    var body: some View {
        // Dar pencerede ızgara üstte, denetimler altta.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                gridColumn
                controls
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 12) {
                gridColumn
                controls
            }
        }
    }

    private var gridColumn: some View {
        VStack(spacing: 6) {
            LayoutGrid(layout: $layout, screenSize: target.visibleSize)
            Text(layout.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L("Drag across the grid to choose an area."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .fixedSize()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Hazır düzenler (ekranın şekline göre)
            FlowLayout(spacing: 4) {
                ForEach(WindowLayout.presets(aspect: target.aspect), id: \.self) { preset in
                    let isSelected = preset == layout
                    Button {
                        layout = preset
                    } label: {
                        LayoutGlyph(layout: preset, size: LayoutGlyph.presetSize(aspect: target.aspect),
                                    screenSize: target.visibleSize)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor.opacity(0.15)
                                                     : Color.primary.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                    .help(preset.label)
                    .accessibilityLabel(preset.label)
                }
            }
            .frame(maxWidth: 360, alignment: .leading)

            Toggle(L("Fixed size"), isOn: fixedBinding)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                // Ekranın gerçek boyutu bilinmeden pt'ye çevirmek yanlış
                // boyut yazardı (sabit düzen zaten varsa kapatılabilir).
                .disabled(target.knownVisibleSize == nil && layout.fixed == nil)
                .help(target.knownVisibleSize == nil && layout.fixed == nil
                      ? L("Connect this display once so its size is known.")
                      : L("Same size in points on every display, placed at an anchor point"))

            if layout.fixed != nil {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        PercentField(L("Width"), systemImage: "arrow.left.and.right",
                                     value: sizeBinding(\.width), unit: "pt",
                                     range: 200...8000, step: 50)
                        PercentField(L("Height"), systemImage: "arrow.up.and.down",
                                     value: sizeBinding(\.height), unit: "pt",
                                     range: 150...4000, step: 50)
                    }
                    AnchorPicker(anchor: anchorBinding)
                }
                Text(L("Larger than the display? It is fitted to the usable area."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                // Kenar boşlukları
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        PercentField(L("Left"), systemImage: "arrow.left.to.line",
                                     value: leftBinding)
                        PercentField(L("Right"), systemImage: "arrow.right.to.line",
                                     value: rightBinding)
                    }
                    GridRow {
                        PercentField(L("Top"), systemImage: "arrow.up.to.line",
                                     value: topBinding)
                        PercentField(L("Bottom"), systemImage: "arrow.down.to.line",
                                     value: bottomBinding)
                    }
                }
                Text(L("Gap to leave from each edge, within the display's usable area."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Sabit boyut

    /// Açınca şu anki alan hedef ekrandaki boyutuyla sabitlenir (10 pt'ye
    /// yuvarlanır); sabitleme noktası alanın dayandığı kenar(lar)dan seçilir
    /// (sol üst çeyrek → sol üst). Kapatınca sabit dikdörtgen orana çevrilir.
    private var fixedBinding: Binding<Bool> {
        Binding(
            get: { layout.fixed != nil },
            set: { on in layout = Self.toggledFixed(layout, on: on, screenSize: target.visibleSize) })
    }

    /// Sabit boyut aç/kapa dönüşümü (saf).
    static func toggledFixed(_ layout: WindowLayout, on: Bool, screenSize: CGSize) -> WindowLayout {
        let area = CGRect(origin: .zero, size: screenSize)
        if on {
            guard layout.fixed == nil else { return layout }
            let rect = layout.rect(in: area)
            // Kenardan kenara uzanan boyut yuvarlanmaz (tam yükseklik/genişlik
            // eksik kalmasın); kenara dayanan boyut aşağı yuvarlanır (iki
            // yarım üst üste binmesin); ortadaki en yakın 10'a.
            func size(_ v: CGFloat, low: Bool, high: Bool, whole: CGFloat) -> Double {
                if low && high { return Double(whole) }
                return Double(((v / 10) as CGFloat).rounded(low || high ? .down : .toNearestOrEven) * 10)
            }
            let slack: CGFloat = 1
            let left = rect.minX - area.minX <= slack, right = area.maxX - rect.maxX <= slack
            let top = rect.minY - area.minY <= slack, bottom = area.maxY - rect.maxY <= slack
            return WindowLayout(
                fixed: .init(width: size(rect.width, low: left, high: right, whole: area.width),
                             height: size(rect.height, low: top, high: bottom, whole: area.height),
                             anchor: .touching(rect, in: area)),
                screenSize: screenSize)
        }
        guard layout.fixed != nil else { return layout }
        let back = WindowLayout(frame: layout.rect(in: area), in: area)
        // Hazır düzene 1 pt'den yakınsa onun kendisi (Tam, Sol yarım …).
        let presets = WindowLayout.presets(aspect: Double(screenSize.width / max(screenSize.height, 1)))
            + WindowLayout.presets
        return presets.first { Coordinates.close($0.rect(in: area), back.rect(in: area), tolerance: 1) }
            ?? back
    }

    static func anchor(of rect: CGRect, in area: CGRect) -> WindowLayout.Anchor {
        .touching(rect, in: area)
    }

    private func sizeBinding(_ keyPath: WritableKeyPath<WindowLayout.FixedSize, Double>) -> Binding<Int> {
        Binding(
            get: { Int((layout.fixed?[keyPath: keyPath] ?? 0).rounded()) },
            set: { value in
                guard var fixed = layout.fixed else { return }
                fixed[keyPath: keyPath] = Double(max(value, 100))
                layout = WindowLayout(fixed: fixed, screenSize: target.visibleSize)
            })
    }

    private var anchorBinding: Binding<WindowLayout.Anchor> {
        Binding(
            get: { layout.fixed?.anchor ?? .center },
            set: { anchor in
                guard var fixed = layout.fixed else { return }
                fixed.anchor = anchor
                layout = WindowLayout(fixed: fixed, screenSize: target.visibleSize)
            })
    }

    // Kenar boşluğu (%) <-> oran dönüşümleri. Pencere en az %10 kalır.
    // Her ayar tek bir atama ile yazılır; iki ayrı atama arasında
    // binding'in eski değeri okunup diğer kenarı bozuyordu.

    struct Margins {
        var left: Int, right: Int, top: Int, bottom: Int

        init(_ layout: WindowLayout) {
            left = Int((layout.x * 100).rounded())
            right = 100 - Int(((layout.x + layout.w) * 100).rounded())
            top = Int((layout.y * 100).rounded())
            bottom = 100 - Int(((layout.y + layout.h) * 100).rounded())
        }

        var layout: WindowLayout {
            WindowLayout(
                x: Double(left) / 100,
                y: Double(top) / 100,
                w: Double(100 - left - right) / 100,
                h: Double(100 - top - bottom) / 100)
        }
    }

    private func margin(_ keyPath: WritableKeyPath<Margins, Int>,
                        opposite: KeyPath<Margins, Int>) -> Binding<Int> {
        Binding(
            get: { Margins(layout)[keyPath: keyPath] },
            set: { newValue in
                let margins = Margins(layout)
                let value = min(max(newValue, 0), 90 - margins[keyPath: opposite])
                layout = Self.settingMargin(keyPath, to: value, of: layout)
            })
    }

    /// Yalnız değişen kenarı yazar (saf); diğer üç kenar tam değerini korur
    /// (üçte bir gibi yüzdeye tam oturmayan düzenler yana kaymasın).
    static func settingMargin(_ keyPath: WritableKeyPath<Margins, Int>, to value: Int,
                                          of layout: WindowLayout) -> WindowLayout {
        var result = layout
        let v = Double(value) / 100
        switch keyPath {
        case \Margins.left:
            let right = layout.x + layout.w
            result.x = v; result.w = right - v
        case \Margins.right:
            result.w = (1 - v) - layout.x
        case \Margins.top:
            let bottom = layout.y + layout.h
            result.y = v; result.h = bottom - v
        default:
            result.h = (1 - v) - layout.y
        }
        return result
    }

    private var leftBinding: Binding<Int> { margin(\.left, opposite: \.right) }
    private var rightBinding: Binding<Int> { margin(\.right, opposite: \.left) }
    private var topBinding: Binding<Int> { margin(\.top, opposite: \.bottom) }
    private var bottomBinding: Binding<Int> { margin(\.bottom, opposite: \.top) }
}

/// "Left  [ 10 ] %  −/+" biçiminde tek satırlık sayı alanı (yüzde ya da
/// pt). Etiket sütunu en uzun İngilizce etikete ("Bottom") göre genişliktedir.
struct PercentField: View {

    let label: String
    let systemImage: String
    @Binding var value: Int
    var unit = "%"
    var range: ClosedRange<Int> = 0...90
    var step = 5

    init(_ label: String, systemImage: String, value: Binding<Int>,
         unit: String = "%", range: ClosedRange<Int> = 0...90, step: Int = 5) {
        self.label = label
        self.systemImage = systemImage
        _value = value
        self.unit = unit
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 42, alignment: .leading)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: unit == "%" ? 46 : 58)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
        .controlSize(.small)
    }
}

// MARK: - Izgara

/// Hedef ekranın oranında ızgara: fareyle hücre taranınca düzen o alan olur.
/// Şu anki düzen soluk, seçim koyu çizilir. Normal ekranda 12 × 8, ultra
/// genişte 24 × 6 hücre.
struct LayoutGrid: View {

    @Binding var layout: WindowLayout
    let screenSize: CGSize

    struct Cell: Equatable {
        var col: Int
        var row: Int
    }

    @State private var start: Cell?
    @State private var current: Cell?

    private var aspect: Double {
        screenSize.height > 0 ? Double(screenSize.width / screenSize.height) : 1.6
    }

    /// Sütun × satır sayısı (saf).
    static func dimensions(aspect: Double) -> (cols: Int, rows: Int) {
        aspect >= WindowLayout.ultrawideAspect ? (24, 6) : (12, 8)
    }

    /// Çizim boyutu (saf): ultra genişte 420 pt genişlik, normalde 170 pt
    /// yükseklik; oran ekranınki.
    static func size(aspect: Double) -> CGSize {
        let a = max(aspect, 0.5)
        if a >= WindowLayout.ultrawideAspect { return CGSize(width: 420, height: max(420 / a, 70)) }
        return CGSize(width: min(170 * a, 360), height: 170)
    }

    /// İki hücre arasındaki dikdörtgen (uçlar dahil) düzen olarak (saf).
    static func layout(from a: Cell, to b: Cell, cols: Int, rows: Int) -> WindowLayout {
        let c0 = min(a.col, b.col), c1 = max(a.col, b.col)
        let r0 = min(a.row, b.row), r1 = max(a.row, b.row)
        return WindowLayout(x: Double(c0) / Double(cols), y: Double(r0) / Double(rows),
                            w: Double(c1 - c0 + 1) / Double(cols),
                            h: Double(r1 - r0 + 1) / Double(rows))
    }

    /// Noktanın düştüğü hücre (saf); dışarıdaki nokta kenara kırpılır.
    static func cell(at point: CGPoint, size: CGSize, cols: Int, rows: Int) -> Cell {
        let col = Int(point.x / max(size.width, 1) * CGFloat(cols))
        let row = Int(point.y / max(size.height, 1) * CGFloat(rows))
        return Cell(col: min(max(col, 0), cols - 1), row: min(max(row, 0), rows - 1))
    }

    var body: some View {
        let dims = Self.dimensions(aspect: aspect)
        let size = Self.size(aspect: aspect)
        let selection = start.flatMap { s in
            current.map { Self.layout(from: s, to: $0, cols: dims.cols, rows: dims.rows) }
        }
        Canvas { context, canvas in
            let frame = CGRect(origin: .zero, size: canvas)
            context.fill(Path(roundedRect: frame, cornerRadius: 4),
                         with: .color(Color.primary.opacity(0.05)))
            var lines = Path()
            for c in 1..<dims.cols {
                let x = frame.width * CGFloat(c) / CGFloat(dims.cols)
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x, y: frame.height))
            }
            for r in 1..<dims.rows {
                let y = frame.height * CGFloat(r) / CGFloat(dims.rows)
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: frame.width, y: y))
            }
            context.stroke(lines, with: .color(Color.primary.opacity(0.12)), lineWidth: 0.5)
            let scale = frame.width / max(screenSize.width, 1)
            let currentRect = layout.rect(in: frame, pointsPerUnit: scale)
            context.fill(Path(roundedRect: currentRect, cornerRadius: 2),
                         with: .color(Color.accentColor.opacity(selection == nil ? 0.55 : 0.18)))
            if let selection {
                let rect = selection.rect(in: frame)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(Color.accentColor.opacity(0.7)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 2),
                               with: .color(Color.accentColor), lineWidth: 1.5)
            }
            context.stroke(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4),
                           with: .color(Color.primary.opacity(0.35)), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Başlangıç her olayda sürüklemenin kendi başlangıcından:
                    // iptal edilmiş bir sürüklemenin hücresi kalmasın.
                    start = Self.cell(at: value.startLocation, size: size,
                                      cols: dims.cols, rows: dims.rows)
                    current = Self.cell(at: value.location, size: size,
                                        cols: dims.cols, rows: dims.rows)
                }
                .onEnded { _ in
                    if let selection { layout = selection }
                    start = nil
                    current = nil
                })
        .help(L("Drag across the grid to choose an area."))
        .accessibilityLabel(L("Layout grid"))
    }
}

// MARK: - Sabitleme noktası

/// 3 × 3 sabitleme noktası seçici.
struct AnchorPicker: View {

    @Binding var anchor: WindowLayout.Anchor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Anchor"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            let candidate = WindowLayout.Anchor.allCases[row * 3 + col]
                            Button {
                                anchor = candidate
                            } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(candidate == anchor ? Color.accentColor
                                                              : Color.primary.opacity(0.12))
                                    .frame(width: 16, height: 11)
                            }
                            .buttonStyle(.plain)
                            .help(candidate.label)
                            .accessibilityLabel(candidate.label)
                        }
                    }
                }
            }
        }
    }
}
