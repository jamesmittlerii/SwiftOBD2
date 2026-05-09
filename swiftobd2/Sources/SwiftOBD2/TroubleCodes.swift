import Foundation


// MARK: - Public Data Model

public enum CodeSeverity: String, Codable, Hashable, CaseIterable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case critical = "Critical"
}

public struct StatusCodeMetadata: Codable, Hashable {
    public let code: String
    public let description: String
    
    public init(code: String, description: String) {
        self.code = code
        self.description = description
    }
    }


public struct TroubleCodeMetadata: Codable, Hashable {
    public let code: String
    public let title: String
    public let description: String
    public let severity: CodeSeverity
    public let causes: [String]
    public let remedies: [String]
    
    // Expose a public memberwise initializer so app targets can construct samples/previews.
    public init(code: String,
                title: String,
                description: String,
                severity: CodeSeverity,
                causes: [String],
                remedies: [String]) {
        self.code = code
        self.title = title
        self.description = description
        self.severity = severity
        self.causes = causes
        self.remedies = remedies
    }
}

// Internal structure for decoding the indexed JSON
private struct CodesJSON: Codable {
    let causes: [String]
    let remedies: [String]
    let codes: [String: CodeEntry]

    struct CodeEntry: Codable {
        let title: String
        let description: String
        let causeIndexes: [Int]
        let remedyIndexes: [Int]
    }
}

private func determineSeverity(for code: String) -> CodeSeverity {
    switch troubleCodeSeverityLevel(for: code) {
    case .low:
        return .low
    case .moderate:
        return .moderate
    case .high:
        return .high
    case .critical:
        return .critical
    }
}

// MARK: - Public Dictionary (Lazy Loaded)

public let troubleCodeDictionary: [String: TroubleCodeMetadata] = {
    // Use the bundle associated with this file, which is more robust
    // than relying on `Bundle.module` which only works in Swift Packages.
    guard let url = Bundle.module.url(forResource: "codes", withExtension: "json") else {
        fatalError("Could not find codes.json in Swift Package resources.")
    }

    do {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(CodesJSON.self, from: data)

        var output: [String: TroubleCodeMetadata] = [:]
        output.reserveCapacity(decoded.codes.count)

        for (code, entry) in decoded.codes {

            // Resolve causeIndexes → actual strings
            let resolvedCauses = entry.causeIndexes.compactMap { index in
                decoded.causes[safe: index]
            }

            // Resolve remedyIndexes → actual strings
            let resolvedRemedies = entry.remedyIndexes.compactMap { index in
                decoded.remedies[safe: index]
            }

            output[code] = TroubleCodeMetadata(
                code: code,
                title: entry.title,
                description: entry.description,
                severity: determineSeverity(for: code),
                causes: resolvedCauses,
                remedies: resolvedRemedies
            )
        }

        return output

    } catch {
        fatalError("Failed loading codes.json: \(error)")
    }
}()

// MARK: - Helpers

private extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
