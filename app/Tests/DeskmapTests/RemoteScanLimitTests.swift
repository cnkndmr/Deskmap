import Foundation
import Testing
@testable import Deskmap

/// Uzak taramanın sınırı ve belirteçten öğe kimliği.
struct RemoteScanLimitTests {

    @Test func unknownAppUsesTheBaseLimit() {
        #expect(AX.scanLimit(highestSeen: nil) == AX.remoteScanLimit)
        #expect(AX.scanLimit(highestSeen: 45) == AX.remoteScanLimit)
    }

    /// Safari 22.10: görünen pencere 9102, başka masaüstündeki pencere 8538.
    @Test func highIDsRaiseTheLimit() {
        let limit = AX.scanLimit(highestSeen: 9102)
        #expect(limit == 9102 + AX.remoteScanMargin)
        #expect(limit > 8538)
    }

    @Test func limitIsCapped() {
        #expect(AX.scanLimit(highestSeen: 1_000_000) == AX.remoteScanCeiling)
    }

    /// Ölçülen Safari belirteci: pid 0x2f93, "coco", kimlik 0x231c (8988).
    @Test func elementIDFromToken() {
        let hex = "932f0000000000006f636f631c23000000000000"
        let bytes = stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        #expect(AX.elementID(token: Data(bytes)) == 8988)
    }

    @Test func malformedTokenHasNoID() {
        #expect(AX.elementID(token: Data(repeating: 0, count: 20)) == nil)
        #expect(AX.elementID(token: Data(repeating: 0, count: 12)) == nil)
    }
}
