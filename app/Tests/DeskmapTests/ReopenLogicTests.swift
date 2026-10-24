import ApplicationServices
import Foundation
import Testing
@testable import Deskmap

/// Yeniden açmanın AX'e gitmeyen dalları: Finder'ın özel konumları,
/// VS Code çalışma alanı klasörü, yol çubuğu zinciri ve uygulaması
/// bulunamayan kural. Disk yazan testler geçici dizinde.
@MainActor
struct ReopenLogicTests {

    // MARK: - Finder özel konumları

    /// "Recents" gibi özel konum başlığı Finder.app içindeki küçük uygulamaya
    /// çevrilir (baştaki/sondaki boşluk önemsiz); klasör adı ya da boş
    /// başlık özel konum değildir.
    @Test func finderLocationResolvesOnlyKnownSpecialPlaces() throws {
        let recents = try #require(Reopen.finderLocation(named: "Recents"))
        #expect(recents.lastPathComponent == "Recents.app")
        #expect(recents.path.hasPrefix(Reopen.finderLocations.path))
        #expect(Reopen.finderLocation(named: "  Recents ") == recents)
        #expect(Reopen.finderLocation(named: "Project Folder") == nil)
        #expect(Reopen.finderLocation(named: "") == nil)
        #expect(Reopen.finderLocation(named: "   ") == nil)
    }

    /// Finder penceresi özel konumdaysa adres başlıktan okunur; pencere
    /// ağacı hiç dolaşılmaz (Recents ağacı dakikalarca sürüyordu).
    @Test func finderCaptureUsesTheTitleForSpecialPlaces() {
        // Sistem öğesi: başlık yolunda AX'e hiç sorulmamalı.
        let element = AXUIElementCreateSystemWide()
        let url = Reopen.capture(element, bundleID: Reopen.finder, title: "Recents")
        #expect(url?.lastPathComponent == "Recents.app")
    }

    // MARK: - VS Code çalışma alanı

    /// Başlıkta klasör yoksa ya da boşsa dosyanın kendisi açılır (nil).
    /// Klasör adı en yakın üst klasörden aranır.
    @Test func workspaceFolderEdgeCases() {
        let file = URL(fileURLWithPath: "/tmp/ws/app/src/app/main.swift")
        #expect(Reopen.workspaceFolder(of: file, title: "") == nil)
        #expect(Reopen.workspaceFolder(of: file, title: "main.swift — ") == nil)
        // Aynı adlı iki üst klasör: dosyaya en yakın olan.
        #expect(Reopen.workspaceFolder(of: file, title: "main.swift — app")?.path
                == "/tmp/ws/app/src/app")
        // Kök "/" aranmaz.
        #expect(Reopen.workspaceFolder(of: URL(fileURLWithPath: "/main.swift"),
                                       title: "main.swift — tmp") == nil)
    }

    // MARK: - Yol çubuğu zinciri

    /// Başlıkla aynı adlı öğe yoksa ve zincirdeki hiçbir öğe diskte klasör
    /// değilse adres yok (var olmayan yola pencere açılmaz).
    @Test func chainWithoutExistingFolderGivesNothing() {
        let base = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let chain = [base, base.appendingPathComponent("a"), base.appendingPathComponent("a/b")]
        #expect(Reopen.chainFolder(chain, title: "zzz") == nil)
        // Başlık uyuyorsa disk denetimi gerekmez: o öğe klasör sayılır.
        #expect(Reopen.chainFolder(chain, title: "a")?.path == base.appendingPathComponent("a").path)
        #expect(Reopen.chainFolder([], title: "a") == nil)
    }

    /// Kökten başlayan zincir ("/" ile biten üst öğe) kabul edilir; ad
    /// önekini paylaşan kardeş ("/x/ab" ↔ "/x/a") zincir sayılmaz.
    @Test func chainRequiresRealNesting() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskmap-chain-\(UUID().uuidString)")
        let inner = base.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = URL(fileURLWithPath: "/")
        let chain = [root, base, inner]
        #expect(Reopen.chainFolder(chain, title: "?")?.standardizedFileURL.path
                == inner.standardizedFileURL.path)
        let sibling = base.appendingPathComponent("ab")
        #expect(Reopen.chainFolder([inner, sibling], title: "ab") == nil)
    }

    // MARK: - Açma

    /// Kuralın uygulaması bulunamazsa hiçbir şey açılmaz, sonuç `noApp`
    /// (kullanıcıya "uygulama yok" denir).
    @Test func openWithUnknownAppReportsNoApp() {
        let unknown = "Deskmap Test App \(UUID().uuidString)"
        let byName = Rule(appName: unknown, bundleID: "", tokens: [])
        #expect(Reopen.open(rule: byName, target: nil) == .noApp)
        let byBundle = Rule(appName: unknown, bundleID: "com.example.missing.\(UUID().uuidString)",
                            tokens: [])
        #expect(Reopen.open(rule: byBundle, target: ReopenTarget(
            url: "https://example.com/", seenAt: Date())) == .noApp)
    }
}
