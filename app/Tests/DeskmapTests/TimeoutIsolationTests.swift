import ApplicationServices
import Foundation
import Testing
@testable import Deskmap

/// Paylaşılan AX öğesine zaman aşımı yazımı kuyruklar arasında sızmasın (inceleme 24.10).
struct TimeoutIsolationTests {

    /// Yalnız birden çok kuyruk aynı öğeye dokunabildiğinde kopya kullanılır; hepsi kapalıyken bugünkü yol.
    @Test func copiesOnlyWhenAnotherQueueCanTouchTheElement() {
        #expect(!AX.isolatesTimeouts(remoteOffSweep: false, planMovesFast: false, perPidParallel: false))
        #expect(AX.isolatesTimeouts(remoteOffSweep: true, planMovesFast: false, perPidParallel: false))
        #expect(AX.isolatesTimeouts(remoteOffSweep: false, planMovesFast: true, perPidParallel: false))
        #expect(AX.isolatesTimeouts(remoteOffSweep: false, planMovesFast: false, perPidParallel: true))
    }

    /// Kopya aynı öğeyi gösterir (CFEqual) ama ayrı nesnedir; üretilemezse öğenin kendisi döner.
    @Test func privateCopyIsTheSameElementInAnotherObject() {
        let original = AXUIElementCreateApplication(getpid())
        let copy = AX.privateCopy(original)
        #expect(CFEqual(copy, original))
        // Ayrı nesne: zaman aşımı yazımı asıl nesneye (önbellekteki) dokunmaz.
        #expect(copy !== original)
        #expect(AXUIElementSetMessagingTimeout(copy, 0.2) == .success)
    }
}
