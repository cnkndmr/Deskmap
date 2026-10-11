import SwiftUI
import Testing
@testable import Deskmap

/// Panellerin Esc kısayolu: metin alanı (arama, masaüstü adı) düzenlenirken
/// kapalı, böylece Esc önce alanı temizler ya da adlandırmayı bırakır.
struct ShortcutScopeTests {

    @Test func cancelShortcutOffWhileEditing() {
        #expect(UIState.cancelShortcut(textEditing: false) == .cancelAction)
        #expect(UIState.cancelShortcut(textEditing: true) == nil)
    }

    @Test @MainActor func editorsAreTrackedByID() {
        let ui = UIState()
        ui.setEditing("search", true)
        ui.setEditing("desktop|a|2", true)
        ui.setEditing("search", false)
        #expect(ui.cancelShortcut == nil)
        ui.setEditing("desktop|a|2", false)
        #expect(ui.cancelShortcut == .cancelAction)
    }
}
