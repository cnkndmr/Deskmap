import CoreGraphics
import Foundation

/// "Shots" modu (`--shots`) için uydurma demo dünyası: iki ekran, iki
/// profil, birkaç pinli kural ve canlı pencere. Kişisel veri yok; App
/// Store / web sitesi ekran görüntüleri için gerçek `RootView`'ı besler
/// (bkz. `Shots.swift`). Diske dokunmaz, gerçek `Store`/`Router` verisiyle
/// hiçbir ilişkisi yoktur.
enum DemoData {

    struct World {
        let document: Document
        let screens: [ScreenInfo]
        let windows: [Router.WindowSnapshot]
    }

    // MARK: - Shots.swift'in belirli kural/pencereleri seçmesi için sabit kimlikler

    /// "acme-web — Messages" penceresini pinleyen kural (RulePanel / düzen
    /// seçici karesi bunu açar).
    static let messagesRuleID = "demo-rule-messages"
    /// Yalnızca "Geri al" çubuğunu sergilemek için var; son karadan hemen
    /// önce silinir.
    static let extraRuleID = "demo-rule-safari-docs"
    /// Hiçbir kuralla eşleşmeyen canlı pencere (yeni pin karesi bunu kullanır).
    static let unpinnedMessagesWindowID: CGWindowID = 9

    // MARK: - Ekranlar

