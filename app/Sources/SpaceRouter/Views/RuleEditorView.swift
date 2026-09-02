import SwiftUI

struct RuleEditorView: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var inspector: WindowInspector

    @State private var draft: Rule
    @State private var dockedEnabled: Bool
    @State private var undockedEnabled: Bool
    @State private var showingWindowPicker = false

    private let onSave: (Rule) -> Void
    private let onCancel: () -> Void

    init(
        rule: Rule,
        onSave: @escaping (Rule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: rule)
        _dockedEnabled = State(initialValue: rule.docked != nil)
        _undockedEnabled = State(initialValue: rule.undocked != nil)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    generalSection
                    applicationSection
                    matchSection
                    destinationsSection
                }
                .padding(12)
            }

            Divider()

            HStack {
                if !issues.isEmpty {
                    Label(issues[0], systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                Spacer()

                Button("Vazgeç", action: onCancel)

                Button("Kaydet") {
                    draft.docked = dockedEnabled ? draft.docked : nil
                    draft.undocked = undockedEnabled ? draft.undocked : nil
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!issues.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingWindowPicker) {
            WindowPickerView { window in
                draft.app = AppSpec(
                    name: window.applicationName,
                    bundleID: window.bundleID)
                draft.match.value = window.title
                if draft.name == "Yeni kural" {
                    draft.name = "\(window.applicationName) · \(window.title)"
                }
                showingWindowPicker = false
            } onCancel: {
                showingWindowPicker = false
            }
            .frame(width: 520, height: 420)
        }
    }

    // MARK: - Doğrulama

    private var issues: [String] {
        var rule = draft
        rule.docked = dockedEnabled ? draft.docked : nil
        rule.undocked = undockedEnabled ? draft.undocked : nil
        return rule.validationIssues
    }

    // MARK: - Bölümler

    private var generalSection: some View {
        GroupBox("Kural") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Ad", text: $draft.name)
                Toggle("Kural etkin", isOn: $draft.enabled)
            }
            .padding(6)
        }
    }

    private var applicationSection: some View {
        GroupBox("Uygulama") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Uygulama adı (ör. Safari, Code)",
                              text: $draft.app.name)

                    Button {
                        inspector.refresh()
                        showingWindowPicker = true
                    } label: {
                        Label("Açık pencerelerden seç", systemImage: "macwindow")
                    }
                }

                TextField(
                    "Bundle ID (isteğe bağlı, ör. com.microsoft.VSCode)",
                    text: Binding(
                        get: { draft.app.bundleID ?? "" },
                        set: { draft.app.bundleID = $0.isEmpty ? nil : $0 }))

                Text("Uygulama adı Finder'daki dosya adından farklı olabilir. "
                     + "Visual Studio Code'un adı \"Code\"dur. "
                     + "Bundle ID verirseniz eşleşme kesinleşir.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private var matchSection: some View {
        GroupBox("Pencere başlığı eşleşmesi") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Yöntem", selection: $draft.match.type) {
                    ForEach(MatchType.allCases) { type in
                        Text(type.localizedName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Aranacak metin", text: $draft.match.value)

                Text(draft.match.type.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                matchPreview
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var matchPreview: some View {
        let candidates = inspector.windows.filter {
            MatchEvaluator.matches(draft, window: $0)
        }

        HStack(spacing: 6) {
            Button {
                inspector.refresh()
            } label: {
                Label("Şimdi test et", systemImage: "arrow.clockwise")
            }
            .font(.caption)

            if draft.match.type == .pattern {
                Text("Lua deseni burada önizlenemez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if inspector.refreshedAt == nil {
                Text("Açık pencerelere karşı deneyin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if candidates.isEmpty {
                Label("Şu an eşleşen pencere yok",
                      systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("\(candidates.count) pencere eşleşiyor",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            DestinationEditor(
                title: "Harici monitör bağlıyken",
                symbol: "display.2",
                isEnabled: $dockedEnabled,
                destination: Binding(
                    get: { draft.docked ?? Destination() },
                    set: { draft.docked = $0 }))

            DestinationEditor(
                title: "Yalnızca dahili ekranda",
                symbol: "laptopcomputer",
                isEnabled: $undockedEnabled,
                destination: Binding(
                    get: { draft.undocked ?? Destination() },
                    set: { draft.undocked = $0 }))
        }
    }
}

// MARK: - Hedef düzenleyici

private struct DestinationEditor: View {

    @EnvironmentObject private var store: RuleStore

    let title: String
    let symbol: String

    @Binding var isEnabled: Bool
    @Binding var destination: Destination

    @State private var showsCustomLayout = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $isEnabled) {
                    Label(title, systemImage: symbol)
                }

                if isEnabled {
                    Picker("Ekran", selection: $destination.screen) {
                        if store.document.screens.isEmpty {
                            Text("Kayıtlı ekran yok").tag("")
                        }
                        ForEach(store.document.screens) { screen in
                            Text("\(screen.name) — \(screen.role.localizedName)")
                                .tag(screen.id)
                        }
                    }

                    Stepper(
                        "Desktop \(destination.desktop)",
                        value: $destination.desktop,
                        in: 1...16)

                    Picker("Düzen", selection: layoutSelection) {
                        ForEach(Layout.presets, id: \.name) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                        Text("Özel…").tag(customTag)
                    }

                    if showsCustomLayout
                        || destination.layout.presetName == nil {
                        customLayoutControls
                    }

                    Text("Desktop numarası, o ekrandaki normal masaüstü "
                         + "sırasıdır. Tam ekran uygulamalar sayılmaz.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
    }

    private let customTag = "__custom__"

    private var layoutSelection: Binding<String> {
        Binding(
            get: {
                destination.layout.presetName ?? customTag
            },
            set: { selection in
                if selection == customTag {
                    showsCustomLayout = true
                } else if let preset = Layout.presets.first(
                    where: { $0.name == selection }) {
                    destination.layout = preset.layout
                    showsCustomLayout = false
                }
            })
    }

    private var customLayoutControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            ratioSlider("Sol kenar",  value: $destination.layout.x)
            ratioSlider("Üst kenar",  value: $destination.layout.y)
            ratioSlider("Genişlik",   value: $destination.layout.w)
            ratioSlider("Yükseklik",  value: $destination.layout.h)
        }
    }

    private func ratioSlider(
        _ label: String, value: Binding<Double>
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)

            Slider(value: value, in: 0...1, step: 0.05)

            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
        }
    }
}
