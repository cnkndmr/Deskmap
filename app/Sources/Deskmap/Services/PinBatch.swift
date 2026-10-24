import AppKit
import ApplicationServices

// MARK: - Toplu aç / kapat

/// Bir masaüstündeki pinleri topluca açma ve bir uygulama grubundaki pinli
/// pencereleri topluca kapatma. Karar mantığı saf (test edilir); yan etki
/// (`open`, `close`) ayrı.
@MainActor
enum PinBatch {

    /// Grup başlığındaki düğmenin yapacağı iş.
    enum GroupAction: Equatable { case open, close, none }

    /// Kapalı pin varsa önce onlar açılır (yarı açık grup tamamlanır);
    /// hepsi açıksa pinli pencereler kapanır; ikisi de yoksa düğme yok.
    nonisolated static func groupAction(openPinned: Int, closed: Int) -> GroupAction {
        if closed > 0 { return .open }
        if openPinned > 0 { return .close }
        return .none
    }

    /// Açılacak pinler: penceresi gerçekten kapalı olanlar. Gölgede kalan
    /// (penceresi açık ama başka kurala yenilen) pin açılmaz; penceresi
    /// zaten var.
    nonisolated static func reopenable(_ rules: [Rule], shadowed: [String: String]) -> [Rule] {
        rules.filter { shadowed[$0.id] == nil }
    }

    /// Pin grubunun aç/kapat girdisi (saf, K3): grubun bu moddaki bütün
    /// üyeleri, hangi masaüstünde olurlarsa. `openPinned`: kazanan kuralı
    /// üye olan açık pencereler (`ruleFor`, oturum pini kazanırsa nil);
    /// `closed`: hiçbir açık pencereye uymayan, gölgede olmayan üyeler.
    nonisolated static func pinGroupInput(members: [Rule], windows: [Router.WindowSnapshot],
                                          shadowed: [String: String],
                                          ruleFor: (Router.WindowSnapshot) -> Rule?)
        -> (openPinned: [Router.WindowSnapshot], closed: [Rule]) {
        let ids = Set(members.map(\.id))
        let openPinned = windows.filter { ruleFor($0).map { ids.contains($0.id) } ?? false }
        let closed = members.filter { rule in !windows.contains { rule.matches($0) } }
        return (openPinned, reopenable(closed, shadowed: shadowed))
    }

    /// Pinleri sırayla açar (aynı uygulamaya art arda belge vermek için
    /// kısa ara). Açılamayanlar tek uyarıda toplanır.
    static func open(_ rules: [Rule], mode: Mode, router: Router, store: Store) {
        guard !rules.isEmpty else { return }
        Task { @MainActor in await openAll(rules, mode: mode, router: router, store: store) }
    }

    /// `open`'ın gövdesi; son pin denenince döner (çift basmayı önleyen
    /// düğme bitişi bekler).
    static func openAll(_ rules: [Rule], mode: Mode, router: Router, store: Store) async {
        guard !rules.isEmpty else { return }
        var failed: [String] = []
        for (i, rule) in rules.enumerated() {
            if i > 0 { try? await Task.sleep(nanoseconds: 400_000_000) }
            let target = router.reopenTargets[rule.id]
            if Reopen.isSafari(rule) {
                if await !Reopen.openSafari(rule: rule, target: target,
                                            destination: rule[mode], router: router) {
                    failed.append(rule.appName)
                }
                continue
            }
            switch Reopen.open(rule: rule, target: target) {
            case .opened: break
            case .appOnly: failed.append(rule.title.isEmpty ? rule.appName : rule.title)
            case .noApp: failed.append(rule.appName)
            }
        }
        if !failed.isEmpty {
            store.report(L("Could not open every pin; check: %@",
                           Array(Set(failed)).sorted().joined(separator: ", ")))
        }
    }

    /// Pencereleri kapat düğmesiyle kapatır (uygulama açık kalır, kayıtsız
    /// belgede uygulamanın kendi "kaydet?" sorusu çıkar). Pin kuralları
    /// silinmez; pencere kapanınca soluk çipe döner.
    static func close(_ windows: [Router.WindowSnapshot], store: Store) {
        var failed = 0
        for window in windows {
            guard let element = AX.element(pid: window.pid, windowID: window.id) else {
                failed += 1; continue
            }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString,
                                                &value) == .success,
                  let button = value, CFGetTypeID(button) == AXUIElementGetTypeID()
            else { failed += 1; continue }
            // swiftlint:disable:next force_cast
            if AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                != .success { failed += 1 }
        }
        if failed > 0 { store.report(L("Could not close %ld windows", failed)) }
    }
}
