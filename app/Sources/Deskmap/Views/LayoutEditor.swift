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
                .help(L("Same size in points on every display, placed at an anchor point"))

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
            func round10(_ v: CGFloat) -> Double { Double((v / 10).rounded() * 10) }
            return WindowLayout(fixed: .init(width: round10(rect.width),
                                             height: round10(rect.height),
                                             anchor: anchor(of: rect, in: area)))
        }
        guard layout.fixed != nil else { return layout }
        return WindowLayout(frame: layout.rect(in: area), in: area)
    }

    /// Alanın dayandığı kenarlara göre sabitleme noktası (saf): iki kenara
    /// da dayanıyor ya da hiçbirine dayanmıyorsa o eksende orta.
    static func anchor(of rect: CGRect, in area: CGRect) -> WindowLayout.Anchor {
        let slack = max(area.width, area.height) * 0.01
        func side(_ low: Bool, _ high: Bool) -> Int { low == high ? 1 : (low ? 0 : 2) }
        let col = side(rect.minX - area.minX <= slack, area.maxX - rect.maxX <= slack)
        let row = side(rect.minY - area.minY <= slack, area.maxY - rect.maxY <= slack)
        return WindowLayout.Anchor.allCases[row * 3 + col]
    }

    private func sizeBinding(_ keyPath: WritableKeyPath<WindowLayout.FixedSize, Double>) -> Binding<Int> {
        Binding(
            get: { Int((layout.fixed?[keyPath: keyPath] ?? 0).rounded()) },
            set: { value in
                guard var fixed = layout.fixed else { return }
                fixed[keyPath: keyPath] = Double(max(value, 100))
                layout = WindowLayout(fixed: fixed)
            })
    }

    private var anchorBinding: Binding<WindowLayout.Anchor> {
        Binding(
            get: { layout.fixed?.anchor ?? .center },
            set: { anchor in
                guard var fixed = layout.fixed else { return }
                fixed.anchor = anchor
                layout = WindowLayout(fixed: fixed)
            })
    }

    // Kenar boşluğu (%) <-> oran dönüşümleri. Pencere en az %10 kalır.
    // Her ayar tek bir atama ile yazılır; iki ayrı atama arasında
    // binding'in eski değeri okunup diğer kenarı bozuyordu.

    private struct Margins {
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
                var margins = Margins(layout)
                margins[keyPath: keyPath] =
                    min(max(newValue, 0), 90 - margins[keyPath: opposite])
                layout = margins.layout
            })
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
                .frame(width: 42, alignment: .leading)
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
                    if start == nil {
                        start = Self.cell(at: value.startLocation, size: size,
                                          cols: dims.cols, rows: dims.rows)
                    }
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