    private static let builtinScreen = ScreenInfo(
        id: "builtin", uuid: "DEMO-BUILTIN-SCREEN-0001", name: "Built-in Display",
        isBuiltin: true, frame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 919))

    private static let externalScreen = ScreenInfo(
        id: "external", uuid: "DEMO-EXTERNAL-SCREEN-0001", name: "Studio Display",
        isBuiltin: false, frame: CGRect(x: 1512, y: -248, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: -248, width: 2560, height: 1415))

    // MARK: - Dünya

    static func make() -> World {
        let builtin = builtinScreen.known
        let external = externalScreen.known

        // MARK: "Desk" (aktif profil)

        // Figma/Slack yerine her Mac'te kurulu gelen sistem uygulamaları:
        // gerçek ikon çıksın, "app.dashed" yer tutucusu görünmesin.
        let reminders = Rule(
            appName: "Reminders", bundleID: "com.apple.reminders", tokens: ["Design Review"],
            docked: Destination(screen: "external", desktop: 1, layout: .full))

        let messages = Rule(
            id: messagesRuleID, appName: "Messages", bundleID: "com.apple.MobileSMS",
            tokens: ["acme-web"],
            docked: Destination(screen: "external", desktop: 2, layout: .rightHalf))

        let mail = Rule(
            appName: "Mail", bundleID: "com.apple.mail", tokens: ["Release notes"],
            docked: Destination(screen: "external", desktop: 2, layout: .leftHalf))

        let terminal = Rule(
            appName: "Terminal", bundleID: "com.apple.Terminal", tokens: ["deploy"],
            docked: Destination(screen: "external", desktop: 3, layout: .center))

        let safariGitHub = Rule(
            appName: "Safari", bundleID: "com.apple.Safari", tokens: ["GitHub"],
            docked: Destination(screen: "builtin", desktop: 1, layout: .leftHalf))

        let vscode = Rule(
            appName: "Visual Studio Code", bundleID: "com.microsoft.VSCode", tokens: ["acme-web"],
            docked: Destination(screen: "builtin", desktop: 1, layout: .rightHalf),
            undocked: Destination(screen: "builtin", desktop: 1, layout: .full))

        // Shots.swift bu ekranın gerçek masaüstü sayısını 3'müş gibi
        // gösterir (`ui.desktopCounts`); masaüstü 5 hedefi "eksik masaüstü"
        // rozetini (D5→3) sergiler.
        let obsidian = Rule(
            appName: "Obsidian", bundleID: "md.obsidian", tokens: [],
            docked: Destination(screen: "external", desktop: 5, layout: .full))

        // Yalnızca alt çubuktaki "Geri al"ı sergilemek için: Shots.swift son
        // kareden hemen önce bunu siler.
        let safariDocs = Rule(
            id: extraRuleID, appName: "Safari", bundleID: "com.apple.Safari", tokens: ["Docs"],
            docked: Destination(screen: "builtin", desktop: 2, layout: .topHalf))

        let deskRules = [reminders, messages, mail, terminal, safariGitHub, vscode, obsidian, safariDocs]

        // MARK: "Café" (ikinci profil; canlı penceresi yok)

        let cafeRules = [
            Rule(appName: "Safari", bundleID: "com.apple.Safari", tokens: [],
                docked: Destination(screen: "builtin", desktop: 1, layout: .full)),
            Rule(appName: "Messages", bundleID: "com.apple.MobileSMS", tokens: [],
                docked: Destination(screen: "builtin", desktop: 2, layout: .full)),
        ]

        let deskProfile = Profile(id: "demo-profile-desk", name: "Desk", rules: deskRules)
        let cafeProfile = Profile(id: "demo-profile-cafe", name: "Café", rules: cafeRules)

        var document = Document()
        document.enabled = true
        // Kapalı: harita karesi (01) doğrudan görünsün. Shots.swift, macOS
        // ayar kartını sergileyen kareden (05) hemen önce bunu tekrar açar.
        document.setupNoticeDismissed = true
        document.screens = [builtin, external]
        document.profiles = [deskProfile, cafeProfile]
        document.activeProfileID = deskProfile.id
        document.rules = deskProfile.rules

        // MARK: Canlı pencereler

        let windows: [Router.WindowSnapshot] = [
            window(1, pid: 5101, app: "Reminders", bundle: "com.apple.reminders",
                  title: "Design Review — Reminders", screen: "external", desktop: 1),
            window(2, pid: 5102, app: "Messages", bundle: "com.apple.MobileSMS",
                  title: "acme-web — Messages", screen: "external", desktop: 2),
            window(3, pid: 5103, app: "Mail", bundle: "com.apple.mail",
                  title: "Release notes — Mail", screen: "external", desktop: 2),
            window(4, pid: 5104, app: "Terminal", bundle: "com.apple.Terminal",
                  title: "deploy · ~/acme-web — Terminal", screen: "external", desktop: 3),
            window(5, pid: 5105, app: "Obsidian", bundle: "md.obsidian",
                  title: "Handbook — Obsidian", screen: "external", desktop: 5),
            window(6, pid: 5106, app: "Safari", bundle: "com.apple.Safari",
                  title: "Deskmap · GitHub — Safari", screen: "builtin", desktop: 1),
            window(7, pid: 5107, app: "Visual Studio Code", bundle: "com.microsoft.VSCode",
                  title: "acme-web — VS Code", screen: "builtin", desktop: 1),
            window(8, pid: 5108, app: "Safari", bundle: "com.apple.Safari",
                  title: "Docs — Safari", screen: "builtin", desktop: 2),
            // Pinsiz canlı pencereler (hiçbir kuralla eşleşmez).
            window(unpinnedMessagesWindowID, pid: 5109, app: "Messages",
                  bundle: "com.apple.MobileSMS", title: "general — Messages",
                  screen: "builtin", desktop: 2),
            window(10, pid: 5110, app: "Mail", bundle: "com.apple.mail",
                  title: "Inbox — Mail", screen: "builtin", desktop: 3),
            // Tam ekran space: Masaüstü 2 ile 3 arasında, salt okunur satır.
            Router.WindowSnapshot(
                id: 12, pid: 5112, appName: "Keynote", bundleID: "com.apple.iWork.Keynote",
                title: "Q3 Review — Keynote", placement: nil, frame: nil, isMinimized: false,
                fullscreen: Router.FullscreenSlot(
                    screen: "external", space: 9001, afterDesktop: 2, order: 2)),
            window(11, pid: 5111, app: "Terminal", bundle: "com.apple.Terminal",
                  title: "~ — Terminal", screen: "builtin", desktop: 4),
        ]

        return World(document: document, screens: [builtinScreen, externalScreen], windows: windows)
    }

    // MARK: - Uzun başlık senaryosu

    /// Uzun, bölünmeyen başlık parçalı kural ve pencere: sağ sütunun taşmadığını
    /// gösteren kareler (13-long-title*) için; dünyaya eklenmez, Shots.swift o
    /// kareler için ekleyip kaldırır.
    static let longTitleRuleID = "demo-rule-long-title"
    static let longTitleToken = "Comet_algorithm_change"

    static func longTitleRule() -> Rule {
        Rule(id: longTitleRuleID, appName: "Preview", bundleID: "com.apple.Preview",
             tokens: [longTitleToken, "v2"],
             docked: Destination(screen: "external", desktop: 2, layout: .topHalf))
    }

    /// Yarım ya da tam olmayan çerçeve: temel düzen satırına beşinci döşeme gelir.
    static func longTitleWindow() -> Router.WindowSnapshot {
        Router.WindowSnapshot(
            id: 13, pid: 5113, appName: "Preview", bundleID: "com.apple.Preview",
            title: "\(longTitleToken)_v2_final.pdf — Preview",
            placement: Router.Placement(screen: "builtin", desktop: 2),
            frame: CGRect(x: 140, y: 120, width: 860, height: 610), isMinimized: false)
    }

    // MARK: - Kalabalık senaryo (`--scenario crowded`)

    /// Görsel haritanın gerçek kullanımdaki hâli: laptop + harici ekran,
    /// adlı masaüstleri, bir masaüstünde 10 tam boy pencere, iki pencereli
    /// Terminal grubu, penceresi kapalı 4 Preview sabitlemesi, uzun başlık,
    /// boş ve eksik masaüstü, tam ekran space. Kişisel veri yok.
    static let crowdedOutlookRuleID = "crowded-rule-outlook"
    static let crowdedOutlookWindowID: CGWindowID = 102
    static let crowdedMessagesWindowID: CGWindowID = 109
    static let crowdedFreeWindowID: CGWindowID = 131
    static let crowdedCometRuleID = "crowded-rule-comet"
    static let crowdedCometWindowID: CGWindowID = 121

    private static let retinaScreen = ScreenInfo(
        id: "builtin", uuid: "DEMO-BUILTIN-SCREEN-0002", name: "Built-in Retina Display",
        isBuiltin: true, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945))

    private static let monitorScreen = ScreenInfo(
        id: "external", uuid: "DEMO-EXTERNAL-SCREEN-0002", name: "Studio Display",
        isBuiltin: false, frame: CGRect(x: 1512, y: -248, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: -248, width: 2560, height: 1415))

    /// Ekran başına gerçek masaüstü sayısı (Shots bunu sabitler): laptopta 4,
    /// bu yüzden 5. masaüstüne sabitli pin "eksik" görünür.
    static let crowdedDesktopCounts = ["builtin": 4, "external": 3]

    static func crowded() -> World {
        func dest(_ screen: String, _ desktop: Int, _ layout: WindowLayout = .full) -> Destination {
            Destination(screen: screen, desktop: desktop, layout: layout)
        }
        func rule(id: String? = nil, _ app: String, _ bundle: String, _ tokens: [String],
                  docked: Destination?, undocked: Destination? = nil) -> Rule {
            if let id {
                return Rule(id: id, appName: app, bundleID: bundle, tokens: tokens,
                            docked: docked, undocked: undocked)
            }
            return Rule(appName: app, bundleID: bundle, tokens: tokens, docked: docked, undocked: undocked)
        }

        let rules: [Rule] = [
            // Laptop · Masaüstü 1 "AI Setup": hepsi tam boy.
            rule("Calendar", "com.apple.iCal", [],
                 docked: dest("builtin", 1), undocked: dest("builtin", 1)),
            rule(id: crowdedOutlookRuleID, "Microsoft Outlook", "com.microsoft.Outlook", [],
                 docked: dest("builtin", 1), undocked: dest("builtin", 1)),
            rule("Microsoft Teams", "com.microsoft.teams2", [],
                 docked: dest("builtin", 1), undocked: dest("builtin", 1)),
            rule("Reminders", "com.apple.reminders", [], docked: dest("builtin", 1)),
            rule("ChatGPT", "com.openai.codex", [], docked: dest("builtin", 1),
                 undocked: dest("builtin", 2)),
            rule("Claude", "com.anthropic.claudefordesktop", [], docked: dest("builtin", 1),
                 undocked: dest("builtin", 2)),
            rule("OpenCode", "ai.opencode.desktop", [], docked: dest("builtin", 1)),
            rule("Safari", "com.apple.Safari", ["Acme"], docked: dest("builtin", 1)),
            // Masaüstü 2 "Notes Hub": Obsidian tam, iki Terminal sağ yarıda.
            rule("Obsidian", "md.obsidian", [], docked: dest("builtin", 2),
                 undocked: dest("builtin", 3)),
            rule("Terminal", "com.apple.Terminal", [], docked: dest("builtin", 2, .rightHalf),
                 undocked: dest("builtin", 3, .rightHalf)),
            // Masaüstü 3 "Nova Projesi": uzun başlıklı PDF, kod,
            // penceresi kapalı dört PDF.
            rule(id: crowdedCometRuleID, "Preview", "com.apple.Preview", [longTitleToken],
                 docked: dest("builtin", 3, .leftHalf), undocked: dest("builtin", 4)),
            rule("Visual Studio Code", "com.microsoft.VSCode", ["Nova"],
                 docked: dest("builtin", 3, .rightHalf), undocked: dest("builtin", 4)),
            rule("Preview", "com.apple.Preview", ["Orion_report_v3"],
                 docked: dest("builtin", 3), undocked: dest("builtin", 4)),
            rule("Preview", "com.apple.Preview", ["Nova_Conf2027_draft"],
                 docked: dest("builtin", 3), undocked: dest("builtin", 4)),
            rule("Preview", "com.apple.Preview", ["Expo_template"],
                 docked: dest("builtin", 3), undocked: dest("builtin", 4)),
            rule("Preview", "com.apple.Preview", ["Vega_notes"],
                 docked: dest("builtin", 3), undocked: dest("builtin", 4)),
            // Masaüstü 5 "Lumen Makale" bu laptopta yok (gerçekte 4 masaüstü).
            rule("Notes", "com.apple.Notes", ["Lumen"], docked: dest("builtin", 5)),
            // Harici · Masaüstü 1 "Orion Projesi".
            rule("Safari", "com.apple.Safari", ["Orion"],
                 docked: dest("external", 1, .leftHalf), undocked: dest("builtin", 4)),
            rule("Visual Studio Code", "com.microsoft.VSCode", ["Orion"],
                 docked: dest("external", 1, .rightHalf)),
            // Harici · Masaüstü 2.
            rule("Mail", "com.apple.mail", [], docked: dest("external", 2),
                 undocked: dest("builtin", 2)),
        ]

        var document = Document()
        document.enabled = true
        document.setupNoticeDismissed = true
        document.screens = [retinaScreen.known, monitorScreen.known]
        let profile = Profile(id: "crowded-profile", name: "Desk", rules: rules)
        document.profiles = [profile]
        document.activeProfileID = profile.id
        document.rules = rules
        for mode in Mode.allCases {
            _ = document.setDesktopName("AI Setup", screen: "builtin", desktop: 1, mode: mode)
            _ = document.setDesktopName("Notes Hub", screen: "builtin", desktop: 2, mode: mode)
            _ = document.setDesktopName("Nova Projesi", screen: "builtin", desktop: 3,
                                        mode: mode)
            _ = document.setDesktopName("Lumen Makale", screen: "builtin", desktop: 5, mode: mode)
        }
        _ = document.setDesktopName("Orion Projesi", screen: "external", desktop: 1, mode: .docked)

        let screens = [retinaScreen, monitorScreen]
        // AX koordinatlarında (sol üst köşe tabanlı) ekranın kullanılabilir
        // alanına göre bir çerçeve: pinsiz pencereler gerçek yerinde çizilir.
        func frame(_ screen: ScreenInfo, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            let area = Coordinates.axRect(fromCocoa: screen.visibleFrame, screens: screens)
            return CGRect(x: area.minX + area.width * x, y: area.minY + area.height * y,
                          width: area.width * w, height: area.height * h)
        }
        func win(_ id: CGWindowID, _ app: String, _ bundle: String, _ title: String,
                 _ screen: String, _ desktop: Int, frame: CGRect? = nil) -> Router.WindowSnapshot {
            Router.WindowSnapshot(
                id: id, pid: pid_t(6000 + Int(id)), appName: app, bundleID: bundle, title: title,
                placement: Router.Placement(screen: screen, desktop: desktop),
                frame: frame, isMinimized: false)
        }
        let windows: [Router.WindowSnapshot] = [
            win(101, "Calendar", "com.apple.iCal", "Calendar", "builtin", 1),
            win(crowdedOutlookWindowID, "Microsoft Outlook", "com.microsoft.Outlook",
                "Inbox • Acme Corp", "builtin", 1),
            win(103, "Microsoft Teams", "com.microsoft.teams2", "Chat | Team weekly | Microsoft Teams",
                "builtin", 1),
            win(104, "Reminders", "com.apple.reminders", "Reminders", "builtin", 1),
            win(105, "ChatGPT", "com.openai.codex", "ChatGPT", "builtin", 1),
            win(106, "Claude", "com.anthropic.claudefordesktop", "Claude", "builtin", 1),
            win(107, "OpenCode", "ai.opencode.desktop", "OpenCode — Atlas", "builtin", 1),
            win(108, "Safari", "com.apple.Safari", "Acme Intranet — Safari", "builtin", 1),
            // Geçici sabitleme (turuncu), tam boy.
            win(crowdedMessagesWindowID, "Messages", "com.apple.MobileSMS", "Messages", "builtin", 1),
            // Pinsiz, kendi yerinde ve boyunda.
            win(110, "Notes", "com.apple.Notes", "Quick Note", "builtin", 1,
                frame: frame(retinaScreen, 0.62, 0.30, 0.34, 0.55)),
            win(111, "Obsidian", "md.obsidian", "Hub — Obsidian", "builtin", 2),
            win(112, "Terminal", "com.apple.Terminal", "~/Documents/Atlas — zsh", "builtin", 2),
            win(113, "Terminal", "com.apple.Terminal", "claude — Atlas — 120×40", "builtin", 2),
            win(crowdedCometWindowID, "Preview", "com.apple.Preview",
                "\(longTitleToken)_v2_final.pdf — Preview", "builtin", 3),
            win(122, "Visual Studio Code", "com.microsoft.VSCode", "comet.py — Nova-Project",
                "builtin", 3),
            win(130, "Safari", "com.apple.Safari", "Orion — Overleaf — Safari", "external", 1),
            win(crowdedFreeWindowID, "Visual Studio Code", "com.microsoft.VSCode",
                "model.py — Orion-Makale", "external", 1),
            win(140, "Mail", "com.apple.mail", "Inbox — Mail", "external", 2),
            win(141, "Finder", "com.apple.finder", "Downloads", "external", 2,
                frame: frame(monitorScreen, 0.55, 0.45, 0.32, 0.38)),
            win(150, "Music", "com.apple.Music", "Music", "external", 3,
                frame: frame(monitorScreen, 0.12, 0.10, 0.50, 0.62)),
            Router.WindowSnapshot(
                id: 160, pid: 6160, appName: "Keynote", bundleID: "com.apple.iWork.Keynote",
                title: "Q3 Review — Keynote", placement: nil, frame: nil, isMinimized: false,
                fullscreen: Router.FullscreenSlot(
                    screen: "external", space: 9101, afterDesktop: 2, order: 2)),
        ]
        return World(document: document, screens: screens, windows: windows)
    }

    private static func window(
        _ id: CGWindowID, pid: pid_t, app: String, bundle: String, title: String,
        screen: String, desktop: Int
    ) -> Router.WindowSnapshot {
        Router.WindowSnapshot(
            id: id, pid: pid, appName: app, bundleID: bundle, title: title,
            placement: Router.Placement(screen: screen, desktop: desktop),
            frame: nil, isMinimized: false)
    }
}
