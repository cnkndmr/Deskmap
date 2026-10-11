import AppKit
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
    private func part<Content: View>(_ text: String, help: String, wraps: Bool = false,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        SentenceLink(text: text, help: help, wraps: wraps, content: content)
    }

    private var screenName: String {
        store.screens(for: mode).first { $0.id == destination.screen }?.name ?? destination.screen
    }

    private func desktopName(_ desktop: Int) -> String {
        store.desktopName(screen: destination.screen, desktop: desktop, mode: mode)
            .map { L("Desktop %ld · %@", desktop, $0) } ?? L("Desktop %ld", desktop)
    }

    private var choices: DestinationChoices {
        DestinationChoices(destination: destination, mode: mode, store: store, ui: ui)
    }

    @ViewBuilder private var screenItems: some View {
        let choices = choices
        ForEach(store.screens(for: mode)) { screen in
            MenuCheck(screen.name, checked: screen.id == destination.screen) {
                setDestination(choices.moved(toScreen: screen.id))
            }
        }
    }

    @ViewBuilder private var desktopItems: some View {
        let choices = choices
        ForEach(1...choices.desktopCount(on: destination.screen), id: \.self) { desktop in
            MenuCheck(desktopName(desktop), checked: desktop == destination.desktop) {
                setDestination(choices.moved(toDesktop: desktop))
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

// MARK: - Hedef seçimi

/// Cümlenin ve altındaki seçicilerin ortak hedef hesabı: hangi ekranlar ve
/// kaç masaüstü seçilebilir, seçim hedefi nasıl değiştirir.
@MainActor
struct DestinationChoices {

    let destination: Destination
    let mode: Mode
    let store: Store
    let ui: UIState

    /// Bu ekranda seçilebilecek masaüstü sayısı: bağlıysa gerçek sayı, plan
    /// ve şu anki hedef hangisi büyükse.
    func desktopCount(on screen: String) -> Int {
        Self.desktopCount(real: ui.desktopCounts[screen],
                          planned: store.document.plannedDesktops(mode: mode, screen: screen),
                          current: destination, screen: screen)
    }

    /// Saf karşılığı: en az 1; hedefin kendi ekranında hedef masaüstü de.
    nonisolated static func desktopCount(real: Int?, planned: Int, current: Destination,
                                         screen: String) -> Int {
        max(real ?? 1, planned, screen == current.screen ? current.desktop : 1, 1)
    }

    /// Başka ekrana geçen hedef: masaüstü o ekranda yoksa sonuncusuna iner.
    func moved(toScreen screen: String) -> Destination {
        var updated = destination
        updated.screen = screen
        updated.desktop = min(destination.desktop, desktopCount(on: screen))
        return updated
    }

    func moved(toDesktop desktop: Int) -> Destination {
        var updated = destination
        updated.desktop = desktop
        return updated
    }
}

/// Cümlenin altında etiketli iki açılır menü: Ekran ve Masaüstü. Cümledeki
/// bağlantılarla aynı değişikliği yapar; dar sütunda taşmaz (menü kısalır).
struct DestinationPickers: View {

    let destination: Destination
    let mode: Mode
    let setDestination: (Destination) -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    /// Etiket sütunu: iki dilde de "Masaüstü" sığar.
    private static let labelWidth: CGFloat = 64

    var body: some View {
        let choices = DestinationChoices(destination: destination, mode: mode, store: store, ui: ui)
        VStack(alignment: .leading, spacing: 6) {
            row(L("Display")) {
                Picker(L("Display"), selection: Binding(
                    get: { destination.screen },
                    set: { setDestination(choices.moved(toScreen: $0)) })) {
                    ForEach(store.screens(for: mode)) { screen in
                        Text(screen.name).tag(screen.id)
                    }
                    // Hedef ekran planın ekranları arasında değilse de seçili görünsün.
                    if !store.screens(for: mode).contains(where: { $0.id == destination.screen }) {
                        Text(destination.screen).tag(destination.screen)
                    }
                }
            }
            row(L("Desktop")) {
                Picker(L("Desktop"), selection: Binding(
                    get: { destination.desktop },
                    set: { setDestination(choices.moved(toDesktop: $0)) })) {
                    ForEach(1...choices.desktopCount(on: destination.screen), id: \.self) { desktop in
                        Text(store.desktopName(screen: destination.screen, desktop: desktop, mode: mode)
                            .map { L("Desktop %ld · %@", desktop, $0) } ?? L("Desktop %ld", desktop))
                            .tag(desktop)
                    }
                }
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Neden burada?

/// Panelin altındaki "Neden burada?" kutusu: hangi sabitleme pencereyi
/// nereye gönderiyor (`Routing.reason`) ve ne zaman geri koyuyor.
struct WhyHereBox: View {

    let reason: String
    let note: String

    /// Cümle başı (saf): ilk harf büyük, dilin kuralıyla ("i" → "İ").
    nonisolated static func sentence(_ text: String, locale: Locale = .current) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L("Why here?"), systemImage: "questionmark.circle")
                .font(.caption.weight(.semibold))
            Text(reason)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1))
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

/// Kural cümlesindeki menü bağlantısı: düz vurgu rengi; alt çizgi ve el imleci
/// yalnız fare üstündeyken. Sürekli kesikli alt çizgi göz yoruyordu.
private struct SentenceLink<Content: View>: View {
    let text: String
    let help: String
    let wraps: Bool
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            Text(text)
                .underline(hovering)
                .foregroundStyle(Color.accentColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: !wraps, vertical: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: !wraps, vertical: false)
        .onHover { inside in
            guard inside != hovering else { return }
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if hovering { NSCursor.pop() }
        }
        .help(help)
    }
}

