import Foundation
import Testing
@testable import Deskmap

/// Yönlendirme nesli: eski nesille başlamış taramanın yan etkisi kesilir (P0-2).
struct RoutingGenerationTests {

    @Test func tokenIsCurrentUntilAdvance() {
        let generation = RoutingGeneration()
        let token = generation.token()
        #expect(token.isCurrent)
        generation.advance()
        #expect(!token.isCurrent)
        #expect(generation.token().isCurrent)
    }

    @Test func everyAdvanceInvalidatesOlderTokens() {
        let generation = RoutingGeneration()
        let tokens = (0..<3).map { _ -> RoutingGeneration.Token in
            defer { generation.advance() }
            return generation.token()
        }
        #expect(tokens.allSatisfy { !$0.isCurrent })
        #expect(Set(tokens.map(\.value)).count == 3)
    }

    @Test func concurrentAdvancesAreCounted() async {
        let generation = RoutingGeneration()
        let start = generation.current
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { generation.advance() } }
        }
        #expect(generation.current == start + 100)
    }
}
