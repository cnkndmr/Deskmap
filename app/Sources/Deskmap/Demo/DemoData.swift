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
                  title: "Space Router · GitHub — Safari", screen: "builtin", desktop: 1),
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
            window(11, pid: 5111, app: "Terminal", bundle: "com.apple.Terminal",
                  title: "~ — Terminal", screen: "builtin", desktop: 4),
        ]

        return World(document: document, screens: [builtinScreen, externalScreen], windows: windows)
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
