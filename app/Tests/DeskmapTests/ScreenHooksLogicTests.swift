import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// `ScreenHooks` uçtan uca, ama yalnız geçici dizinde: `hooks.json`
/// geçici klasöre yazılır, komutlar oraya bir işaret dosyası bırakır.
/// Gerçek Deskmap verisine ve uygulamalara dokunulmaz. Fare sol tuşu
/// basılıyken değişimler bekletildiği için testler tuşa basılmadan koşar.
@MainActor
struct ScreenHooksLogicTests {

    private final class Sandbox {
        let dir: URL
        var hooksURL: URL { dir.appendingPathComponent("hooks.json") }
        init() throws {
            dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("deskmap-hooks-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: dir) }

        func marker(_ name: String) -> URL { dir.appendingPathComponent(name) }

        /// `hooks.json`'u yazar; değişikliğin fark edilmesi için değiştirme
        /// zamanı açıkça ilerletilir.
        func write(_ text: String, stamp: Date = Date()) throws {
            try Data(text.utf8).write(to: hooksURL)
            try FileManager.default.setAttributes([.modificationDate: stamp],
                                                  ofItemAtPath: hooksURL.path)
        }

        /// Komut `name` dosyasına ortam değişkenlerini yazar.
        func command(_ name: String) -> String {
            "printf '%s|%s|%s|%s' \"$DESKMAP_APP\" \"$DESKMAP_FROM\" \"$DESKMAP_TO\" "
                + "\"$DESKMAP_CAUSE\" > '\(marker(name).path)'"
        }
    }

    private func change(_ id: CGWindowID = 5, app: String = "Editor",
                        bundle: String = "com.example.editor",
                        from: String = "builtin", to: String = "external",
                        cause: ScreenChange.Cause = .move) -> ScreenChange {
        ScreenChange(windowID: id, pid: 1, appName: app, bundleID: bundle,
                     from: .init(id: from, name: from.capitalized),
                     to: .init(id: to, name: to.capitalized), cause: cause)
    }

    private func hooksJSON(_ hooks: [ScreenHook]) throws -> String {
        String(decoding: try JSONEncoder().encode(hooks), as: UTF8.self)
    }

    /// Dosya belirene (komut bitene) dek en çok `timeout` saniye bekler.
    private func waitFor(_ url: URL, timeout: TimeInterval = 5) async -> String? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty { return text }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private var mouseIsDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    /// Eşleşen kancanın komutu ekran değişiminin ortam değişkenleriyle
    /// çalışır; başka uygulamanın kancası çalışmaz.
    @Test func matchingHookRunsWithChangeEnvironment() async throws {
        try #require(!mouseIsDown)
        let box = try Sandbox()
        try box.write(try hooksJSON([
            ScreenHook(app: "com.example.editor", from: "*", to: "external", run: box.command("hit")),
            ScreenHook(app: "Other App", from: nil, to: nil, run: box.command("miss")),
        ]))
        let hooks = ScreenHooks(url: box.hooksURL)
        hooks.fire([change(cause: .display)])
        let text = await waitFor(box.marker("hit"))
        #expect(text == "Editor|builtin|external|display")
        // Pozitif kontrol geldi; eşleşmeyen kanca bu sürede çalışmış olurdu.
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(!FileManager.default.fileExists(atPath: box.marker("miss").path))
    }

    /// Aynı pencere ekrana gidip geri döndüyse (tek turda birleşir) komut
    /// çalışmaz; boş değişim listesi de hiçbir şey yapmaz.
    @Test func roundTripAndEmptyFireRunNothing() async throws {
        try #require(!mouseIsDown)
        let box = try Sandbox()
        try box.write(try hooksJSON([ScreenHook(app: nil, from: nil, to: nil, run: box.command("any"))]))
        let hooks = ScreenHooks(url: box.hooksURL)
        hooks.fire([])
        hooks.fire([change(from: "builtin", to: "external"), change(from: "external", to: "builtin")])
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(!FileManager.default.fileExists(atPath: box.marker("any").path))
        // Kanca dosyası sağlam: gerçek bir geçiş çalıştırır.
        hooks.fire([change()])
        #expect(await waitFor(box.marker("any")) != nil)
    }

    /// Bozuk `hooks.json` hiçbir komut çalıştırmaz; dosya düzeltilince
    /// (değiştirme zamanı ilerler) yeniden okunur ve kanca çalışır.
    @Test func brokenFileRunsNothingUntilFixed() async throws {
        try #require(!mouseIsDown)
        let box = try Sandbox()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try box.write("{ not json", stamp: t0)
        let hooks = ScreenHooks(url: box.hooksURL)
        hooks.fire([change(1)])
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.dir.path) == ["hooks.json"])
        try box.write(try hooksJSON([ScreenHook(app: nil, from: nil, to: nil, run: box.command("fixed"))]),
                      stamp: t0.addingTimeInterval(10))
        hooks.fire([change(2)])
        #expect(await waitFor(box.marker("fixed")) == "Editor|builtin|external|move")
    }

    /// Kanca dosyası silinince eski kancalar unutulur (bellekte kalıp
    /// çalışmaya devam etmez).
    @Test func deletedFileForgetsHooks() async throws {
        try #require(!mouseIsDown)
        let box = try Sandbox()
        try box.write(try hooksJSON([ScreenHook(app: nil, from: nil, to: nil, run: box.command("first"))]))
        let hooks = ScreenHooks(url: box.hooksURL)
        hooks.fire([change(1)])
        #expect(await waitFor(box.marker("first")) != nil)
        try FileManager.default.removeItem(at: box.marker("first"))
        try FileManager.default.removeItem(at: box.hooksURL)
        hooks.fire([change(2)])
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(!FileManager.default.fileExists(atPath: box.marker("first").path))
    }
}
