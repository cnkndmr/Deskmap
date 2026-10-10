import SwiftUI

// MARK: - Masaüstü önizlemesi

/// Bir masaüstünün küçük resmi: ekranın oranında çerçeve, içinde pencereler
/// kayıtlı (ya da şu anki) düzenlerinde kutu olarak. Sabit pencere mavi
/// çerçeveli, sabit olmayan kesikli ve soluk, açık penceresi olmayan
/// sabitleme daha da soluk. Kutuya tıklamak satıra tıklamakla aynıdır.
struct DesktopPreview: View {

    struct Item: Identifiable {
        let id: String
        let bundleID: String
        let title: String
        let layout: WindowLayout
        let pinned: Bool
        /// Penceresi açık mı (kapalı sabitleme soluk çizilir).
        let isOpen: Bool
        let isSelected: Bool
        let dimmed: Bool
        let highlighted: Bool
        let action: () -> Void
    }

    /// Önizlemenin genişliği; yükseklik ekranın oranından.
    nonisolated static let width: CGFloat = 150

    let screenSize: CGSize
    let items: [Item]

    /// Önizleme boyutu (saf): sabit genişlik, ekranın oranında yükseklik
    /// (ultra geniş ve dikey ekranda makul sınırlar içinde).
    nonisolated static func size(screenSize: CGSize) -> CGSize {
        let aspect = screenSize.height > 0 ? screenSize.width / screenSize.height : 1.6
        return CGSize(width: width, height: (width / min(max(aspect, 0.6), 3.6)).rounded())
    }

    var body: some View {
        let size = Self.size(screenSize: screenSize)
        let frame = CGRect(origin: .zero, size: size)
        let scale = size.width / max(screenSize.width, 1)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.06))
            // Sabit olmayanlar altta, sabitler üstte çizilir.
            ForEach(items.sorted { !$0.pinned && $1.pinned }) { item in
                let rect = item.layout.rect(in: frame, pointsPerUnit: scale).insetBy(dx: 1, dy: 1)
                box(item, size: rect.size)
                    .offset(x: rect.minX, y: rect.minY)
            }
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Desktop preview"))
    }

    private func box(_ item: Item, size: CGSize) -> some View {
        let tint: Color = item.highlighted ? .orange : (item.pinned ? .accentColor : .secondary)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(item.pinned ? Color.accentColor.opacity(item.isOpen ? 0.22 : 0.08)
                                  : Color.primary.opacity(0.07))
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(tint.opacity(item.isSelected || item.highlighted ? 1 : 0.7),
                              style: StrokeStyle(lineWidth: item.isSelected || item.highlighted ? 1.6 : 1,
                                                 dash: item.pinned && item.isOpen ? [] : [3, 2]))
            if size.width > 18, size.height > 14 {
                HStack(spacing: 3) {
                    AppIcon(bundleID: item.bundleID, size: 11)
                    if size.width > 54 {
                        Text(item.title)
                            .font(.system(size: 8))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(2)
            }
        }
        .frame(width: max(size.width, 4), height: max(size.height, 4))
        .opacity(item.dimmed ? 0.25 : (item.isOpen ? 1 : 0.6))
        .contentShape(Rectangle())
        .onTapGesture(perform: item.action)
        .help(item.title)
    }
}

// MARK: - Son hareketler

/// Üst çubuktaki "Son hareketler" düğmesinin paneli: Deskmap'in hangi
/// pencereyi ne zaman nereye taşıdığı, en yenisi başta.
struct ActivityLogView: View {

    @EnvironmentObject private var router: Router
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Recent moves")).font(.headline)
            Text(L("Pinned windows Deskmap sent to their desktop, newest first: a window opens, or was moved away by hand, and Deskmap puts it back."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if router.actionLog.isEmpty {
                Text(L("Deskmap has not moved any window since it started."))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(router.actionLog) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Text(entry.date, format: .dateTime.hour().minute())
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                Text(entry.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.caption)
                            .padding(.vertical, 5)
                            .overlay(alignment: .top) { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
            if let entry = store.undoBuffer.entry, store.undoBuffer.isVisible(at: Date()) {
                Divider()
                Button {
                    store.undo()
                } label: {
                    Label(L("%@ · Undo", entry.label), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}

// MARK: - Arama vurgusu

extension View {
    /// Arama sürerken uymayan öğeyi soluklaştırır, uyanı turuncu çerçeveyle
    /// vurgular.
    func searchLook(dimmed: Bool, highlighted: Bool, cornerRadius: CGFloat = 6) -> some View {
        self
            .opacity(dimmed ? 0.3 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.orange, lineWidth: highlighted ? 1.5 : 0)
                    .allowsHitTesting(false))
    }
}
