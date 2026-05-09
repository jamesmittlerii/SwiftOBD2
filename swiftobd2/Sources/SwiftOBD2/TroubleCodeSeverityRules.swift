import Foundation

internal enum TroubleCodeSeverityLevel {
    case low
    case moderate
    case high
    case critical
}

internal func troubleCodeSeverityLevel(for code: String) -> TroubleCodeSeverityLevel {
    let criticalCodes = ["P0087", "P0088", "P0217", "P0218", "P0219", "P0234", "P0606"]
    if criticalCodes.contains(code) || code.hasPrefix("P030") || code.hasPrefix("P031") {
        return .critical
    }

    let highSeverityPrefixes = ["P017", "P032", "P033", "P034", "P035", "P036", "P039"]
    let highSeverityCodes = ["U0121", "U0151"]
    if highSeverityCodes.contains(code) ||
        highSeverityPrefixes.contains(where: { code.hasPrefix($0) }) ||
        code.hasPrefix("P07") || code.hasPrefix("P08") {
        return .high
    }

    let lowSeverityPrefixes = ["P041", "P042", "P043", "P044", "P045", "P049"]
    if lowSeverityPrefixes.contains(where: { code.hasPrefix($0) }) {
        return .low
    }

    return .moderate
}
