import Foundation
import Testing
@testable import Deskmap

/// Uygulama listesi önbelleği, açılışı süren uygulama varken kısa (`perf.appsCacheNotify`).
struct AppsCacheNotifyTests {
    @Test func launchingAppKeepsTheListShort() {
        #expect(AX.appsCacheTTL(anyLaunching: true, notify: true) == AX.launchingAppsTTL)
        #expect(AX.launchingAppsTTL <= 1)
    }
    @Test func settledListKeepsTodaysTTL() {
        #expect(AX.appsCacheTTL(anyLaunching: false, notify: true) == AX.runningAppsTTL)
    }
    @Test func flagOffKeepsTodaysTTL() {
        #expect(AX.appsCacheTTL(anyLaunching: true, notify: false) == AX.runningAppsTTL)
    }
}
