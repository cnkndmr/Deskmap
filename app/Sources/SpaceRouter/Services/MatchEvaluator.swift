import Foundation

/// Kural önizlemesi için başlık eşleştirme.
/// Lua motorundaki `titleMatches` ile aynı davranışı hedefler.
/// `pattern` türü Lua'ya özgü olduğu için burada değerlendirilemez.
enum MatchEvaluator {

    enum Result {
        case matched
        case notMatched
        case notEvaluable
    }

    static func evaluate(_ match: MatchSpec, against title: String) -> Result {
        guard !match.value.isEmpty else { return .notMatched }

        switch match.type {
        case .contains:
            return title.contains(match.value) ? .matched : .notMatched
        case .prefix:
            return title.hasPrefix(match.value) ? .matched : .notMatched
        case .suffix:
            return title.hasSuffix(match.value) ? .matched : .notMatched
        case .exact:
            return title == match.value ? .matched : .notMatched
        case .pattern:
            return .notEvaluable
        }
    }

    static func matches(_ rule: Rule, window: ObservedWindow) -> Bool {
        let applicationMatches: Bool
        if let bundleID = rule.app.bundleID, !bundleID.isEmpty {
            applicationMatches = window.bundleID == bundleID
        } else {
            applicationMatches =
                window.applicationName.lowercased()
                == rule.app.name.lowercased()
        }

        guard applicationMatches else { return false }
        return evaluate(rule.match, against: window.title) == .matched
    }
}
