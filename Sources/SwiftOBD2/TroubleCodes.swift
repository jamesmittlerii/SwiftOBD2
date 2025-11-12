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

/// Determines the severity of a trouble code based on a set of predefined rules.
/// - Warning: This is a simplified heuristic and may not be accurate for all codes. It's recommended to consult a professional mechanic or official documentation for precise severity information.
/// - Parameter code: The trouble code string (e.g., "P0300").
/// - Returns: The estimated `Severity` of the code.
private func determineSeverity(for code: String) -> CodeSeverity {
    // Critical Issues: Directly affect safety or risk immediate and severe engine damage.
    // Misfires, Overheating, Overspeed, Overboost, Critical ECU failures, Severe fuel pressure issues.
    let criticalCodes = ["P0087", "P0088", "P0217", "P0218", "P0219", "P0234", "P0606"]
    if criticalCodes.contains(code) || code.hasPrefix("P030") || code.hasPrefix("P031") {
        return .critical
    }

    // High Severity Issues: Can cause poor performance, potential engine damage if ignored.
    // Fuel trim, knock sensors, crank/cam sensors, ignition coils, most transmission issues, critical comms loss.
    let highSeverityPrefixes = ["P017", "P032", "P033", "P034", "P035", "P036", "P039"]
    let highSeverityCodes = ["U0121", "U0151"]
    if highSeverityCodes.contains(code) ||
       highSeverityPrefixes.contains(where: { code.hasPrefix($0) }) ||
       code.hasPrefix("P07") || code.hasPrefix("P08") {
        return .high
    }
    
    // Low Severity Issues: Mostly related to emissions.
    // Catalyst efficiency, EVAP system, secondary air injection.
    let lowSeverityPrefixes = ["P041", "P042", "P043", "P044", "P045", "P049"]
    if lowSeverityPrefixes.contains(where: { code.hasPrefix($0) }) {
        return .low
    }

    // Default to moderate for all other codes.
    return .moderate
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
