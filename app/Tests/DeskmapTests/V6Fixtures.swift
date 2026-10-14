import CoreGraphics
import Foundation
@testable import Deskmap

/// Şema 6 testlerinin ortak yapı taşları ve 12.10.2026 olayının yapay
/// kopyası (docs/desktop-names-v2.md §A.8 walkthrough): aynı space'ler,
/// aynı eski ad tabloları, aynı kural yerleri; başlıklar yapay.
enum V6 {

    static func rule(_ app: String, _ tokens: [String] = [], docked: Destination? = nil,
                     undocked: Destination? = nil) -> Rule {
        var r = Rule(appName: app, bundleID: "b.\(app)", tokens: tokens)
        r.docked = docked
        r.undocked = undocked
        return r
    }

    static func at(_ screen: String, _ desktop: Int, name: String? = nil,
                   layout: WindowLayout = .full) -> Destination {
        Destination(screen: screen, desktop: desktop, layout: layout, nameID: name)
    }

    static func b(_ desktop: Int) -> Destination { at("builtin", desktop) }
    static func e(_ desktop: Int) -> Destination { at("external", desktop) }

    /// Tek profilli belge: adlar ve planlar verilir.
    static func document(rules: [Rule] = [], names: [DesktopName] = [],
                         plans: DesktopPlans = DesktopPlans()) -> Document {
        var d = Document()
        d.rules = rules
        d.names = names
        d.plans = plans
        d.syncActiveProfile()
        return d
    }

    // MARK: - 12.10 olayı

    static let externalLive: [UInt64] = [1681, 1674, 1673, 1672, 1032]
    static let builtinLive: [UInt64] = [5, 4, 6, 8, 1652, 1653, 1678, 1679, 1680]
    static let live = LiveDesktops(mode: .docked, spaces: ["external": externalLive,
                                                           "builtin": builtinLive])
    /// Hayalet olayının anı (17:52:40.024).
    static let incident = Date(timeIntervalSinceReferenceDate: 813513160.024068)

    struct Win {
        var app: String
        var title: String
        var space: UInt64
    }

    /// "normal profil": 42 kurala benzer yapı.
    static func normalProfilRules() -> [Rule] {
        var rules: [Rule] = []
        func both(_ app: String, _ token: String, _ desktop: Int) {
            rules.append(rule(app, token.isEmpty ? [] : [token], docked: b(desktop), undocked: b(desktop)))
        }
        both("Safari", "mail", 1); both("Safari", "news", 1)
        both("Outlook", "", 2); both("Telegram", "chat", 2); both("WhatsApp", "", 2); both("Safari", "bank", 2)
        both("Calendar", "", 3); both("Teams", "", 3); both("Reminders", "", 3)
        both("ChatGPT", "", 4); both("Claude", "", 4); both("OpenCode", "", 4); both("Safari", "assistant", 4)
        rules.append(rule("Terminal", undocked: b(10)))
        for token in ["nova-code"] { both("Code", token, 6) }
        both("Finder", "nova-folder", 6)
        both("Excel", "nova-1", 6); both("Excel", "nova-2", 6); both("Excel", "nova-3", 6)
        for i in 1...5 { both("Preview", "nova-pdf\(i)", 6) }
        for i in 1...3 { rules.append(rule("Word", ["comet\(i)"], docked: e(2), undocked: b(7))) }
        for (app, token) in [("Code", "orion-code"), ("Finder", "orion-folder"), ("Excel", "orion-sheet"),
                             ("Preview", "orion-pdf")] {
            rules.append(rule(app, [token], docked: e(1), undocked: b(9)))
        }
        for (app, token) in [("Code", "lumen-code"), ("Finder", "lumen-folder"), ("Excel", "lumen-sheet"),
                             ("Preview", "lumen-pdf1"), ("Preview", "lumen-pdf2"), ("Preview", "lumen-pdf3"),
                             ("Preview", "lumen-pdf4")] {
            rules.append(rule(app, [token], docked: e(4), undocked: b(8)))
        }
        both("cmux", "hub", 5); both("Notion", "hub", 5); both("Obsidian", "hub", 5)
        return rules
    }

