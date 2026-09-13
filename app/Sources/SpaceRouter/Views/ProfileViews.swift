import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Üst çubuğun altındaki profil satırı: çipler (tıkla = geç; seçiliye
/// tekrar tıkla = panel), "+" (yeni boş profil) ve içe aktar.
struct ProfileBar: View {

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
                .help("Profiller: her biri ayrı bir pin kümesi")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.profiles) { profile in
                        chip(profile)
                    }
                    Button {
                        store.addProfile()
                        ui.panel = .profile
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Yeni boş profil")
                    .accessibilityLabel("Yeni boş profil")
                }
                .padding(.vertical, 1)
            }

            Button {
                ui.panel = nil
                ProfileFiles.importProfile(into: store)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Profili dosyadan içe aktar (.spacerouter.json)")
            .accessibilityLabel("Profili dosyadan içe aktar")
        }
        .font(.caption)
    }

    private func chip(_ profile: Profile) -> some View {
        let isActive = profile.id == store.document.activeProfileID
        return Button {
            if isActive {
                // Açık olan başka bir panel (pin, geçici pin) varsa yerini alır.
                ui.toggle(.profile)
            } else {
                ui.panel = nil
                store.switchProfile(to: profile.id)
            }
        } label: {
            HStack(spacing: 4) {
                if isActive {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                }
                Text(profile.name).lineLimit(1)
                Text("\(profile.rules.count)")
                    .font(.caption2)
                    .foregroundStyle(isActive ? Color.white.opacity(0.8) : Color.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isActive ? Color.accentColor : Color.primary.opacity(0.06)))
            .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(isActive ? "Aktif profil — ad, kopya, dışa aktar, sil için tıkla"
                       : "Bu profile geç (\(profile.rules.count) pin)")
    }
}

/// Aktif profil paneli: ad, kopya, dışa aktar, sil.
struct ProfilePanel: View {

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var ui: UIState

    @State private var name = ""

    var body: some View {
        if let profile = store.activeProfile {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.secondary)
                    TextField("Profil adı", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit { store.renameProfile(profile.id, to: name) }
                    if name.trimmingCharacters(in: .whitespaces) != profile.name {
                        Button("Kaydet") { store.renameProfile(profile.id, to: name) }
                            .controlSize(.small)
                    }
                    Spacer()
                    Button {
                        ui.panel = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Kapat (Esc)")
                    .accessibilityLabel("Kapat")
                }

                HStack(spacing: 8) {
                    Text(profile.rules.count == 1 ? "1 pin" : "\(profile.rules.count) pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.addProfile(named: "\(profile.name) kopyası", copyingCurrent: true)
                        name = store.activeProfile?.name ?? ""
                    } label: {
                        Label("Kopyala", systemImage: "doc.on.doc")
                    }
                    .help("Bu pinlerle yeni profil oluştur")

                    Button {
                        ProfileFiles.exportProfile(profile.id, from: store)
                    } label: {
                        Label("Dışa aktar", systemImage: "square.and.arrow.up")
                    }
                    .help("\(profile.name).spacerouter.json olarak kaydet")

                    Button(role: .destructive) {
                        store.deleteProfile(profile.id)
                        name = store.activeProfile?.name ?? ""
                    } label: {
                        Label("Sil", systemImage: "trash")
                    }
                    .disabled(store.profiles.count < 2)
                    .help(store.profiles.count < 2 ? "Son profil silinemez" : "Profili sil")
                }
                .controlSize(.small)
            }
            .onAppear { name = profile.name }
            .onChange(of: profile.id) { _ in name = store.activeProfile?.name ?? "" }
        }
    }
}

// MARK: - Dosya diyalogları

/// NSSavePanel / NSOpenPanel. Menü çubuğu penceresi diyalog açılınca
/// kapanır; diyalog uygulama düzeyinde çalıştığı için sorun olmaz.
@MainActor
enum ProfileFiles {

    static var contentType: UTType { .json }

    static func exportProfile(_ id: String, from store: Store) {
        guard let profile = store.profiles.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.title = "Profili dışa aktar"
        panel.nameFieldStringValue = "\(safeFileName(profile.name)).\(ProfileExport.fileExtension)"
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData(for: id).write(to: url, options: .atomic)
        } catch {
            store.report("Dışa aktarılamadı: \(error.localizedDescription)")
        }
    }

    static func importProfile(into store: Store) {
        let panel = NSOpenPanel()
        panel.title = "Profili içe aktar"
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try store.importProfile(from: data)
        } catch {
            store.report("İçe aktarılamadı: \(error.localizedDescription)")
        }
    }

    private static func safeFileName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "profil" : cleaned
    }
}
