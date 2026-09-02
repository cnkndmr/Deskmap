import SwiftUI

/// Açık pencerelerden uygulama + başlık seçtirir.
/// Kural yazarken doğru `app.name`, `bundleID` ve başlık metnini bulmanın
/// en kolay yolu budur.
struct WindowPickerView: View {

    @EnvironmentObject private var inspector: WindowInspector
    @EnvironmentObject private var accessibility: AccessibilityService

    @State private var searchText = ""

    let onSelect: (ObservedWindow) -> Void
    let onCancel: () -> Void

    init(
        onSelect: @escaping (ObservedWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Açık pencereler")
                    .font(.headline)
                Spacer()
                Button {
                    inspector.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)

            if !accessibility.isTrusted {
                Label("Başlıkları okumak için Erişilebilirlik izni gerekir.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            TextField("Ara", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)

            List(filteredWindows) { window in
                Button {
                    onSelect(window)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.title)
                            .lineLimit(1)
                        Text("\(window.applicationName)  ·  \(window.bundleID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Text("Seçtiğiniz başlık kurala kopyalanır; "
                     + "sonra kısaltıp benzersizleştirebilirsiniz.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Vazgeç", action: onCancel)
            }
            .padding(12)
        }
        .onAppear { inspector.refresh() }
    }

    private var filteredWindows: [ObservedWindow] {
        guard !searchText.isEmpty else { return inspector.windows }

        let needle = searchText.lowercased()
        return inspector.windows.filter {
            $0.title.lowercased().contains(needle)
            || $0.applicationName.lowercased().contains(needle)
            || $0.bundleID.lowercased().contains(needle)
        }
    }
}
