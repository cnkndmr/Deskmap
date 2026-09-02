import SwiftUI

/// Açık pencerelerden birini seçip başlığın hangi parçasının kural
/// olacağını işaretleme akışı. İki adım, metin girişi yok.
struct AddWindowView: View {

    let mode: Mode
    let onAdd: (Rule) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService

    @State private var windows: [AXWindow] = []
    @State private var selected: AXWindow?
    @State private var segments: [String] = []
    @State private var chosen: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            if let window = selected {
                tokenPicker(for: window)
            } else {
                windowList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { windows = AX.allWindows().sorted(by: Self.order) }
    }

    // MARK: - 1. Pencere seç

    private var windowList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hangi pencere?")
                    .font(.headline)
                Spacer()
                Button {
                    windows = AX.allWindows().sorted(by: Self.order)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Button("Vazgeç", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            if windows.isEmpty {
                Spacer()
                Text("Başlığı olan açık pencere bulunamadı.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(windows) { window in
                            Button {
                                choose(window)
                            } label: {
                                HStack(spacing: 8) {
                                    AppIcon(bundleID: window.bundleID, size: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(window.title).lineLimit(1)
                                        Text(window.appName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if isCovered(window) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .help("Zaten bir kurala uyuyor")
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private func isCovered(_ window: AXWindow) -> Bool {
        store.document.rules.contains {
            $0.matches(bundleID: window.bundleID, appName: window.appName,
                       title: window.title)
        }
    }

    private func choose(_ window: AXWindow) {
        segments = Self.split(window.title)
        // Varsayılan: uygulama adı olmayan son parça (çalışma alanı adı
        // genellikle başlığın sonundadır).
        let candidates = segments.indices.filter {
            segments[$0].caseInsensitiveCompare(window.appName) != .orderedSame
        }
        chosen = Set([candidates.last ?? segments.indices.last].compactMap { $0 })
        selected = window
    }

    // MARK: - 2. Parça seç

    private func tokenPicker(for window: AXWindow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                AppIcon(bundleID: window.bundleID, size: 22)
                Text(window.appName).font(.headline)
                Spacer()
            }

            Text("Başlığın hangi parçası bu pencereyi tanımlıyor?")
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(segments.indices, id: \.self) { index in
                    let isOn = chosen.contains(index)
                    Button {
                        if isOn { chosen.remove(index) } else { chosen.insert(index) }
                    } label: {
                        Text(segments[index])
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(isOn ? Color.accentColor
                                                    : Color.primary.opacity(0.08)))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Seçili parçalar başlıkta geçen her pencere bu kurala uyar. "
                 + "Dosya adı gibi değişen parçaları seçmeyin.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            HStack {
                Text(matchCount(for: window) == 1
                     ? "Şu an 1 pencere uyuyor"
                     : "Şu an \(matchCount(for: window)) pencere uyuyor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Ekle") { add(window) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty)
            }
        }
        .padding(16)
    }

    private var tokens: [String] {
        chosen.sorted().map { segments[$0] }
    }

    private func matchCount(for window: AXWindow) -> Int {
        let draft = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
        return windows.filter {
            draft.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
        }.count
    }

    private func add(_ window: AXWindow) {
        var rule = Rule(appName: window.appName, bundleID: window.bundleID, tokens: tokens)
        // Pencere şu an neredeyse kural oradan başlar; sonra sürüklenir.
        if mode == screens.mode,
           let placement = Router.locate(window, screens: screens.screens) {
            rule[mode] = Destination(screen: placement.screen, desktop: placement.desktop)
        } else {
            rule[mode] = Destination(screen: "builtin", desktop: 1)
        }
        onAdd(rule)
    }

    // MARK: - Yardımcılar

    /// Başlığı yaygın ayraçlardan böler: " — ", " – ", " - ", " | ", " · ", " • ", " : "
    static func split(_ title: String) -> [String] {
        let separator = try! Regex(#"\s*[—–|·•]\s*|\s+[-:]\s+"#)
        let cleaned = title.split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: #"^[●•*]\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? [title] : cleaned
    }

    private static func order(_ a: AXWindow, _ b: AXWindow) -> Bool {
        (a.appName.lowercased(), a.title.lowercased())
            < (b.appName.lowercased(), b.title.lowercased())
    }
}

private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed
                          ? Color.accentColor.opacity(0.2) : Color.clear))
    }
}
