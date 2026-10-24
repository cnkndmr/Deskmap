import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// perf/PLAN-perf.md §4.1 A1: plan okuması kendi kuyruğunda.
struct PlanReadQueueTests {

    /// A1: tarama kuyruğu meşgulken plan okuması beklemez (bayrak açık); kapalıyken aynı kuyruk.
    @Test func planReadDoesNotWaitBehindTheSweepQueue() {
        let router = DispatchQueue(label: "test.router")
        #expect(Router.planQueue(router: router, ownQueue: false) === router)
        let busy = DispatchSemaphore(value: 0)
        router.async { busy.wait() }
        let done = DispatchSemaphore(value: 0)
        Router.planQueue(router: router, ownQueue: true).async { done.signal() }
        #expect(done.wait(timeout: .now() + 1) == .success)
        busy.signal()
    }
}
