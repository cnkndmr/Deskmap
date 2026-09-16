import SwiftUI

/// Başlık parçalarından seçim: "Tüm pencereler" + her parça bir hap.
/// Bir parça seçilince uygulama geneli kapanır; "Tüm pencereler" seçilince
/// parçalar boşalır. Pin panelinde ve pin bilgi panelinde (parça düzenleme)
/// aynı görünüm kullanılır; metin girişi yoktur.
struct TokenPicker: View {

    let segments: [String]
    @Binding var chosen: Set<Int>
    @Binding var appWide: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            TokenPill(L("All windows"), systemImage: "macwindow.on.rectangle", isOn: appWide) {
                appWide.toggle()
                if appWide { chosen = [] }
            }
            ForEach(segments.indices, id: \.self) { index in
                TokenPill(segments[index], isOn: chosen.contains(index)) {
                    if chosen.contains(index) {
                        chosen.remove(index)
                    } else {
                        chosen.insert(index)
                        appWide = false
                    }
                }
            }
        }
    }

    // MARK: Saf yardımcılar

    /// Seçimden kural parçaları: uygulama geneli ise boş, yoksa seçili
    /// parçalar başlıktaki sırayla.
    static func tokens(segments: [String], chosen: Set<Int>, appWide: Bool) -> [String] {
        appWide ? [] : chosen.sorted().compactMap { segments.indices.contains($0) ? segments[$0] : nil }
    }

    /// Mevcut parçalara (büyük/küçük harf duyarsız) eşit olan bölümlerin
    /// dizinleri; var olan bir kuralın parçalarını bir pencere başlığı
    /// üzerinde önceden işaretlemek için.
    static func preselection(segments: [String], tokens: [String]) -> Set<Int> {
        Set(segments.indices.filter { index in
            tokens.contains { $0.caseInsensitiveCompare(segments[index]) == .orderedSame }
        })
    }
}

/// Tek bir parça hapı. `action` verilmezse yalnızca gösterir (salt okunur).
struct TokenPill: View {

    let text: String
    var systemImage: String?
    let isOn: Bool
    var action: (() -> Void)?

    init(_ text: String, systemImage: String? = nil, isOn: Bool,
         action: (() -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.isOn = isOn
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
        .foregroundStyle(isOn ? Color.white : Color.primary)
    }
}
