import SwiftUI

/// Hazır düzenler + yüzde kenar boşlukları + canlı önizleme.
struct LayoutEditor: View {

    @Binding var layout: WindowLayout

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Önizleme
            VStack(spacing: 6) {
                LayoutGlyph(layout: layout, size: CGSize(width: 128, height: 80))
                    .foregroundStyle(Color.accentColor)
                Text(layout.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                // Hazır düzenler
                HStack(spacing: 4) {
                    ForEach(WindowLayout.presets, id: \.self) { preset in
                        let isSelected = preset == layout
                        Button {
                            layout = preset
                        } label: {
                            LayoutGlyph(preset: preset)
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15)
                                                         : Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .help(preset.label)
                    }
                }

                // Kenar boşlukları
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        PercentField("Sol", systemImage: "arrow.left.to.line",
                                     value: leftBinding)
                        PercentField("Sağ", systemImage: "arrow.right.to.line",
                                     value: rightBinding)
                    }
                    GridRow {
                        PercentField("Üst", systemImage: "arrow.up.to.line",
                                     value: topBinding)
                        PercentField("Alt", systemImage: "arrow.down.to.line",
                                     value: bottomBinding)
                    }
                }
                Text("Ekranın kullanılabilir alanında, kenardan bırakılacak boşluk.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
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

/// "Sol  [ 10 ] %  −/+" biçiminde tek satırlık yüzde alanı.
struct PercentField: View {

    let label: String
    let systemImage: String
    @Binding var value: Int

    init(_ label: String, systemImage: String, value: Binding<Int>) {
        self.label = label
        self.systemImage = systemImage
        _value = value
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .frame(width: 24, alignment: .leading)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 46)
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper("", value: $value, in: 0...90, step: 5)
                .labelsHidden()
        }
        .controlSize(.small)
    }
}
