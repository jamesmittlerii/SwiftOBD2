import Foundation

public enum CommandCatalogResources {
    public struct CommandRow: Decodable {
        public let command: String
        public let description: String
    }

    public static func loadCommands() throws -> [CommandRow] {
        try loadRows(named: "commands")
    }

    public static func loadEnrichedCommands() throws -> [CommandRow] {
        try loadRows(named: "commands.enriched")
    }

    private static func loadRows(named name: String) throws -> [CommandRow] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw NSError(
                domain: "CommandCatalogResources",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing resource \(name).json"]
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([CommandRow].self, from: data)
    }
}
