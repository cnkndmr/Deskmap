import Foundation
import Testing
@testable import SpaceRouter

/// Tek seviyeli geri alma tamponu (Store yıkıcı işlemlerden önce doldurur).
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
        buffer.record("Pin kaldırıldı", document: first)
        buffer.record("Profil silindi: Ofis", document: second)
        #expect(!buffer.isEmpty)
        #expect(buffer.entry?.label == "Profil silindi: Ofis")
        #expect(buffer.entry?.document == second)   // tek seviye: yalnızca sonuncusu
    }

    @Test func takeReturnsEntryAndClears() {
        var buffer = UndoBuffer()
        let doc = document(rules: 3)
        buffer.record("Masaüstü sırası değişti", document: doc)
        let taken = buffer.take()
        #expect(taken?.document == doc)
        #expect(taken?.label == "Masaüstü sırası değişti")
        #expect(buffer.isEmpty)
        #expect(buffer.take() == nil)
    }

    @Test func clearEmptiesBuffer() {
        var buffer = UndoBuffer()
        buffer.record("Pin kaldırıldı", document: Document())
        buffer.clear()
        #expect(buffer.isEmpty)
        #expect(buffer.take() == nil)
    }

    @Test func visibilityWindowIsTenSeconds() {
        #expect(UndoBuffer.visibleFor == 10)
        var buffer = UndoBuffer()
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(!buffer.isVisible(at: t0))            // boş tampon görünmez
        buffer.record("Pin kaldırıldı", document: Document(), at: t0)
        #expect(buffer.isVisible(at: t0))
        #expect(buffer.isVisible(at: t0.addingTimeInterval(9.9)))
        #expect(!buffer.isVisible(at: t0.addingTimeInterval(10)))
        #expect(buffer.expiry == t0.addingTimeInterval(10))
        // Süre dolsa da kayıt durur; take yine verir (⌘Z sadece görünürken bağlı).
        #expect(!buffer.isEmpty)
    }
}
