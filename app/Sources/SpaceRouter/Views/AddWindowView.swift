import SwiftUI

/// Açık bir pencere ya da çalışan bir uygulama seçip başlığın hangi
/// parçasının kural olacağını işaretleme akışı. İki adım, metin girişi yok.
struct AddWindowView: View {

    let mode: Mode
    let onAdd: (Rule) -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var screens: ScreenService

    /// Seçilen şey: bir pencere ya da yalnızca uygulama.
    private struct Pick: Equatable {
        let appName: String
        let bundleID: String
        let window: AXWindow?
    }

    @State private var windows: [AXWindow] = []
    @State private var apps: [AX.App] = []
    @State private var isLoading = true
    @State private var pick: Pick?
    @State private var segments: [String] = []
    @State private var chosen: Set<Int> = []
    @State private var appWide = false

    var body: some View {
        VStack(spacing: 0) {
            if let pick {
                tokenPicker(for: pick)
            } else {
                windowList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        let loaded = await Task.detached(priority: .userInitiated) {
            (AX.allWindows().sorted(by: Self.order), AX.runningApps())
        }.value
        windows = loaded.0
        apps = loaded.1
        isLoading = false
    }

    // MARK: - 1. Pencere / uygulama seç

    private var windowList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hangi pencere?")
                    .font(.headline)
                if isLoading {
                    ProgressView().controlSize(.small).padding(.leading, 6)
                }
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isLoading)
                Button("Vazgeç", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
                    Section {
                        if windows.isEmpty && !isLoading {
                            Text("Açık pencere bulunamadı.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        ForEach(windows) { window in
                            row(icon: window.bundleID,
                                title: window.title.isEmpty ? "Adsız pencere" : window.title,
                                subtitle: window.appName,
                                covered: isCovered(window)) {
                                choose(Pick(appName: window.appName,
                                            bundleID: window.bundleID,
                                            window: window))
                            }
                        }
                    } header: {
                        sectionHeader("Açık pencereler")
                    }

                    Section {
                        ForEach(apps) { app in
                            row(icon: app.bundleID,
                                title: app.name,
                                subtitle: "tüm pencereleri",
                                covered: isCovered(app)) {
                                choose(Pick(appName: app.name,
                                            bundleID: app.bundleID,
                                            window: nil))
                            }
                        }
                    } header: {
                        sectionHeader("Uygulamalar")
                    }
                }
                .padding(6)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial)
    }

    private func row(icon: String, title: String, subtitle: String,
                     covered: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AppIcon(bundleID: icon, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if covered {
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

    private func isCovered(_ window: AXWindow) -> Bool {
        store.document.rules.contains {
            $0.matches(bundleID: window.bundleID, appName: window.appName,
                       title: window.title)
        }
    }

    private func isCovered(_ app: AX.App) -> Bool {
        store.document.rules.contains { $0.isAppWide && $0.bundleID == app.bundleID }
    }

    private func choose(_ pick: Pick) {
        if let window = pick.window, !window.title.isEmpty {
            segments = Self.split(window.title)
            // Varsayılan: uygulama adı olmayan son parça (çalışma alanı adı
            // genellikle başlığın sonundadır).
            let candidates = segments.indices.filter {
                segments[$0].caseInsensitiveCompare(pick.appName) != .orderedSame
            }
            chosen = Set([candidates.last ?? segments.indices.last].compactMap { $0 })
            appWide = false
        } else {
            segments = []
            chosen = []
            appWide = true
        }
        self.pick = pick
    }

    // MARK: - 2. Parça seç

    private func tokenPicker(for pick: Pick) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    self.pick = nil
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                AppIcon(bundleID: pick.bundleID, size: 22)
                Text(pick.appName).font(.headline)
                Spacer()
            }

            Text(segments.isEmpty
                 ? "Bu uygulamanın bütün pencereleri aynı yere gidecek."
                 : "Başlığın hangi parçası bu pencereyi tanımlıyor?")
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                pill("Tüm pencereler", systemImage: "macwindow.on.rectangle",
                     isOn: appWide) {
                    appWide.toggle()
                    if appWide { chosen = [] }
                }

                ForEach(segments.indices, id: \.self) { index in
                    pill(segments[index], isOn: chosen.contains(index)) {
                        if chosen.contains(index) {
                            chosen.remove(index)
                        } else {
                            chosen.insert(index)
                            appWide = false
                        }
                    }
                }
            }

            Text(appWide
                 ? "Başlığa bakılmaz; \(pick.appName) uygulamasının her penceresi uyar."
                 : "Seçili parçalar başlıkta geçen her pencere bu kurala uyar. "
                   + "Dosya adı gibi değişen parçaları seçmeyin.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            HStack {
                Text(matchCount(for: pick) == 1
                     ? "Şu an 1 pencere uyuyor"
                     : "Şu an \(matchCount(for: pick)) pencere uyuyor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Ekle") { add(pick) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!appWide && chosen.isEmpty)
            }
        }
        .padding(16)
    }

    private func pill(_ text: String, systemImage: String? = nil, isOn: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(text).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var tokens: [String] {
        appWide ? [] : chosen.sorted().map { segments[$0] }
    }

    private func matchCount(for pick: Pick) -> Int {
        let draft = Rule(appName: pick.appName, bundleID: pick.bundleID, tokens: tokens)
        return windows.filter {
            draft.matches(bundleID: $0.bundleID, appName: $0.appName, title: $0.title)
        }.count
    }

    private func add(_ pick: Pick) {
        var rule = Rule(appName: pick.appName, bundleID: pick.bundleID, tokens: tokens)
        // Pencere şu an neredeyse kural oradan başlar; sonra sürüklenir.
        if mode == screens.mode, let window = pick.window,
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

    nonisolated private static func order(_ a: AXWindow, _ b: AXWindow) -> Bool {
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
