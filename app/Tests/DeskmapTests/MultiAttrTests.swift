import ApplicationServices
import Foundation
import Testing
@testable import Deskmap

/// Toplu öznitelik okuma (perf/PLAN-perf.md §6.2): tekli yolla aynı kararlar.
struct MultiAttrTests {

    @Test func standardDecisionMatchesTheSingleReadRules() {
        #expect(AX.isStandard(role: kAXWindowRole, subrole: kAXStandardWindowSubrole, strict: true))
        #expect(AX.isStandard(role: nil, subrole: nil, strict: false))
        #expect(!AX.isStandard(role: nil, subrole: nil, strict: true))
        #expect(!AX.isStandard(role: kAXWindowRole, subrole: kAXFloatingWindowSubrole, strict: false))
        #expect(!AX.isStandard(role: kAXWindowRole, subrole: kAXSystemDialogSubrole, strict: false))
        #expect(!AX.isStandard(role: kAXButtonRole, subrole: nil, strict: false))
    }

    /// Okunamayan öznitelik toplu yanıtta hata değeri olarak gelir: nil sayılır.
    @Test func errorValueBecomesNil() {
        var error = AXError.attributeUnsupported
        let value = AXValueCreate(.axError, &error)!
        #expect(AX.multiValue(value) == nil)
        #expect(AX.multiValue("Başlık" as NSString) as? String == "Başlık")
        #expect(AX.multiValue(kCFBooleanTrue) as? Bool == true)
    }
}
