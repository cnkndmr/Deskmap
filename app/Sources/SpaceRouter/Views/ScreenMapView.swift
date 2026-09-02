import SwiftUI

/// Seçili mod için ekranlar, masaüstleri ve üzerlerindeki kural çipleri.
/// Çipler masaüstleri arasında sürüklenir.
struct ScreenMapView: View {

    let mode: Mode
    /// Bağlı ekranlardaki gerçek masaüstü sayısı (ekran id → sayı).
    let desktopCounts: [String: Int]

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(spacing: 12) {
            ForEach(store.screens(for: mode)) { screen in
                ScreenCard(
                    screen: screen,
                    mode: mode,
                    isConnected: screens.screens.contains { $0.id == screen.id },
                    tileCount: tileCount(for: screen),
                    realCount: desktopCounts[screen.id])
            }

            UnassignedTray(mode: mode)
        }
        .coordinateSpace(name: MapSpace.name)
        .onPreferenceChange(DropTargetPreference.self) { ui.targets = $0 }
        .overlay(alignment: .topLeading) {
            // Sürüklenen çipin hayaleti; imleci izler.
            if let drag = ui.drag, let rule = store.rule(drag.ruleID) {
                RuleChip(rule: rule, mode: mode, isGhost: true)
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
        let real = desktopCounts[screen.id] ?? 0
        return max(real, used, 2)
    }
}

// MARK: - Ekran kartı

private struct ScreenCard: View {

    let screen: KnownScreen
    let mode: Mode
    let isConnected: Bool
    let tileCount: Int
    let realCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: screen.isBuiltin ? "laptopcomputer" : "display")
                Text(screen.name)
                if !isConnected {
                    Text("bağlı değil")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(1..<(tileCount + 1), id: \.self) { desktop in
                    DesktopTile(
                        screen: screen, desktop: desktop, mode: mode,
                        exists: realCount.map { desktop <= $0 } ?? true)
                }
                GhostTile(screen: screen, desktop: tileCount + 1, mode: mode)
            }
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

// MARK: - Masaüstü kutusu

private struct DesktopTile: View {

    let screen: KnownScreen
    let desktop: Int
    let mode: Mode
    /// Bağlı ekranda bu masaüstü gerçekten var mı?
    let exists: Bool

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    private var isTargeted: Bool { ui.drag?.hover == target }

    private var rules: [Rule] {
        store.document.rules.filter {
            guard let destination = $0[mode] else { return false }
            return destination.screen == screen.id && destination.desktop == desktop
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(desktop)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(exists ? .secondary : .tertiary)

            ForEach(rules) { rule in
                RuleChip(rule: rule, mode: mode)
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.18)
                                 : Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: exists ? [] : [4, 3])))
        .dropTarget(target)
        .help(exists ? "Masaüstü \(desktop)"
                     : "Masaüstü \(desktop) henüz yok; açılınca kullanılır")
    }
}

/// Yeni bir masaüstü numarası oluşturmak için bırakma alanı.
private struct GhostTile: View {

    let screen: KnownScreen
    let desktop: Int
    let mode: Mode

    @EnvironmentObject private var ui: UIState

    private var target: DropTarget { .desktop(screen: screen.id, desktop: desktop) }
    private var isTargeted: Bool { ui.drag?.hover == target }

    var body: some View {
        Image(systemName: "plus")
            .font(.caption)
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(width: 28)
            .frame(minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? Color.accentColor.opacity(0.18) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.primary.opacity(0.1),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .dropTarget(target)
            .help("Masaüstü \(desktop)")
    }
}

// MARK: - Atanmamış kurallar

/// Bu modda hedefi olmayan kurallar. Bir çipi buraya bırakmak hedefi kaldırır.
private struct UnassignedTray: View {

    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    private var isTargeted: Bool { ui.drag?.hover == .tray }

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
                     ? "Buraya bırakılan pencere monitör bağlıyken serbest kalır."
                     : "Buraya bırakılan pencere sadece laptopta serbest kalır.")
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
