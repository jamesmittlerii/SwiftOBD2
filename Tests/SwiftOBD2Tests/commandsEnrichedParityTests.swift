@testable import SwiftOBD2
import XCTest

final class CommandsEnrichedParityTests: XCTestCase {
    func testEnrichedCatalogHasSameCommandsAndDescriptions() throws {
        let baseline = try CommandCatalogResources.loadCommands()
        let enriched = try CommandCatalogResources.loadEnrichedCommands()

        let baselinePairs = Set(baseline.map { "\($0.command.uppercased())|\($0.description)" })
        let enrichedPairs = Set(enriched.map { "\($0.command.uppercased())|\($0.description)" })
        XCTAssertEqual(baselinePairs, enrichedPairs)
    }

    func testPidGetterDerivationMatchesRuntimeLogic() throws {
        let enriched = try CommandCatalogResources.loadEnrichedCommands()
        let enrichedGetterCommands = Set(
            enriched
                .filter {
                    let lower = $0.description.lowercased()
                    return lower.contains("supported pids [") || lower.contains("supported mids [")
                }
                .map { $0.command.uppercased() }
        )

        let runtimeGetterCommands = Set(OBDCommand.pidGetters.map { $0.properties.command.uppercased() })
        XCTAssertEqual(enrichedGetterCommands, runtimeGetterCommands)
    }
}
