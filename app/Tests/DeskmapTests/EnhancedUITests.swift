import Foundation
import Testing
@testable import Deskmap

@Suite("AXEnhancedUserInterface policy")
struct EnhancedUITests {
    @Test func chromiumBrowsersMatchByPrefix() {
        #expect(AX.isKnownChromium("com.google.Chrome"))
        #expect(AX.isKnownChromium("com.google.Chrome.canary"))
        #expect(AX.isKnownChromium("com.microsoft.edgemac"))
        #expect(AX.isKnownChromium("com.brave.Browser"))
        #expect(AX.isKnownChromium("org.chromium.Chromium"))
    }

    @Test func otherAppsAreNotChromium() {
        #expect(!AX.isKnownChromium("com.apple.Safari"))
        #expect(!AX.isKnownChromium("com.google.ChromeRemoteDesktop"))
        #expect(!AX.isKnownChromium("org.mozilla.firefox"))
        #expect(!AX.isKnownChromium(""))
    }
}
