import SwiftUI

/// Canlı bir pencere satırı: başlık ve pin düğmesi. Sürüklenerek başka
/// masaüstüne taşınır; pinsiz pencere yalnızca taşınır (kural yazılmaz),
/// pinli pencerenin hedefi güncellenir. Pinleme yalnızca pin düğmesiyle.
struct WindowRow: View {

    let window: Router.WindowSnapshot
    let mode: Mode
    /// Tek pencereli uygulamada simge + ad satırda gösterilir; gruplu
    /// uygulamada başlık satırı zaten gösterdiği için gizlenir.
    var showsApp = true
    var isGhost = false

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var screens: ScreenService
    @EnvironmentObject private var ui: UIState

    /// Bu pencereye uyan ve bu modda hedefi olan kural; router ile aynı
    /// seçim. Oturum pini ayrı tutulduğu için burada verilmez.
    private var pinnedRule: Rule? {
        Routing.select(rules: store.document.rules, sessionPins: [:], mode: mode,
                       windowID: window.id, bundleID: window.bundleID,
                       appName: window.appName, title: window.title)?.rule
    }

    /// Bu pencerenin kimliğine bağlı oturum pini (kalıcı kuraldan önce gelir).
    private var sessionPin: Destination? { router.sessionPins[window.id] }

    private var isPinned: Bool { sessionPin != nil || pinnedRule != nil }
    private var isDrafting: Bool { ui.pinDraft?.window.id == window.id }
    private var isSelected: Bool {
        if sessionPin != nil { return ui.panel == .session(window.id) }
        return pinnedRule.map { ui.panel == .rule($0.id) } ?? false
    }
    /// Satırda gösterilen hedef: oturum pini varsa onun, yoksa kuralın.
    private var pinnedDestination: Destination? {
        sessionPin ?? pinnedRule?[mode]
    }
    private var pinnedLayout: WindowLayout? { pinnedDestination?.layout }
    /// Hedef masaüstü bu ekranda yoksa router'ın kırptığı sayı (canlı
    /// pencereler yalnızca şu anki modda listelenir; yine de mod denetlenir).
    private var clampedDesktop: Int? {
        pinnedDestination.flatMap {
            MissingDesktopBadge.clamped(for: $0, desktopCounts: ui.desktopCounts,
                                        isLive: mode == screens.mode)
        }
    }
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

            if let destination = pinnedDestination, let real = clampedDesktop {
                MissingDesktopBadge(wanted: destination.desktop, real: real)
            }

            if let layout = pinnedLayout {
                LayoutGlyph(layout: layout, size: CGSize(width: 14, height: 10))
                    .foregroundStyle(.tertiary)
                    .help("Düzen: \(layout.label)")
            }

            Button {
                togglePin()
            } label: {
                Image(systemName: sessionPin != nil ? "pin.circle.fill"
                                  : (isPinned ? "pin.fill" : "pin"))
                    .font(.system(size: sessionPin != nil ? 13 : 11))
                    .foregroundStyle(sessionPin != nil ? Color.orange
                                     : (isPinned ? Color.accentColor : Color.secondary.opacity(0.6)))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(pinButtonHelp)
            .accessibilityLabel(pinButtonHelp)
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
                              : (sessionPin != nil ? Color.orange.opacity(0.5)
                                 : (isPinned ? Color.accentColor.opacity(0.35)
                                             : Color.primary.opacity(0.08))),
                              lineWidth: 1))
        .contentShape(Rectangle())
        .opacity(isBeingDragged ? 0.35 : 1)
        .onTapGesture {
            // Pinli satıra tıklamak düzen panelini açar (tekrar tıklamak kapatır).
            if sessionPin != nil {
                ui.toggle(.session(window.id))
            } else if let rule = pinnedRule {
                ui.toggle(.rule(rule.id))
            }
        }
        .gesture(dragGesture, including: isGhost ? .none : .all)
        .help(isPinned ? "Tıklayarak düzeni değiştir, sürükleyerek pinin hedefini değiştir"
                       : "Sürükleyerek taşı (pinlenmez); sabitlemek için pin'e tıkla")
    }

    private var pinButtonHelp: String {
        if sessionPin != nil {
            return "Geçici pin (yalnızca bu pencere, bu oturum). Kaldırmak için tıklayın."
        }
        return isPinned
            ? "Pinli: \(pinnedRule?.title ?? ""). Kaldırmak için tıklayın."
            : "Bu masaüstüne pinle"
    }

    private func togglePin() {
        let wasDrafting = isDrafting
        ui.panel = nil
        if sessionPin != nil {
            router.unpinSession(window.id)
        } else if let rule = pinnedRule {
            store.unpin(rule.id, mode: mode)
        } else if !wasDrafting, let placement = window.placement {
            ui.panel = .pin(PinDraft(window: window, target: placement))
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
                // Bilgi panelleri kapanır; başka pencerenin pin taslağı ve
                // profil paneli tek seferlik taşımadan etkilenmez.
                switch ui.panel {
                case .rule, .session: ui.panel = nil
                default: break
                }
                switch target {
                case .desktop(let screen, let desktop):
                    let placement = Router.Placement(screen: screen, desktop: desktop)
                    if let current = sessionPin {
                        // Oturum pini: hedef doğrudan güncellenir; geri alma
                        // pin hâlâ duruyorsa eski hedefe döndürür (pencere
                        // kapanıp pin düştüyse dokunmaz).
                        let next = Destination(screen: screen, desktop: desktop,
                                               layout: current.layout)
                        router.pinSession(window.id, destination: next)
                        if next != current {
                            let router = router, id = window.id
                            store.recordSessionChange("Geçici pin taşındı") {
                                if router.sessionPins[id] != nil {
                                    router.pinSession(id, destination: current)
                                }
                            }
                        }
                        ui.panel = nil
                    } else if let rule = pinnedRule, let current = rule[mode] {
                        // Pinli pencere: hedef doğrudan güncellenir (geri alınabilir).
                        store.moveRule(
                            rule.id,
                            to: Destination(screen: screen, desktop: desktop,
                                            layout: current.layout),
                            mode: mode)
                        ui.panel = nil
                    } else if placement != window.placement {
                        // Pinsiz pencere: tek seferlik taşınır, kural yazılmaz.
                        router.moveWindow(window.id, to: placement)
                    }
                case .tray:
                    if sessionPin != nil {
                        router.unpinSession(window.id)
                    } else if let rule = pinnedRule {
                        store.unpin(rule.id, mode: mode)
                    }
                    ui.panel = nil
                }
            }
    }
}
