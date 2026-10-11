import SwiftUI

// MARK: - Sağ sütun çerçevesi

/// Haritanın sağındaki ayrıntı sütununun ortak görünümü: iç boşluk ve
/// hafif zemin. Sütun haritadan yer almaz; pencere o kadar geniştir.
struct InspectorChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func inspectorChrome() -> some View { modifier(InspectorChrome()) }
}

/// Seçili bir şey yokken sütunda: ne yapılacağına dair kısa ipuçları.
struct InspectorPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Click a window to see where it goes."))
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            tip("cursorarrow.click", L("Click: details and layout"))
            tip("hand.draw", L("Drag onto a desktop: move it there"))
            tip("contextualmenu.and.cursorarrow", L("Right-click: send it elsewhere or free it for a while"))
            tip("command", L("⌘-click: select several and pin them at once"))
        }
        .foregroundStyle(.secondary)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).frame(width: 16)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Kural cümlesi

/// Kuralı tek cümleyle anlatır: "Messages · başlığında “acme-web” geçen
/// pencereler → Studio Display · Masaüstü 2 · Sol yarı". Altı çizili her
/// parça bir menüdür; seçince kural değişir.
struct RuleSentence<MatchMenu: View>: View {

    let appName: String
    /// Eşleşme parçasının metni ("bütün pencereler", "başlığında … geçen").
    let matchText: String
    let destination: Destination
    let mode: Mode
    /// Eşleşme menüsünün içeriği; boşsa parça düz metin olarak durur.
    @ViewBuilder let matchMenu: () -> MatchMenu
    let setDestination: (Destination) -> Void
    /// "Diğer düzenler…" seçilince (gelişmiş bölümü açar).
    let showAdvanced: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    var body: some View {
        FlowLayout(spacing: 4) {
            Text(appName).fontWeight(.semibold)
            Text("·").foregroundStyle(.secondary)
            if MatchMenu.self == EmptyView.self {
                Text(matchText)
            } else {
                part(matchText, help: L("Which windows this applies to"), wraps: true) { matchMenu() }
            }
            Text("→").foregroundStyle(.secondary)
            part(screenName, help: L("Display"), wraps: true) { screenItems }
            Text("·").foregroundStyle(.secondary)
            part(desktopName(destination.desktop), help: L("Desktop"), wraps: true) { desktopItems }
            Text("·").foregroundStyle(.secondary)
            part(destination.layout.label, help: L("Layout")) { layoutItems }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    /// Menü açan, bağlantı görünümlü parça. `wraps`: uzun olabilen parça
    /// (pencere başlığı, ekran ya da masaüstü adı); satıra sığmazsa alt satıra kırılır, sütunu
    /// genişletmez.
    @ViewBuilder
    private func part<Content: View>(_ text: String, help: String, wraps: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        if wraps {
            Menu {
                content()
            } label: {
                Text(text)
                    .underline(pattern: .dot)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(help)
        } else {
            Menu {
                content()
            } label: {
                Text(text)
                    .underline(pattern: .dot)
                    .foregroundStyle(Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(help)
        }
    }

    private var screenName: String {
        store.screens(for: mode).first { $0.id == destination.screen }?.name ?? destination.screen
    }

    private func desktopName(_ desktop: Int) -> String {
        store.desktopName(screen: destination.screen, desktop: desktop, mode: mode)
            .map { L("Desktop %ld · %@", desktop, $0) } ?? L("Desktop %ld", desktop)
    }

    /// Bu ekranda seçilebilecek masaüstü sayısı: bağlıysa gerçek sayı, plan
    /// ve şu anki hedef hangisi büyükse.
    private func desktopCount(on screen: String) -> Int {
        max(ui.desktopCounts[screen] ?? 1,
            store.document.plannedDesktops(mode: mode, screen: screen),
            screen == destination.screen ? destination.desktop : 1, 1)
    }

    @ViewBuilder private var screenItems: some View {
        ForEach(store.screens(for: mode)) { screen in
            MenuCheck(screen.name, checked: screen.id == destination.screen) {
                var updated = destination
                updated.screen = screen.id
                updated.desktop = min(destination.desktop, desktopCount(on: screen.id))
                setDestination(updated)
            }
        }
    }

    @ViewBuilder private var desktopItems: some View {
        ForEach(1...desktopCount(on: destination.screen), id: \.self) { desktop in
            MenuCheck(desktopName(desktop), checked: desktop == destination.desktop) {
                var updated = destination
                updated.desktop = desktop
                setDestination(updated)
            }
        }
    }

    @ViewBuilder private var layoutItems: some View {
        ForEach(BasicLayoutRow.basic, id: \.self) { layout in
            MenuCheck(layout.label, checked: layout == destination.layout) {
                var updated = destination
                updated.layout = layout
                setDestination(updated)
            }
        }
        Divider()
        Button(L("Other layouts…"), action: showAdvanced)
    }
}

// MARK: - Temel düzenler

/// Gelişmiş bölüm kapalıyken görünen dört düzen: tamamı, sol yarı, sağ yarı,
/// olduğu gibi (yalnız masaüstü). Kayıtlı düzen bunlardan biri değilse o da
/// seçili olarak sona eklenir.
struct BasicLayoutRow: View {

    static let basic: [WindowLayout] = [.full, .leftHalf, .rightHalf, .anyFrame]

    @Binding var layout: WindowLayout

    var body: some View {
        let shown = Self.basic.contains(layout) ? Self.basic : Self.basic + [layout]
        VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
            ForEach(shown, id: \.self) { candidate in
                let isSelected = candidate == layout
                Button {
                    layout = candidate
                } label: {
                    VStack(spacing: 3) {
                        glyph(candidate)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(Self.shortLabel(candidate))
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    }
                    // Döşemeler sütunu paylaşır: beşinci (özel) döşeme de
                    // sütunu taşırmaz.
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(candidate.isDesktopOnly
                      ? L("The window follows this desktop; Deskmap never moves or resizes it there")
                      : candidate.label)
                .accessibilityLabel(candidate.label)
            }
        }
        // Özel düzenin tam adı döşemeye sığmaz; altında okunur.
        if !Self.basic.contains(layout) {
            Text(layout.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        }
    }

    /// Döşeme yazısı (saf): temel düzenlerin adı, başka bir düzen için kısa
    /// "Özel" (tam adı ipucunda ve satırın altında).
    static func shortLabel(_ layout: WindowLayout) -> String {
        if layout.isDesktopOnly { return L("As it is") }
        return basic.contains(layout) ? layout.label : L("Custom")
    }

    @ViewBuilder private func glyph(_ layout: WindowLayout) -> some View {
        if layout.isDesktopOnly {
            Image(systemName: "macwindow")
                .font(.system(size: 13))
                .frame(width: 30, height: 20)
        } else {
            LayoutGlyph(preset: layout)
        }
    }
}

// MARK: - Gelişmiş bölüm

/// "Gelişmiş ▸" düğmesi; durum `UIState.showAdvanced`'te, paneller arasında
/// korunur (bir kez açan sonraki pencerede de açık görür).
struct AdvancedToggle: View {

    @EnvironmentObject private var ui: UIState
    var summary: String

    var body: some View {
        Button {
            ui.showAdvanced.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ui.showAdvanced ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 10)
                Text(L("Advanced"))
                    .font(.callout.weight(.medium))
                if !ui.showAdvanced {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}
