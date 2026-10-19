import Combine
import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Plan seçicinin gerçek modu izlemesi (docs/bug-tables.md A′, plan seçici
/// satırı): `ScreenService.$screens` willSet'te yayınlar, abone o anda
/// `screens.mode` okursa bir adım geride kalır; seçici yayınlanan listeyi kullanır.
@MainActor
struct PlanPickerFollowTests {

    private func screen(_ id: String) -> ScreenInfo {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        return ScreenInfo(id: id, uuid: id.uppercased(), name: id, isBuiltin: id == "builtin",
                          frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 20))
    }

    /// Kök neden: yayın anında servis hâlâ eski listeyi döndürür.
    @Test func publishIsWillSet() {
        let service = ScreenService(demo: [screen("builtin")])
        var seen: [(published: Mode, read: Mode)] = []
        let cancellable = service.$screens.dropFirst().sink { list in
            seen.append((ScreenService.mode(of: list), service.mode))
        }
        service.replaceDemoScreens([screen("builtin"), screen("external")])
        cancellable.cancel()
        #expect(seen.count == 1)
        #expect(seen.first?.published == .docked)
        #expect(seen.first?.read == .undocked)
    }

    /// Tek değişimde seçici yeni moda geçer; mod değişmediyse dokunmaz.
    @Test func pickerFollowsPublishedScreens() {
        let service = ScreenService(demo: [screen("builtin")])
        var liveMode: Mode? = service.mode
        var picked: [Mode] = []
        let cancellable = service.$screens.dropFirst().sink { list in
            if let next = RootView.followedMode(published: list, liveMode: liveMode) {
                liveMode = next
                picked.append(next)
            }
        }
        service.replaceDemoScreens([screen("builtin"), screen("external")])
        #expect(picked == [.docked])
        service.replaceDemoScreens([screen("builtin"), screen("external"), screen("external-2")])
        #expect(picked == [.docked])
        service.replaceDemoScreens([screen("builtin")])
        #expect(picked == [.docked, .undocked])
        cancellable.cancel()
    }
}
