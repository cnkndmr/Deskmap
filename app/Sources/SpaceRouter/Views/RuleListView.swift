import SwiftUI

struct RuleListView: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var screenService: ScreenService

    let onEdit: (Rule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if store.document.rules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach($store.document.rules) { $rule in
                        RuleRow(rule: $rule, onEdit: { onEdit(rule) })
                            .contextMenu {
                                Button("Düzenle") { onEdit(rule) }
                                Button("Kopyala") { duplicate(rule) }
                                Divider()
                                Button("Sil", role: .destructive) {
                                    store.delete(ruleID: rule.id)
                                }
                            }
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.inset)
            }

            HStack {
                Button {
                    onEdit(newRule())
                } label: {
                    Label("Kural ekle", systemImage: "plus")
                }

                Spacer()

                Text("Sıra önemlidir: ilk eşleşen kural uygulanır.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Henüz kural yok")
                .font(.headline)

            Text("Bir kural, pencere başlığında görünen workspace adını "
                 + "belirli bir monitöre, Desktop'a ve düzene bağlar.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newRule() -> Rule {
        let builtin = store.document.screens.first { $0.role == .builtin }
        let external = store.document.screens.first { $0.role == .external }

        return Rule(
            docked: Destination(
                screen: external?.id ?? builtin?.id ?? "",
                desktop: 1,
                layout: .full),
            undocked: Destination(
                screen: builtin?.id ?? "",
                desktop: 1,
                layout: .full))
    }

    private func duplicate(_ rule: Rule) {
        var copy = rule
        copy.id = UUID().uuidString
        copy.name = rule.name + " kopyası"
        store.addRule(copy)
    }
}

// MARK: - Satır

private struct RuleRow: View {

    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var screenService: ScreenService

    @Binding var rule: Rule
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $rule.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .fontWeight(.medium)

                Text("\(rule.app.name) · \(rule.match.type.localizedName): "
                     + "\(rule.match.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    destinationLabel(
                        symbol: "display.2",
                        destination: rule.docked,
                        active: screenService.isDocked)

                    destinationLabel(
                        symbol: "laptopcomputer",
                        destination: rule.undocked,
                        active: !screenService.isDocked)
                }
            }
            .opacity(rule.enabled ? 1 : 0.5)

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func destinationLabel(
        symbol: String, destination: Destination?, active: Bool
    ) -> some View {
        if let destination {
            let screenName =
                store.screenEntry(withID: destination.screen)?.name
                ?? destination.screen

            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text("\(screenName) · D\(destination.desktop) · "
                     + "\(destination.layout.summary)")
            }
            .font(.caption2)
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .lineLimit(1)
        }
    }
}
