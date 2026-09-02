import SwiftUI

/// Canlı bir pencere satırı: başlık ve pin düğmesi. Sürüklenerek başka
/// masaüstüne taşınır (taşıma = pinleme). Pinli değilse router dokunmaz.
struct WindowRow: View {

    let window: Router.WindowSnapshot
    let mode: Mode
    /// Tek pencereli uygulamada simge + ad satırda gösterilir; gruplu
    /// uygulamada başlık satırı zaten gösterdiği için gizlenir.
    var showsApp = true
    var isGhost = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    /// Bu pencereye uyan ve bu modda hedefi olan kural.
    private var pinnedRule: Rule? {
        store.document.rules.bySpecificity.first {
            $0[mode] != nil && $0.matches(bundleID: window.bundleID,
                                          appName: window.appName, title: window.title)
        }
    }

    private var isPinned: Bool { pinnedRule != nil }
    private var isDrafting: Bool { ui.pinDraft?.window.id == window.id }
    private var isSelected: Bool { pinnedRule.map { ui.selectedRuleID == $0.id } ?? false }
    private var isBeingDragged: Bool { !isGhost && ui.drag?.item == .window(window.id) }

    var body: some View {
        HStack(spacing: 6) {
            if showsApp {
                AppIcon(bundleID: window.bundleID, size: 16)
                Text(window.appName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            if window.isMinimized {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Simge durumunda")
            }
            Text(window.title.isEmpty ? "Adsız pencere" : window.title)
                .font(.caption)
                .foregroundStyle(window.title.isEmpty ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let rule = pinnedRule, let layout = rule[mode]?.layout {
                LayoutGlyph(layout: layout, size: CGSize(width: 14, height: 10))
                    .foregroundStyle(.tertiary)
                    .help("Düzen: \(layout.label)")
            }

            Button {
                togglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(isPinned
                  ? "Pinli: \(pinnedRule?.title ?? ""). Kaldırmak için tıklayın."
                  : "Bu masaüstüne pinle")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDrafting || isSelected ? Color.accentColor.opacity(0.18)
                                 : Color(nsColor: .controlBackgroundColor).opacity(isGhost ? 1 : 0.7)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isDrafting || isSelected ? Color.accentColor
                              : (isPinned ? Color.accentColor.opacity(0.35)
                                          : Color.primary.opacity(0.08)),
                              lineWidth: 1))
        .contentShape(Rectangle())
        .opacity(isBeingDragged ? 0.35 : 1)
        .onTapGesture {
            // Pinli satıra tıklamak düzen panelini açar.
            guard let rule = pinnedRule else { return }
            ui.pinDraft = nil
            ui.selectedRuleID = ui.selectedRuleID == rule.id ? nil : rule.id
        }
        .gesture(dragGesture, including: isGhost ? .none : .all)
        .help(isPinned ? "Tıklayarak düzeni değiştir, sürükleyerek taşı"
                       : "Pin ile sabitle, sürükleyerek taşı")
    }

    private func togglePin() {
        ui.selectedRuleID = nil
        if let rule = pinnedRule {
            store.unpin(rule.id, mode: mode)
            ui.pinDraft = nil
        } else if isDrafting {
            ui.pinDraft = nil
        } else if let placement = window.placement {
            ui.pinDraft = PinDraft(window: window, target: placement)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(MapSpace.name))
            .onChanged { value in
                ui.drag = ChipDrag(
                    item: .window(window.id),
                    location: value.location,
                    hover: ui.target(at: value.location))
            }
            .onEnded { value in
                defer { ui.drag = nil }
                guard let target = ui.target(at: value.location) else { return }
                ui.selectedRuleID = nil
                switch target {
                case .desktop(let screen, let desktop):
                    let placement = Router.Placement(screen: screen, desktop: desktop)
                    if let rule = pinnedRule, let current = rule[mode] {
                        // Pinli pencere: hedef doğrudan güncellenir.
                        store.setDestination(
                            Destination(screen: screen, desktop: desktop,
                                        layout: current.layout),
                            for: rule.id, mode: mode)
                        ui.pinDraft = nil
                    } else if placement != window.placement {
                        // Taşımak = pinlemek; önce başlık parçası sorulur.
                        ui.pinDraft = PinDraft(window: window, target: placement)
                    }
                case .tray:
                    if let rule = pinnedRule { store.unpin(rule.id, mode: mode) }
                    ui.pinDraft = nil
                }
            }
    }
}

/// Pin düğmesine basılınca ya da pencere sürüklenince oluşan taslak:
/// hangi pencere, nereye. Başlık parçası seçilince kurala dönüşür.
struct PinDraft: Equatable {
    var window: Router.WindowSnapshot
    var target: Router.Placement
}