    /// Canlı pencereler (status.json'daki yerlerle aynı space'ler).
    static func normalProfilWindows() -> [Win] {
        var list: [Win] = [
            Win(app: "Safari", title: "mail", space: 5), Win(app: "Safari", title: "news", space: 5),
            Win(app: "Outlook", title: "Inbox", space: 4), Win(app: "Telegram", title: "chat", space: 4),
            Win(app: "WhatsApp", title: "x", space: 4), Win(app: "Safari", title: "bank", space: 4),
            Win(app: "Calendar", title: "x", space: 6), Win(app: "Teams", title: "x", space: 6),
            Win(app: "Reminders", title: "x", space: 6),
            Win(app: "ChatGPT", title: "x", space: 8), Win(app: "Claude", title: "a", space: 8),
            Win(app: "Claude", title: "b", space: 8), Win(app: "OpenCode", title: "x", space: 8),
            Win(app: "Safari", title: "assistant", space: 8),
            Win(app: "cmux", title: "hub", space: 1652), Win(app: "Notion", title: "hub", space: 1652),
            Win(app: "Obsidian", title: "hub", space: 1652),
            Win(app: "Code", title: "nova-code", space: 1653), Win(app: "Finder", title: "nova-folder", space: 1653),
            Win(app: "Excel", title: "nova-1", space: 1653), Win(app: "Excel", title: "nova-2", space: 1653),
            Win(app: "Excel", title: "nova-3", space: 1653),
        ]
        for i in 1...5 { list.append(Win(app: "Preview", title: "nova-pdf\(i)", space: 1653)) }
        for (app, title) in [("Code", "orion-code"), ("Finder", "orion-folder"), ("Excel", "orion-sheet"),
                             ("Preview", "orion-pdf")] {
            list.append(Win(app: app, title: title, space: 1681))
        }
        for i in 1...3 { list.append(Win(app: "Word", title: "comet\(i)", space: 1674)) }
        for (app, title) in [("Code", "lumen-code"), ("Finder", "lumen-folder"), ("Excel", "lumen-sheet"),
                             ("Preview", "lumen-pdf1"), ("Preview", "lumen-pdf2"), ("Preview", "lumen-pdf3"),
                             ("Preview", "lumen-pdf4")] {
            list.append(Win(app: app, title: title, space: 1672))
        }
        return list
    }

    static func evidence(_ windows: [Win], live: LiveDesktops = V6.live) -> MigrationEvidence {
        MigrationEvidence(live: live, windows: windows.enumerated().map { index, window in
            MigrationEvidence.Window(id: CGWindowID(1000 + index), space: window.space,
                                     bundleID: "b.\(window.app)", appName: window.app,
                                     title: window.title)
        })
    }

    static let normalID = "949E-NORMAL"
    static let copyID = "308A-COPY"
    static let denemeID = "EBCB-DENEME"

