import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// Taşıma doğrulanmamış macOS'larda görünür kapalı mod (PLAN K4, saf).
struct MoveSupportTests {

    @Test func unverifiedVersions() {
        for (major, minor) in [(15, 0), (15, 6), (26, 0), (26, 3)] {
            #expect(MoveSupport.classify(major: major, minor: minor, hasMovePath: true) == .unverified)
        }
    }

    @Test func supportedVersions() {
        for (major, minor) in [(13, 0), (14, 5), (26, 4), (26, 6), (27, 0)] {
            #expect(MoveSupport.classify(major: major, minor: minor, hasMovePath: true) == .supported)
        }
    }

    @Test func noMovePathIsUnavailableOnAnyVersion() {
        #expect(MoveSupport.classify(major: 15, minor: 1, hasMovePath: false) == .unavailable)
        #expect(MoveSupport.classify(major: 27, minor: 0, hasMovePath: false) == .unavailable)
    }

    @Test func versionLabelDropsZeroPatch() {
        #expect(MoveSupport.versionLabel(.init(majorVersion: 15, minorVersion: 3, patchVersion: 0)) == "15.3")
        #expect(MoveSupport.versionLabel(.init(majorVersion: 26, minorVersion: 1, patchVersion: 2)) == "26.1.2")
    }

    @Test func heldHealthBlocksMovesAndIgnoresResults() {
        var health = MoveHealth(held: true)
        #expect(health.state == .held)
        #expect(!health.movesAllowed)
        let afterVerified = health.record(window: 1, verified: true)
        let afterFailed = health.record(window: 2, verified: false)
        #expect(!afterVerified)
        #expect(!afterFailed)
        #expect(health.state == .held)
        #expect(health.consecutiveFailures == 0)
    }

    /// "Yine de dene": bekletme kalkar, devre kesici normal izler.
    @Test func resetFromHeldAllowsMovesAndBreakerStillWorks() {
        var health = MoveHealth(held: true)
        health.reset()
        #expect(health.state == .unknown)
        #expect(health.movesAllowed)
        for i in 0..<MoveHealth.failureLimit {
            health.record(window: CGWindowID(i % 2 + 1), verified: false)
        }
        #expect(health.state == .degraded)
    }

    @Test func cardReasonFollowsCapabilityAndHealth() {
        typealias Reason = ReducedModeCard.Reason
        #expect(Reason.current(canMove: false, health: .working, version: "15.3") == .unavailable)
        #expect(Reason.current(canMove: true, health: .held, version: "15.3") == .unverified(version: "15.3"))
        #expect(Reason.current(canMove: true, health: .degraded, version: "26.6") == .failed)
        #expect(Reason.current(canMove: true, health: .unknown, version: "26.6") == nil)
        #expect(Reason.current(canMove: true, health: .working, version: "26.6") == nil)
    }
}
