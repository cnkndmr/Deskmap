import Foundation
import os

/// M0 (Grup B ölçümü): tarama hattının süre dağılımı. Her ölçü bellekte toplanır, 5 dakikada bir
/// `perf` kategorisine tek özet satırı yazılır (n, p50, p95, en çok). Ayrıca os_signpost aralıkları
/// (Instruments "Points of Interest" yerine `perf` kategorisi). Yalnız ölçüm; davranış değişmez.
final class PerfStats: @unchecked Sendable {
    static let shared = PerfStats()
    static let signposter = OSSignposter(subsystem: "com.deskmap.app", category: "perf")
    private let lock = NSLock()
    private var samples: [String: [Double]] = [:]
    private var counters: [String: Int] = [:]
    private var windowStart = Date()
    private let interval: TimeInterval = 300

    @inline(__always) static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    @inline(__always) static func ms(since t: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds &- t) / 1e6 }

    func add(_ key: String, _ ms: Double) {
        lock.lock()
        samples[key, default: []].append(ms)
        let dump = takeIfDue()
        lock.unlock()
        if let dump { Self.write(dump) }
    }
    func count(_ key: String) {
        lock.lock(); counters[key, default: 0] += 1; let dump = takeIfDue(); lock.unlock()
        if let dump { Self.write(dump) }
    }
    private func takeIfDue() -> (samples: [String: [Double]], counters: [String: Int])? {
        guard Date().timeIntervalSince(windowStart) >= interval else { return nil }
        let d = (samples, counters); samples = [:]; counters = [:]; windowStart = Date()
        return d
    }
    private static func write(_ d: (samples: [String: [Double]], counters: [String: Int])) {
        func q(_ s: [Double], _ p: Double) -> Double { s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))] }
        let parts = d.samples.keys.sorted().map { k -> String in
            let s = d.samples[k]!.sorted()
            return String(format: "%@ n=%d p50=%.1f p95=%.1f max=%.1f", k, s.count, q(s, 0.5), q(s, 0.95), s.last ?? 0)
        } + d.counters.keys.sorted().map { "\($0)=\(d.counters[$0]!)" }
        Log.perf.notice("perf 5m: \(parts.joined(separator: "; "), privacy: .public)")
    }
}
