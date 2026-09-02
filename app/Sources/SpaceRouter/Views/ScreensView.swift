import SwiftUI

struct ScreensView: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var screenService: ScreenService

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                GroupBox("Şu an bağlı ekranlar") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(screenService.screens) { screen in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: screen.isBuiltin
                                      ? "laptopcomputer" : "display")
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(screen.name)
                                    Text(screen.uuid)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                Spacer()

                                if isRegistered(screen) {
                                    Label("Kayıtlı", systemImage: "checkmark")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }

                        Button {
                            store.syncScreens(with: screenService.screens)
                        } label: {
                            Label("Bağlı ekranları yapılandırmaya ekle",
                                  systemImage: "plus.rectangle.on.rectangle")
                        }
                        .padding(.top, 4)
                    }
                    .padding(6)
                }

                GroupBox("Kayıtlı ekranlar") {
                    if store.document.screens.isEmpty {
                        Text("Henüz kayıt yok. Yukarıdaki düğmeyle ekleyin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(6)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($store.document.screens) { $entry in
                                registeredRow($entry)
                            }
                        }
                        .padding(6)
                    }
                }

                Text("Rol seçimi dock tespitini belirler: harici olarak "
                     + "işaretlenmiş ekranlardan biri bağlıysa kuralların "
                     + "\"docked\" profili uygulanır.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private func registeredRow(_ entry: Binding<ScreenEntry>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.wrappedValue.name)
                Text("id: \(entry.wrappedValue.id)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: entry.role) {
                ForEach(ScreenEntry.Role.allCases, id: \.self) { role in
                    Text(role.localizedName).tag(role)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Button(role: .destructive) {
                store.document.screens.removeAll {
                    $0.id == entry.wrappedValue.id
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func isRegistered(_ screen: DetectedScreen) -> Bool {
        store.document.screens.contains { $0.uuid == screen.uuid }
    }
}
