import Foundation
import Testing
@testable import Deskmap

/// Yerelleştirme: kaynaktaki `L("...")` anahtarları ile
/// `app/Resources/*.lproj/Localizable.strings` tabloları tutarlı mı?
///
/// Anahtar İngilizce metnin kendisidir; Türkçe çeviri `tr.lproj`'dadır.
/// Eksik çeviri uygulamayı bozmaz (İngilizce görünür) ama belirteci
/// uyuşmayan bir çeviri `String(format:)` ile yanlış metin ya da çökme
/// üretir; bu testler ikisini de derleme zamanına yakın yakalar.
struct LocalizationTests {

    // MARK: - Dosyalar

    /// `app/` dizini (bu dosya app/Tests/DeskmapTests içinde).
    private static let appDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func tableURL(_ language: String) -> URL {
        appDirectory.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
    }

    /// `.strings` dosyasını sözlük olarak okur (boş tablo = boş sözlük).
    private static func table(_ language: String) throws -> [String: String] {
        let text = try String(contentsOf: tableURL(language), encoding: .utf8)
        guard text.contains("=") else { return [:] }
        let plist = try PropertyListSerialization.propertyList(
            from: Data(text.utf8), format: nil)
        guard let table = plist as? [String: String] else {
            throw Failure(description: "\(language).lproj/Localizable.strings bir dize tablosu değil")
        }
        return table
    }

    /// Kaynaktaki bir `L(...)` çağrısı.
    private struct Call {
        let key: String?
        let location: String
        /// Anahtar tek parça bir dize sabiti değilse neden.
        let problem: String?
    }

    /// `app/Sources/Deskmap` altındaki bütün `L(` çağrıları (yorum
    /// satırları hariç). `Localization.swift` `L`'yi tanımlar; içindeki
    /// `L(key)` çağrısı bir anahtar değildir, taranmaz.
    private static func sourceCalls() throws -> [Call] {
        let sources = appDirectory.appendingPathComponent("Sources/Deskmap")
        let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Localization.swift" }
            .sorted { $0.path < $1.path }
        let call = try Regex(#"\bL\("#)
        let literal = try Regex(#"\bL\("((?:[^"\\]|\\.)*)"(\s*[,)])?"#)

        var result: [Call] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                let location = "\(file.lastPathComponent):\(index + 1)"
                let literals = line.matches(of: literal)
                for match in literals {
                    let raw = match.output[1].substring.map(String.init) ?? ""
                    var problem: String?
                    if match.output[2].substring == nil {
                        problem = "anahtar birleştiriliyor; tek dize sabiti olmalı"
                    } else if raw.contains(#"\("#) {
                        problem = "anahtarda \\(...) var; %@ / %ld kullanın"
                    }
                    result.append(Call(key: unescape(raw), location: location, problem: problem))
                }
                // Sabitle başlamayan çağrılar (L(değişken)) denetlenemez.
                let extra = line.matches(of: call).count - literals.count
                for _ in 0..<max(0, extra) {
                    result.append(Call(key: nil, location: location,
                                       problem: "anahtar dize sabiti değil"))
                }
            }
        }
        return result
    }

    /// Swift dize sabiti kaçışlarını çözer (`\"`, `\\`, `\n`, `\t`).
    private static func unescape(_ raw: String) -> String {
        var result = ""
        var escaping = false
        for character in raw {
            if escaping {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Biçim belirteçleri: konum → tür (ör. 1 → "l" + "d"). `%%` sayılmaz;
    /// sırasız belirteçler soldan sağa 1, 2, … konumunu alır.
    static func specifiers(_ format: String) -> [Int: String] {
        let pattern = try! Regex(
            #"%(?:%|(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGcCsSp]))"#)
        var result: [Int: String] = [:]
        var next = 1
        for match in format.matches(of: pattern) {
            guard let conversion = match.output[3].substring else { continue }  // %%
            let position: Int
            if let explicit = match.output[1].substring, let number = Int(explicit) {
                position = number
            } else {
                position = next
                next += 1
            }
            let length = match.output[2].substring.map(String.init) ?? ""
            let kind = conversion == "i" ? "d" : String(conversion)
            result[position] = length + kind
        }
        return result
    }

    // MARK: - Testler

    @Test func keysAreSingleStringLiterals() throws {
        let problems = try Self.sourceCalls().compactMap { call in
            call.problem.map { "\(call.location): \($0)" }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test func turkishTableCoversEverySourceKey() throws {
        let table = try Self.table("tr")
        let missing = try Self.sourceCalls()
            .filter { call in call.key.map { table[$0] == nil } ?? false }
            .map { "\($0.location): \"\($0.key ?? "")\"" }
        #expect(missing.isEmpty, "tr.lproj'da çevirisi olmayan anahtarlar:\n\(missing.joined(separator: "\n"))")
    }

    @Test func turkishTableHasNoStaleKeys() throws {
        let used = Set(try Self.sourceCalls().compactMap(\.key))
        let stale = try Self.table("tr").keys.filter { !used.contains($0) }.sorted()
        #expect(stale.isEmpty, "Kaynakta kullanılmayan anahtarlar:\n\(stale.joined(separator: "\n"))")
    }

    @Test func turkishTableHasNoDuplicateKeys() throws {
        // PropertyListSerialization yinelenen anahtarda sessizce sonuncuyu
        // alır; satır sayısı sözlük boyutuyla aynı olmalı.
        let text = try String(contentsOf: Self.tableURL("tr"), encoding: .utf8)
        let entries = text.split(separator: "\n").filter { $0.hasPrefix("\"") }.count
        #expect(entries == (try Self.table("tr").count))
    }

    @Test func turkishFormatSpecifiersMatchKeys() throws {
        let mismatched = try Self.table("tr").compactMap { key, value -> String? in
            Self.specifiers(key) == Self.specifiers(value) ? nil : "\"\(key)\" → \"\(value)\""
        }.sorted()
        #expect(mismatched.isEmpty, "Belirteçleri uyuşmayan çeviriler:\n\(mismatched.joined(separator: "\n"))")
    }

    @Test func englishTableExistsAndIsEmpty() throws {
        // Anahtarlar İngilizce olduğu için en.lproj boştur; paketin İngilizce
        // yerelleştirmeyi bildirmesi için yine de bulunur.
        #expect(try Self.table("en").isEmpty)
    }

    @Test func specifierParserHandlesPositionsAndPercentSigns() {
        #expect(Self.specifiers("%ld%% × %ld%%") == [1: "ld", 2: "ld"])
        #expect(Self.specifiers("%%%1$ld × %%%2$ld") == [1: "ld", 2: "ld"])
        #expect(Self.specifiers("%1$@ modunda %2$ld pin") == Self.specifiers("Pins in %@ mode: %ld"))
        #expect(Self.specifiers("Sağ %30") == [:])
        #expect(Self.specifiers("Right 30%") == [:])
    }

    @Test func lookupFallsBackToEnglishKey() {
        // Test sürecinde paket tablosu yok: anahtar (İngilizce) döner, biçim uygulanır.
        #expect(L("Full") == "Full")
        #expect(L("%ld pins", 3) == "3 pins")
        #expect(L("%@ · Desktop %ld", "Studio", 2) == "Studio · Desktop 2")
        #expect(WindowLayout(x: 0.1, y: 0, w: 0.25, h: 0.5).label == "25% × 50%")
    }
}