    /// Üç profilli şema 5 belgesi (okunmuş gibi: `legacy` tabloları dolu).
    static func incidentDocument() -> Document {
        var d = Document()
        let normal = Profile(
            id: normalID, name: "normal profil", rules: normalProfilRules(),
            ghostDesktops: [GhostDesktop(
                screen: "external", name: "Notes Hub", desktop: 1, deletedAt: incident,
                pins: [GhostDesktop.Pin(
                    profileID: normalID, mode: .docked, rule: rule("Terminal", undocked: b(10)),
                    destination: at("external", 1, layout: WindowLayout(x: 0, y: 0, w: 1.0 / 6, h: 1)))])],
            legacy: LegacyNames(
                desktopNames: ["docked|builtin": ["4": "AI Setup", "5": "Notes Hub", "6": "Nova Project"],
                               "docked|external": ["2": "Orion", "3": "Nova Ek", "5": "Lumen"],
                               "undocked|builtin": ["4": "AI Setup", "5": "Notes Hub", "6": "Nova Project",
                                                    "7": "Nova Ek", "8": "Lumen", "9": "Orion"]],
                desktopNameSpaces: ["docked|builtin": ["4": 8, "5": 1652, "6": 1653],
                                    "docked|external": ["2": 1674, "3": 1673, "5": 1032],
                                    "undocked|builtin": ["4": 8, "5": 1652, "6": 1653, "7": 1678,
                                                         "8": 1032, "9": 1672]]))
        let copyGhostPins = [
            GhostDesktop.Pin(profileID: copyID, mode: .docked, rule: rule("Mail"), destination: e(1)),
            GhostDesktop.Pin(profileID: copyID, mode: .docked, rule: rule("Music"), destination: e(1)),
        ]
        let copy = Profile(
            id: copyID, name: "normal setup copy",
            rules: [rule("ChatGPT", docked: b(4), undocked: b(4)), rule("Claude", docked: b(4), undocked: b(4))],
            ghostDesktops: [
                GhostDesktop(screen: "builtin", name: "Orion Projesi", desktop: 11,
                             deletedAt: Date(timeIntervalSinceReferenceDate: 813512113.342926),
                             pins: [GhostDesktop.Pin(profileID: copyID, mode: .undocked,
                                                     rule: rule("Code", ["orion"]), destination: b(11))]),
                GhostDesktop(screen: "builtin", name: "Notes Hub", desktop: 5,
                             deletedAt: Date(timeIntervalSinceReferenceDate: 813512736.335883), pins: []),
                GhostDesktop(screen: "external", name: nil, desktop: 1, deletedAt: incident,
                             pins: copyGhostPins),
            ],
            legacy: LegacyNames(desktopNames: ["docked|builtin": ["4": "AI Setup"], "undocked|builtin": ["4": "AI Setup"]],
                                desktopNameSpaces: ["docked|builtin": ["4": 8], "undocked|builtin": ["4": 8]]))
        let deneme = Profile(
            id: denemeID, name: "normal setup copy (deneme)",
            rules: [rule("ChatGPT", docked: b(4), undocked: b(4))],
            ghostDesktops: [
                GhostDesktop(screen: "builtin", name: "Lumen Makale", desktop: 11,
                             deletedAt: Date(timeIntervalSinceReferenceDate: 813512121.271514), pins: []),
                GhostDesktop(screen: "external", name: nil, desktop: 1, deletedAt: incident,
                             pins: [GhostDesktop.Pin(profileID: denemeID, mode: .docked,
                                                     rule: rule("Mail"), destination: e(1))]),
            ],
            legacy: LegacyNames(
                desktopNames: ["docked|builtin": ["4": "AI Setup"], "docked|external": ["4": "Nova Ek"],
                               "undocked|builtin": ["4": "AI Setup", "7": "Nova Ek"]],
                desktopNameSpaces: ["docked|builtin": ["4": 8], "docked|external": ["4": 1672],
                                    "undocked|builtin": ["4": 8, "7": 1678]]))
        d.profiles = [copy, deneme, normal]
        d.activeProfileID = normalID
        d.loadProfileState(normal)
        d.fileVersion = 5
        return d
    }

    /// Profilin adı → space.
    static func bindings(_ profile: Profile) -> [String: UInt64?] {
        Dictionary(profile.names.map { ($0.name, $0.space) }, uniquingKeysWith: { a, _ in a })
    }

    /// Plan girdilerini adlara çevirir ("" kalır).
    static func named(_ entries: [String], _ profile: Profile) -> [String] {
        entries.map { id in id.isEmpty ? "" : profile.names.first { $0.id == id }?.name ?? "?" }
    }
}
