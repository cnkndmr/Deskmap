import AppKit
import SwiftUI

/// Bir kuralı temsil eden sürüklenebilir çip: uygulama simgesi, başlık
/// parçası ve düzen simgesi. Tıklanınca düzen seçici açılır.
struct RuleChip: View {

    let rule: Rule
    let mode: Mode

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    private var isSelected: Bool { ui.editingRuleID == rule.id }

    var body: some View {
        HStack(spacing: 5) {
            AppIcon(bundleID: rule.bundleID, size: 14)
            Text(rule.title.isEmpty ? rule.appName : rule.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if let layout = rule[mode]?.layout {
                LayoutGlyph(layout: layout, size: CGSize(width: 14, height: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.18)
                                              : Color(nsColor: .controlBackgroundColor)))
        .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                        lineWidth: 1))
        .contentShape(Capsule())
        .draggable(rule.id)
        .onTapGesture { ui.editingRuleID = isSelected ? nil : rule.id }
        .help("\(rule.appName): \(rule.title)\nSürükleyerek taşı, tıklayarak düzeni seç")
    }
}

// MARK: - Düzen simgesi

/// Ekranı temsil eden çerçeve içinde pencerenin kapladığı alan.
struct LayoutGlyph: View {

    let layout: WindowLayout
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            let frame = CGRect(origin: .zero, size: canvasSize).insetBy(dx: 0.5, dy: 0.5)
            context.stroke(
                Path(roundedRect: frame, cornerRadius: 2),
                with: .foreground, lineWidth: 1)
            let inner = layout.rect(in: frame.insetBy(dx: 1.5, dy: 1.5))
            context.fill(Path(roundedRect: inner, cornerRadius: 1), with: .foreground)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Uygulama simgesi

struct AppIcon: View {

    let bundleID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.icon(for: bundleID) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}
