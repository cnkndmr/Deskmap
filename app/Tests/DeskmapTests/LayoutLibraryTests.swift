import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Deskmap

/// `LayoutLibrary` (Ayarlar › Düzenler): varsayılanın bugünkü listelerle
/// birebir eşitliği, değişiklik kuralları, hoşgörülü okuma, belge ve
/// `Store` bütünleşmesi.
struct LayoutLibraryTests {

    private func ids(_ library: LayoutLibrary, _ list: LayoutList) -> [String] {
        library.entries(in: list).map(\.id)
    }

    /// Temel satırı `maxBasic`'e kadar doldurur (iki hazır düzen taşınır).
    private func fullBasic() -> LayoutLibrary {
        var library = LayoutLibrary.defaults
        check(library.setList("center", to: .basic))
        check(library.setList("top-half", to: .basic))
        #expect(library.isBasicFull)
        return library
    }

    private let code = WindowLayout(x: 0, y: 0, w: 0.6, h: 1)

    /// `#expect`/`#require` makroları alt ifadeleri değişmez kopyalar; kitaplığı
    /// değiştiren çağrı (`library.setList(…)`) bu sarmalayıcılarla denetlenir.
    private func check(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(condition, sourceLocation: sourceLocation)
    }

    private func require<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
        try #require(value, sourceLocation: sourceLocation)
    }

    // MARK: Varsayılanlar

    @Test func defaultsBasicMatchesTodaysRow() {
        #expect(LayoutLibrary.defaults.basic() == [.full, .leftHalf, .rightHalf, .anyFrame])
    }

    @Test func defaultsAdvancedMatchesPresetsForEveryAspect() {
        for aspect in [1.6, 16.0 / 9, 2.19, 2.2, 21.0 / 9, 3.56, 5120.0 / 1440] {
            #expect(LayoutLibrary.defaults.advanced(aspect: aspect) == WindowLayout.presets(aspect: aspect),
                    "aspect \(aspect)")
        }
    }

    @Test func defaultsHaveNoNamesAndLabelsAreBuiltIn() {
        let library = LayoutLibrary.defaults
        for entry in library.entries {
            #expect(entry.name == nil)
            #expect(library.label(for: entry.layout) == entry.layout.label)
            #expect(!library.isModified(entry.id))
        }
        #expect(library.label(for: .anyFrame) == "Desktop only")
    }

    @Test func builtInIdsAreUniqueAndAsIsIsBasic() {
        let builtIns = LayoutLibrary.builtIns
        #expect(Set(builtIns.map(\.id)).count == builtIns.count)
        #expect(Set(builtIns.map(\.layout)).count == builtIns.count)
        #expect(LayoutLibrary.builtIn("as-is")?.layout == .anyFrame)
        #expect(LayoutLibrary.builtIn("as-is")?.list == .basic)
        #expect(LayoutLibrary.defaults.entries(in: .hidden).isEmpty)
        #expect(LayoutLibrary.defaults.entries.map(\.id) == builtIns.map(\.id))
        check(builtIns.allSatisfy(\.isBuiltIn))
    }

    // MARK: Ekleme

    @Test func addCustomAppendsToSectionAndIsLookedUpByName() throws {
        var library = LayoutLibrary.defaults
        let id = try require(library.add(code, name: "Code", list: .advanced, fit: .any))
        #expect(library.entries(in: .advanced).last?.id == id)
        #expect(library.label(for: code) == "Code")
        #expect(library.advanced(aspect: 1.6).last == code)
        #expect(library.advanced(aspect: 3.56).last == code)
        #expect(!(library.entry(id)?.isBuiltIn ?? true))
        // Gelişmişteki düzen temel döşemede "Özel".
        #expect(library.shortLabel(for: code) == "Custom")
    }

    @Test func addRejectsDuplicateAreaDesktopOnlyAndFullBasic() {
        var library = LayoutLibrary.defaults
        check(library.add(.leftHalf, name: nil, list: .advanced) == nil)
        check(library.add(WindowLayout(x: 0, y: 0, w: 0.5002, h: 1), name: nil, list: .advanced) == nil)
        check(library.add(.anyFrame, name: nil, list: .basic) == nil)
        check(library.add(code, name: nil, list: .advanced, id: "full") == nil)
        check(library.add(WindowLayout(x: .nan, y: 0, w: 0.5, h: 1), name: nil, list: .advanced) == nil)
        #expect(library == .defaults)
        var full = fullBasic()
        check(full.add(code, name: nil, list: .basic) == nil)
        check(full.add(code, name: nil, list: .advanced) != nil)
    }

    @Test func addStripsFixedSize() throws {
        var library = LayoutLibrary.defaults
        let fixed = WindowLayout(fixed: .init(width: 800, height: 600),
                                 screenSize: CGSize(width: 1600, height: 1000))
        let id = try require(library.add(fixed, name: nil, list: .advanced))
        let stored = try #require(library.entry(id)?.layout)
        #expect(stored.fixed == nil)
        #expect(stored == WindowLayout(x: fixed.x, y: fixed.y, w: fixed.w, h: fixed.h))
    }

    // MARK: Temizleme

    @Test func sanitizedClampsOnlyOutOfRangeAndKeepsThirdsExact() {
        for preset in LayoutLibrary.builtIns.map(\.layout) where !preset.isDesktopOnly {
            #expect(LayoutLibrary.sanitized(preset) == preset)
        }
        #expect(LayoutLibrary.sanitized(.rightThird) == .rightThird)
        let wide = LayoutLibrary.sanitized(WindowLayout(x: -0.2, y: 0, w: 2, h: 1))
        #expect(wide == WindowLayout(x: 0, y: 0, w: 1, h: 1))
        let tiny = LayoutLibrary.sanitized(WindowLayout(x: 0.99, y: 0, w: 0.01, h: 1))
        #expect(tiny?.x == 1 - WindowLayout.minSide)
        #expect(abs((tiny?.w ?? 0) - WindowLayout.minSide) < 1e-9)
        #expect(LayoutLibrary.sanitized(WindowLayout(x: 0, y: 0, w: .nan, h: 1)) == nil)
        #expect(LayoutLibrary.sanitized(WindowLayout(x: 0, y: .infinity, w: 1, h: 1)) == nil)
        #expect(LayoutLibrary.sanitized(.anyFrame) == .full)
    }

    /// Ultra geniş ızgaranın (24 × 6) tek sütunu ve tek satırı, ilki ve
    /// sonuncusu dahil, kitaplığa çizildiği gibi girer: pinin ızgarasında
    /// çizilen aynı alanla birebir eşleşir.
    @Test func sanitizedKeepsEverySingleGridCell() throws {
        for (cols, rows) in [(24, 6), (12, 8)] {
            for col in [0, 1, cols - 2, cols - 1] {
                let column = LayoutGrid.layout(from: .init(col: col, row: 0),
                                               to: .init(col: col, row: rows - 1),
                                               cols: cols, rows: rows)
                #expect(LayoutLibrary.sanitized(column) == column)
            }
            for row in [0, rows - 1] {
                let cell = LayoutGrid.layout(from: .init(col: cols - 1, row: row),
                                             to: .init(col: cols - 1, row: row),
                                             cols: cols, rows: rows)
                #expect(LayoutLibrary.sanitized(cell) == cell)
            }
        }
        var library = LayoutLibrary.defaults
        let last = LayoutGrid.layout(from: .init(col: 23, row: 0), to: .init(col: 23, row: 5),
                                     cols: 24, rows: 6)
        let id = try require(library.add(last, name: "Strip", list: .advanced, fit: .ultrawide))
        #expect(library.entry(id)?.layout == last)
        #expect(library.label(for: last) == "Strip")
        // Yerleştirme de tek sütunu kırpmaz.
        let rect = last.rect(in: CGRect(x: 0, y: 0, width: 5120, height: 1440))
        #expect(abs(rect.width - 5120.0 / 24) < 1e-6 && abs(rect.maxX - 5120) < 1e-6)
    }

    @Test func cleanNameTrimsEmptiesAndTruncates() {
        #expect(LayoutLibrary.cleanName("  ") == nil)
        #expect(LayoutLibrary.cleanName(nil) == nil)
        #expect(LayoutLibrary.cleanName(" Code \n") == "Code")
        let long = String(repeating: "x", count: 60)
        #expect(LayoutLibrary.cleanName(long)?.count == LayoutLibrary.maxNameLength)
    }

    // MARK: Değişiklikler

    @Test func renameChangesLabelAndEmptyRestoresAutomatic() {
        var library = LayoutLibrary.defaults
        check(library.rename("left-half", to: "Docs"))
        #expect(library.label(for: .leftHalf) == "Docs")
        #expect(library.shortLabel(for: .leftHalf) == "Docs")
        #expect(library.isModified("left-half"))
        check(!library.rename("left-half", to: " Docs "))
        check(library.rename("left-half", to: ""))
        #expect(library.label(for: .leftHalf) == "Left half")
        #expect(library == .defaults)
        check(!library.rename("as-is", to: "Keep"))
        check(!library.rename("missing", to: "X"))
    }

    @Test func setListMovesToEndOfTargetSection() {
        var library = LayoutLibrary.defaults
        check(library.setList("center", to: .basic))
        #expect(ids(library, .basic) == ["full", "left-half", "right-half", "as-is", "center"])
        #expect(library.basic() == [.full, .leftHalf, .rightHalf, .anyFrame, .center])
        check(!library.setList("center", to: .basic))
        check(library.setList("full", to: .hidden))
        #expect(ids(library, .hidden) == ["full"])
        #expect(!library.basic().contains(.full))
        #expect(!library.advanced(aspect: 1.6).contains(.full))
        check(library.setList("full", to: .advanced))
        #expect(library.entries(in: .advanced).last?.id == "full")
        #expect(library.advanced(aspect: 1.6).contains(.full))
        #expect(!library.basic().contains(.full))
    }

    @Test func setListRespectsLimits() {
        var full = fullBasic()
        check(!full.setList("left-70", to: .basic))
        var library = LayoutLibrary.defaults
        check(!library.setList("as-is", to: .advanced))
        check(library.setList("as-is", to: .hidden))
        #expect(!library.basic().contains(.anyFrame))
        #expect(library.shortLabel(for: .anyFrame) == "As it is")
        check(library.setList("as-is", to: .basic))
        #expect(library.basic().last == .anyFrame)
    }

    @Test func moveStaysWithinSection() {
        var library = LayoutLibrary.defaults
        check(library.move("left-half", by: -1))
        #expect(ids(library, .basic) == ["left-half", "full", "right-half", "as-is"])
        check(!library.move("left-half", by: -1))
        check(!library.move("as-is", by: 1))
        check(!library.move("left-70", by: -1))
        check(library.move("left-70", by: 1))
        #expect(ids(library, .advanced).prefix(2) == ["right-70", "left-70"])
        check(!library.move("center", by: 1))
        check(!library.move("missing", by: 1))
    }

    @Test func removeOnlyCustom() throws {
        var library = LayoutLibrary.defaults
        check(!library.remove("full"))
        let id = try require(library.add(code, name: "Code", list: .basic))
        check(library.remove(id))
        #expect(library.entry(id) == nil)
        #expect(library == .defaults)
        for builtIn in LayoutLibrary.builtIns {
            #expect(library.entry(builtIn.id) != nil)
        }
    }

    @Test func updateEditsGeometryAndRestoreReverts() {
        var library = LayoutLibrary.defaults
        let narrower = WindowLayout(x: 0, y: 0, w: 0.45, h: 1)
        check(library.update("left-half", layout: narrower, name: nil, fit: .any))
        #expect(library.isModified("left-half"))
        #expect(library.label(for: narrower) == "45% × 100%")
        #expect(library.shortLabel(for: narrower) == "45% × 100%")
        #expect(library.basic().contains(narrower) && !library.basic().contains(.leftHalf))
        check(!library.update("left-half", layout: narrower, name: nil, fit: .any))
        check(!library.update("left-half", layout: .rightHalf, name: nil, fit: .any))
        check(!library.update("as-is", layout: code, name: nil, fit: .any))
        check(!library.update("missing", layout: code, name: nil, fit: .any))
        check(library.setList("left-half", to: .hidden))
        check(library.restore("left-half"))
        #expect(library.entry("left-half")?.layout == .leftHalf)
        #expect(library.entry("left-half")?.name == nil)
        #expect(library.entry("left-half")?.list == .hidden)
        #expect(!library.isModified("left-half"))
        check(!library.restore("left-half"))
    }

    @Test func restoreRefusesWhenOriginalAreaIsTaken() throws {
        var library = LayoutLibrary.defaults
        check(library.update("left-half", layout: code, name: nil, fit: .any))
        let mine = try require(library.add(.leftHalf, name: "Mine", list: .advanced))
        // Ayarlar "Özgüne dön"ü kapatır ve engelleyen girişi adlandırır.
        let left = try require(library.entry("left-half"))
        #expect(library.isModified("left-half"))
        #expect(library.restoreConflict("left-half")?.id == mine)
        #expect(!LayoutSettings.canRestore(left, in: library))
        check(!library.restore("left-half"))
        // Engel kalkınca yeniden açılır ve işe yarar.
        check(library.remove(mine))
        #expect(library.restoreConflict("left-half") == nil)
        #expect(LayoutSettings.canRestore(try require(library.entry("left-half")), in: library))
        check(library.restore("left-half"))
        #expect(!LayoutSettings.canRestore(try require(library.entry("left-half")), in: library))
    }

    @Test func draftOfDeletedEntryCannotBeSaved() throws {
        var library = LayoutLibrary.defaults
        let id = try require(library.add(code, name: "Code", list: .advanced))
        var draft = LayoutDraft.editing(try require(library.entry(id)))
        draft.name = "Code 2"
        #expect(draft.problem(in: library) == nil)
        check(library.remove(id))
        #expect(draft.problem(in: library) == "This layout no longer exists.")
        var copy = library
        check(draft.apply(to: &copy) == nil)
        #expect(copy == library)
    }

    @Test func resetEqualsDefaults() throws {
        var library = LayoutLibrary.defaults
        library.rename("full", to: "Everything")
        library.add(code, name: "Code", list: .basic)
        library.setList("center", to: .hidden)
        #expect(library != .defaults)
        library = .defaults
        #expect(library == LayoutLibrary.defaults)
        var document = Document()
        document.layouts = library
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        #expect(!json.contains("\"layouts\""))
    }

    @Test func fitFiltersBothLists() throws {
        var library = LayoutLibrary.defaults
        let column = WindowLayout(x: 0, y: 0, w: 0.4, h: 1)
        _ = try require(library.add(column, name: "Column", list: .basic, fit: .ultrawide))
        #expect(library.basic(aspect: 3.56).contains(column))
        #expect(!library.basic(aspect: 1.6).contains(column))
        #expect(library.basic(aspect: nil).contains(column))
        #expect(library.advanced(aspect: 3.56).contains(column))
        #expect(!library.advanced(aspect: 1.6).contains(column))
        #expect(ScreenFit.ultrawide.accepts(aspect: 2.2))
        #expect(!ScreenFit.regular.accepts(aspect: 2.2))
        #expect(ScreenFit.regular.accepts(aspect: 2.19))
        #expect(!ScreenFit.ultrawide.accepts(aspect: 2.19))
        #expect(ScreenFit.any.accepts(aspect: 9) && ScreenFit.regular.accepts(aspect: nil))
        // Ekrana uymadığı için satırda olmayan temel düzen orada "Özel".
        #expect(library.shortLabel(for: column, aspect: 1.6) == "Custom")
        #expect(library.shortLabel(for: column, aspect: 3.56) == "Column")
    }

    @Test func shortLabelRules() {
        var library = LayoutLibrary.defaults
        #expect(library.shortLabel(for: .anyFrame) == "As it is")
        #expect(library.shortLabel(for: .full) == "Full")
        #expect(library.shortLabel(for: .topHalf) == "Custom")
        library.setList("right-half", to: .hidden)
        #expect(library.shortLabel(for: .rightHalf) == "Custom")
        library.rename("full", to: "All")
        #expect(library.shortLabel(for: .full) == "All")
        // Varsayılan kitaplıkla eski `BasicLayoutRow.shortLabel` davranışı.
        #expect(BasicLayoutRow.shortLabel(.leftHalf) == "Left half")
        #expect(BasicLayoutRow.shortLabel(.full, in: library) == "All")
    }

    @Test func labelForFixedLayoutIgnoresLibrary() throws {
        var library = LayoutLibrary.defaults
        let fixed = WindowLayout(fixed: .init(width: 800, height: 600),
                                 screenSize: CGSize(width: 1600, height: 1000))
        _ = try require(library.add(fixed, name: "Small", list: .advanced))
        #expect(library.label(for: fixed) == fixed.label)
        #expect(library.label(for: WindowLayout(x: fixed.x, y: fixed.y, w: fixed.w, h: fixed.h)) == "Small")
    }

    // MARK: Kayıt

    @Test func codableRoundTrip() throws {
        var library = LayoutLibrary.defaults
        let id = try require(library.add(WindowLayout(x: 0, y: 0, w: 0.5833, h: 1), name: "Code",
                                          list: .basic, fit: .ultrawide))
        check(library.setList("center", to: .hidden))
        check(library.move("right-half", by: -1))
        let data = try JSONEncoder().encode(library)
        #expect(try JSONDecoder().decode(LayoutLibrary.self, from: data) == library)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let entries = try #require(object["entries"] as? [[String: Any]])
        let full = try #require(entries.first { $0["id"] as? String == "full" })
        #expect(full["fit"] == nil && full["name"] == nil)
        #expect(full["list"] as? String == "basic")
        let custom = try #require(entries.first { $0["id"] as? String == id })
        #expect(custom["fit"] as? String == "ultrawide" && custom["name"] as? String == "Code")
    }

    @Test func decodeIsLenient() throws {
        let json = """
        {"version": 99, "future": true, "entries": [
          {"id": "a", "layout": {"x": 0, "y": 0, "w": 0.4, "h": 1}, "list": "pinned", "fit": "tv", "extra": 1},
          {"layout": {"x": 0, "y": 0, "w": 0.3, "h": 0.3}, "list": "basic"},
          {"id": "", "layout": {"x": 0, "y": 0, "w": 0.2, "h": 0.3}},
          5,
          {"id": "b", "layout": {"x": 0, "y": 0, "w": 0.45, "h": 1}}
        ]}
        """
        let library = try JSONDecoder().decode(LayoutLibrary.self, from: Data(json.utf8))
        #expect(library.entry("a")?.list == .advanced)
        #expect(library.entry("a")?.fit == ScreenFit.any)
        #expect(library.entry("b")?.list == .advanced)
        #expect(library.entries.count == LayoutLibrary.builtIns.count + 2)
        #expect(!library.entries.contains { $0.layout == WindowLayout(x: 0, y: 0, w: 0.3, h: 0.3) })
    }

    @Test func decodeAppendsMissingBuiltIns() throws {
        let json = """
        {"version": 1, "entries": [
          {"id": "full", "layout": {"x": 0, "y": 0, "w": 1, "h": 1}, "list": "hidden"},
          {"id": "mine", "layout": {"x": 0, "y": 0, "w": 1, "h": 0.5}, "list": "basic", "name": "Top"}
        ]}
        """
        let library = try JSONDecoder().decode(LayoutLibrary.self, from: Data(json.utf8))
        #expect(library.entry("full")?.list == .hidden)
        #expect(library.entry("top-half") == nil)
        #expect(library.label(for: .topHalf) == "Top")
        for builtIn in LayoutLibrary.builtIns where !["full", "top-half"].contains(builtIn.id) {
            #expect(library.entry(builtIn.id)?.list == builtIn.list, "\(builtIn.id)")
        }
        #expect(Set(library.entries.map(\.layout)).count == library.entries.count)
    }

    @Test func decodeNormalizesAsIsAndBasicOverflow() throws {
        let widths = ["0.15", "0.2", "0.25", "0.3", "0.35", "0.4", "0.45", "0.55"]
        let extra = widths.enumerated().map { i, w in
            "{\"id\": \"c\(i + 1)\", \"layout\": {\"x\": 0, \"y\": 0, \"w\": \(w), \"h\": 0.9}, \"list\": \"basic\"}"
        }
        let json = """
        {"entries": [
          {"id": "as-is", "name": "X", "layout": {"x": 0.2, "y": 0, "w": 0.5, "h": 1}, "list": "advanced"},
          \(extra.joined(separator: ",\n"))
          , {"id": "c1", "layout": {"x": 0.5, "y": 0.5, "w": 0.1, "h": 0.1}, "list": "basic"}
          , {"id": "dup", "layout": {"x": 0, "y": 0, "w": 0.15, "h": 0.9}, "list": "basic"}
        ]}
        """
        let library = try JSONDecoder().decode(LayoutLibrary.self, from: Data(json.utf8))
        let asIs = try #require(library.entry("as-is"))
        #expect(asIs.list == .hidden && asIs.layout == .anyFrame && asIs.name == nil)
        #expect(ids(library, .basic) == ["c1", "c2", "c3", "c4", "c5", "c6"])
        #expect(ids(library, .advanced).prefix(2) == ["c7", "c8"])
        #expect(library.entry("c1")?.layout.w == 0.15)
        #expect(library.entry("dup") == nil)
        // Temel satırdaki hazırlar sınırı aştığı için gelişmişe iner.
        #expect(library.entry("full")?.list == .advanced)
    }

    @Test func normalizedKeepsSectionsContiguous() {
        var library = LayoutLibrary.defaults
        var generator = SeededRNG(seed: 7)
        let allIDs = LayoutLibrary.builtIns.map(\.id)
        for _ in 0..<300 {
            let id = allIDs.randomElement(using: &generator)!
            if Bool.random(using: &generator) {
                library.setList(id, to: LayoutList.allCases.randomElement(using: &generator)!)
            } else {
                library.move(id, by: Bool.random(using: &generator) ? 1 : -1)
            }
            let order = library.entries.map { LayoutList.allCases.firstIndex(of: $0.list)! }
            #expect(order == order.sorted())
            #expect(library.entries(in: .basic).count <= LayoutLibrary.maxBasic)
            #expect(library.entries.count == allIDs.count)
        }
    }

    @Test func documentDefaultsAndCorruptFallback() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(Document.self, from: Data("{}".utf8)).layouts == .defaults)
        #expect(try decoder.decode(Document.self, from: Data(#"{"layouts": "x"}"#.utf8)).layouts == .defaults)
        #expect(try decoder.decode(Document.self,
                                   from: Data(#"{"layouts": {"entries": 5}}"#.utf8)).layouts == .defaults)
        let plain = String(decoding: try JSONEncoder().encode(Document()), as: UTF8.self)
        #expect(!plain.contains("\"layouts\""))
        var document = Document()
        document.layouts.rename("center", to: "Middle")
        document.layouts.add(code, name: "Code", list: .basic)
        let data = try JSONEncoder().encode(document)
        #expect(String(decoding: data, as: UTF8.self).contains("\"layouts\""))
        #expect(try decoder.decode(Document.self, from: data).layouts == document.layouts)
    }

    @Test func deletingLayoutNeverTouchesRules() throws {
        var document = Document()
        let id = try require(document.layouts.add(code, name: "Code", list: .basic))
        document.rules = [Rule(id: "r", appName: "A", bundleID: "a", tokens: [],
                               docked: Destination(screen: "external", desktop: 2, layout: code))]
        let before = document.rules
        #expect(document.layouts.label(for: code) == "Code")
        check(document.layouts.remove(id))
        #expect(document.rules == before)
        #expect(document.layouts.label(for: code) == "60% × 100%")
        #expect(document.layouts.shortLabel(for: code) == "Custom")
    }

    /// Kenar boşluğu alanlarının bir ulp kaydırdığı alan (1 − 0,7) aynı
    /// alandır: hazır düzen "değişti" olmaz, eski değeri tutan pin girişle
    /// (ad, temel döşeme) eşleşmeye devam eder.
    @Test func updateSnapsNearlySameAreaToStoredValue() throws {
        let shifted = WindowLayout(x: 0.7, y: 0, w: 1.0 - 0.7, h: 1)
        #expect(shifted != .right30 && LayoutLibrary.sameArea(shifted, .right30))

        var library = LayoutLibrary.defaults
        check(!library.update("right-30", layout: shifted, name: nil, fit: .regular))
        #expect(library.entry("right-30")?.layout == .right30)
        #expect(!library.isModified("right-30"))

        // Adla birlikte kaydedilince de alan özgün kalır; pin adı görür.
        check(library.update("right-30", layout: shifted, name: "Chat", fit: .regular))
        #expect(library.entry("right-30")?.layout == .right30)
        #expect(library.label(for: .right30) == "Chat")
        check(library.setList("right-30", to: .basic))
        #expect(library.shortLabel(for: .right30) == "Chat")

        // Değiştirilmiş hazır düzen özgününe neredeyse dönünce özgüne oturur.
        let wider = WindowLayout(x: 0.55, y: 0, w: 0.45, h: 1)
        check(library.update("left-30", layout: WindowLayout(x: 0, y: 0, w: 0.4, h: 1),
                             name: nil, fit: .regular))
        check(library.update("left-30", layout: WindowLayout(x: 0, y: 0, w: (1 - 0.7) - 0, h: 1),
                             name: nil, fit: .regular))
        #expect(library.entry("left-30")?.layout == .left30)
        #expect(!library.isModified("left-30"))

        // Kullanıcının düzeni eski değerinde kalır.
        let id = try require(library.add(wider, name: nil, list: .advanced))
        let nudged = WindowLayout(x: 0.55, y: 0, w: 1.0 - 0.55, h: 1)
        #expect(nudged != wider)
        check(!library.update(id, layout: nudged, name: nil, fit: .any))
        #expect(library.entry(id)?.layout == wider)
    }

    // MARK: Ayarlar penceresi

    /// Açık pencereyi yeniden göstermek yarım taslağı atmaz ve sekme
    /// verilmediyse sekmeyi değiştirmez; gizli pencerenin açılışı yeni
    /// oturumdur.
    @Test func settingsReopenKeepsDraftOnlyWhileVisible() {
        let shown = SettingsWindow.opening(requested: .layouts, current: .layouts, visible: true)
        #expect(shown.tab == .layouts && !shown.newSession)
        let menu = SettingsWindow.opening(requested: nil, current: .layouts, visible: true)
        #expect(menu.tab == .layouts && !menu.newSession)
        let hidden = SettingsWindow.opening(requested: .layouts, current: .layouts, visible: false)
        #expect(hidden.tab == .layouts && hidden.newSession)
        let fresh = SettingsWindow.opening(requested: nil, current: .layouts, visible: false)
        #expect(fresh.tab == .general && fresh.newSession)
        let other = SettingsWindow.opening(requested: .profiles, current: .layouts, visible: true)
        #expect(other.tab == .profiles && !other.newSession)
    }

    // MARK: Taslak

    @Test func draftNewAndEditing() throws {
        let library = LayoutLibrary.defaults
        let fresh = LayoutDraft.new(in: library)
        #expect(fresh.conflict(in: library) == nil && fresh.problem(in: library) == nil)
        #expect(fresh.list == .advanced && fresh.fit == .any && fresh.id == nil && fresh.name.isEmpty)
        let leftHalf = try #require(library.entry("left-half"))
        let editing = LayoutDraft.editing(leftHalf)
        #expect(editing.conflict(in: library) == nil)
        var duplicate = fresh
        duplicate.layout = .leftHalf
        #expect(duplicate.problem(in: library) == "Same area as “Left half”.")

        let full = fullBasic()
        var basicDraft = fresh
        basicDraft.list = .basic
        #expect(basicDraft.problem(in: full) == "The basic row is full (6 layouts). Move one out first.")
        // Zaten temel olan giriş dolu satırda kalabilir.
        #expect(LayoutDraft.editing(try #require(full.entry("full"))).problem(in: full) == nil)

        var added = library
        var named = fresh
        named.name = " Wide "
        let newID = try require(named.apply(to: &added))
        #expect(added.entry(newID)?.name == "Wide")
        #expect(added.entries(in: .advanced).last?.id == newID)

        var updated = library
        var change = editing
        change.layout = WindowLayout(x: 0, y: 0, w: 0.55, h: 1)
        change.name = "Docs"
        change.list = .hidden
        check(change.apply(to: &updated) == "left-half")
        #expect(updated.entry("left-half")?.list == .hidden)
        #expect(updated.entry("left-half")?.name == "Docs")
        #expect(updated.entry("left-half")?.layout.w == 0.55)

        var rejected = library
        check(duplicate.apply(to: &rejected) == nil)
        #expect(rejected == library)
    }

    @Test func draftPreviewSize() {
        let ultra = LayoutDraft.previewSize(fit: .ultrawide, screens: [])
        #expect(ultra.width / ultra.height >= WindowLayout.ultrawideAspect)
        let known = KnownScreen(id: "external", name: "LG", aspect: 3440.0 / 1440,
                                visibleWidth: 3440, visibleHeight: 1415)
        #expect(LayoutDraft.previewSize(fit: .ultrawide, screens: [known])
                == CGSize(width: 3440, height: 1415))
        #expect(LayoutDraft.previewSize(fit: .regular, screens: [known])
                == CGSize(width: 1600, height: 1000))
        #expect(LayoutDraft.previewSize(fit: .any, screens: [known]) == CGSize(width: 3440, height: 1415))
    }

    @Test func layoutGridSizeHonoursMaxWidth() {
        #expect(LayoutGrid.size(aspect: 3.56, maxWidth: 420).width == 420)
        #expect(abs(LayoutGrid.size(aspect: 1.6, maxWidth: 420).height - 170) < 1e-9)
    }

    @Test func settingsRowHelpers() throws {
        var library = LayoutLibrary.defaults
        let asIs = try #require(library.entry("as-is"))
        #expect(!LayoutSettings.canShow(asIs, in: .advanced, library: library))
        #expect(LayoutSettings.canShow(asIs, in: .hidden, library: library))
        library.rename("left-half", to: "Docs")
        let left = try #require(library.entry("left-half"))
        #expect(LayoutSettings.subtitle(left, in: library) == "Left half · Changed")
        #expect(LayoutSettings.subtitle(try #require(library.entry("left-third")), in: library)
                == "Ultrawide displays only")
        let id = try require(library.add(code, name: nil, list: .advanced))
        #expect(LayoutSettings.subtitle(try #require(library.entry(id)), in: library) == "Your layout")
        let full = fullBasic()
        #expect(!LayoutSettings.canShow(try #require(full.entry("left-70")), in: .basic, library: full))
        #expect(LayoutSettings.canShow(try #require(full.entry("full")), in: .basic, library: full))
    }

    /// Satır düğmelerinin VoiceOver etiketi düzenin adını taşır: her satırda
    /// aynı "Move up" okunursa yanlış düzen taşınır ya da silinir.
    @Test func settingsRowAccessibilityLabelsNameTheLayout() throws {
        var library = LayoutLibrary.defaults
        library.rename("left-half", to: "Docs")
        let left = try #require(library.entry("left-half"))
        let top = try #require(library.entry("top-half"))
        #expect(LayoutSettings.moveUpLabel(left) == "Move up: Docs")
        #expect(LayoutSettings.moveDownLabel(left) == "Move down: Docs")
        #expect(LayoutSettings.menuLabel(left) == "Edit, move or delete: Docs")
        for label in [LayoutSettings.moveUpLabel, LayoutSettings.moveDownLabel, LayoutSettings.menuLabel] {
            #expect(label(top).contains(top.displayName))
            #expect(label(left) != label(top))
        }
    }

    /// Taslakta Kaydet varsayılan düğme değil: ad ya da kenar boşluğu
    /// alanındaki Return yazılanı bağlamalı, taslağı kaydedip kapatmamalı.
    @Test func draftSaveIsNotTheReturnKeyDefault() {
        let shortcut = LayoutDraftEditor.saveShortcut
        #expect(shortcut != .defaultAction)
        #expect(shortcut.modifiers.contains(.command))
        #expect(shortcut.key == .return)
    }

    // MARK: Geçmiş ve Store

    @Test func historyDoesNotTreatLayoutChangeAsNoise() {
        let a = Document()
        var b = a
        b.layouts.rename("full", to: "All")
        #expect(!ChangeHistory.matches(a, b))
    }

    @MainActor @Test func storeChangeLayoutsRecordsUndoableEntry() throws {
        let store = Store(demo: Document())
        let changed = store.changeLayouts("Layout added: X") { $0.add(code, name: "X", list: .basic) != nil }
        #expect(changed)
        #expect(store.history.undoEntry?.label == "Layout added: X")
        let custom = store.document.layouts
        store.undo()
        #expect(store.document.layouts == .defaults)
        store.redo()
        #expect(store.document.layouts == custom)
        let count = store.history.entries.count
        check(!store.changeLayouts("Nothing") { $0.setList("full", to: .basic) })
        check(!store.changeLayouts("Nothing") { _ in true })
        #expect(store.history.entries.count == count)
    }

    @MainActor @Test func storeResetLayoutsIsUndoable() {
        let store = Store(demo: Document())
        store.changeLayouts("Renamed") { $0.rename("full", to: "All") }
        store.resetLayouts()
        #expect(store.document.layouts == .defaults)
        #expect(store.history.undoEntry?.label == "Layouts reset")
        store.undo()
        #expect(store.document.layouts.label(for: .full) == "All")
    }

    /// Kitaplığı olmayan (özellikten önceki ya da varsayılan) yedek şu anki
    /// düzenleri silmez.
    @MainActor @Test func restoreBackupWithoutLibraryKeepsCurrentLibrary() throws {
        var start = Document()
        start.layouts.add(code, name: "Code", list: .basic)
        let store = Store(demo: start)
        let backup = try JSONDecoder().decode(Document.self, from: Store.encode(Document()))
        store.restoreBackup(backup)
        #expect(store.document.layouts == start.layouts)
        #expect(store.document.layouts.label(for: code) == "Code")
    }

    /// Kitaplığı olan yedek onu geri getirir: sıfırlanan ya da silinen
    /// düzenlerin yeniden başlatmadan sonraki tek dönüş yolu.
    @MainActor @Test func restoreBackupBringsBackItsLibrary() throws {
        var saved = Document()
        saved.layouts.add(code, name: "Code", list: .basic)
        saved.layouts.rename("full", to: "All")
        let backup = try JSONDecoder().decode(Document.self, from: Store.encode(saved))
        #expect(backup.layouts == saved.layouts)
        let store = Store(demo: Document())
        store.restoreBackup(backup)
        #expect(store.document.layouts == saved.layouts)
        #expect(store.document.layouts.label(for: code) == "Code")
        store.undo()
        #expect(store.document.layouts == .defaults)
        #expect(Store.restoredLayouts(backup: .defaults, current: saved.layouts) == saved.layouts)
        #expect(Store.restoredLayouts(backup: saved.layouts, current: .defaults) == saved.layouts)
    }

    @Test func routingReasonUsesLibraryNames() throws {
        let match = Routing.Match(destination: Destination(screen: "external", desktop: 1, layout: .leftHalf),
                                  ruleID: Routing.sessionRuleID, rule: nil)
        let plain = try #require(Routing.reason(for: match, screenName: "Dell"))
        #expect(plain.contains("Layout: Left half"))
        var library = LayoutLibrary.defaults
        library.rename("left-half", to: "Docs")
        let named = try #require(Routing.reason(for: match, screenName: "Dell", layouts: library))
        #expect(named.contains("Layout: Docs"))
        #expect(Routing.explanation(for: match, screenName: "Dell", layouts: library)?.contains("Docs") == true)
        #expect(Routing.reason(for: match, screenName: "Dell", layouts: .defaults) == plain)
    }
}
