import Foundation
import Testing
@testable import SpaceRouter

/// Tek seviyeli geri alma tamponu (Store yıkıcı işlemlerden sonra doldurur).
struct UndoBufferTests {

    private func document(rules: Int) -> Document {
        var doc = Document()
        doc.rules = (0..<rules).map {
            Rule(id: "r\($0)", appName: "Code", bundleID: "com.microsoft.VSCode",
                 tokens: ["t\($0)"], docked: Destination(screen: "external"))
        }
        return doc
    }

    @Test func startsEmptyAndRecordsLatestOnly() {
        var buffer = UndoBuffer()
        #expect(buffer.isEmpty)
        #expect(buffer.entry == nil)
        #expect(buffer.expiry == nil)

        let first = document(rules: 1)
        let second = document(rules: 2)
        buffer.record("Pin kaldırıldı", before: first, after: Document())
        buffer.record("Profil silindi: Ofis", before: second, after: Document())
        #expect(!buffer.isEmpty)
        #expect(buffer.entry?.label == "Profil silindi: Ofis")
        #expect(buffer.entry?.before == second)   // tek seviye: yalnızca sonuncusu
    }

    @Test func takeReturnsEntryAndClears() {
        var buffer = UndoBuffer()
        let doc = document(rules: 3)
        buffer.record("Masaüstü sırası değişti", before: doc, after: Document())
        let taken = buffer.take()
        #expect(taken?.before == doc)
        #expect(taken?.label == "Masaüstü sırası değişti")
        #expect(buffer.isEmpty)
        #expect(buffer.take() == nil)
    }

    @Test func clearEmptiesBuffer() {
        var buffer = UndoBuffer()
        buffer.record("Pin kaldırıldı", before: Document(), after: Document())
        buffer.clear()
        #expect(buffer.isEmpty)
        #expect(buffer.take() == nil)
    }

    @Test func visibilityWindowIsTenSeconds() {
        #expect(UndoBuffer.visibleFor == 10)
        var buffer = UndoBuffer()
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(!buffer.isVisible(at: t0))            // boş tampon görünmez
        buffer.record("Pin kaldırıldı", before: Document(), after: Document(), at: t0)
        #expect(buffer.isVisible(at: t0))
        #expect(buffer.isVisible(at: t0.addingTimeInterval(9.9)))
        #expect(!buffer.isVisible(at: t0.addingTimeInterval(10)))
        #expect(buffer.expiry == t0.addingTimeInterval(10))
        // Süre dolsa da kayıt durur; take yine verir (⌘Z sadece görünürken bağlı).
        #expect(!buffer.isEmpty)
    }

    // MARK: Geçerlilik

    @Test func matchesIgnoresEnabledAndScreens() {
        let a = document(rules: 2)
        var b = a
        b.enabled = false
        b.screens = [KnownScreen(id: "external", name: "Dell", aspect: 1.78)]
        #expect(UndoBuffer.matches(a, b))

        var c = a
        c.rules.removeLast()
        #expect(!UndoBuffer.matches(a, c))
        var d = a
        d.setupNoticeDismissed = true
        #expect(!UndoBuffer.matches(a, d))
        var e = a
        e.addProfile(named: "Ofis")
        #expect(!UndoBuffer.matches(a, e))
    }

    @Test func matchesTreatsDelayedProfileSyncAsSame() {
        // Store, kayıttan 400 ms sonra aktif profilin kurallarını üst düzey
        // `rules` ile eşitler; bu eşitleme kaydı düşürmemeli.
        let after = document(rules: 2)             // profiles[0].rules hâlâ boş
        var synced = after
        synced.syncActiveProfile()
        #expect(synced != after)
        #expect(UndoBuffer.matches(after, synced))
    }

    @Test func entryStaysValidUntilDocumentDrifts() {
        let before = document(rules: 2)
        var after = before
        after.rules.removeLast()
        var buffer = UndoBuffer()
        buffer.record("Pin kaldırıldı", before: before, after: after)

        // Belge kayıttaki "sonra" hâlinde: geçerli; anahtar ve ekranlar sayılmaz.
        #expect(buffer.isStillValid(current: after))
        var toggled = after
        toggled.enabled.toggle()
        buffer.invalidate(ifChangedFrom: toggled)
        #expect(!buffer.isEmpty)

        // Araya yeni bir pin girdi: geri alma onu da silerdi, kayıt düşer.
        var drifted = after
        drifted.pin(Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: ["Docs"]),
                    destination: Destination(screen: "builtin"), mode: .docked)
        #expect(!buffer.isStillValid(current: drifted))
        buffer.invalidate(ifChangedFrom: drifted)
        #expect(buffer.isEmpty)

        // Boş tampon her belge için geçerli sayılır.
        #expect(buffer.isStillValid(current: drifted))
    }

    @Test func profileSwitchInvalidatesEntry() {
        var before = document(rules: 1)
        before.addProfile(named: "Ofis")
        before.switchProfile(to: before.profiles[0].id)
        var after = before
        after.rules.removeAll()
        var buffer = UndoBuffer()
        buffer.record("Pin kaldırıldı", before: before, after: after)

        var switched = after
        switched.switchProfile(to: switched.profiles[1].id)
        buffer.invalidate(ifChangedFrom: switched)
        #expect(buffer.isEmpty)
    }

    @Test func companionIsKeptButNotCompared() {
        var ran = 0
        var buffer = UndoBuffer()
        let doc = Document()
        buffer.record("Masaüstü sırası değişti", before: doc, after: doc, companion: { ran += 1 })
        let taken = buffer.take()
        taken?.companion?()
        #expect(ran == 1)
        // Eşitlik kapanışa bakmaz.
        let t0 = Date(timeIntervalSince1970: 1_000)
        var a = UndoBuffer(), b = UndoBuffer()
        a.record("x", before: doc, after: doc, companion: { ran += 1 }, at: t0)
        b.record("x", before: doc, after: doc, companion: nil, at: t0)
        #expect(a == b)
    }
}
