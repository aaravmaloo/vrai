import Foundation

public struct OID: Sendable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ string: String) {
        let lowered = string.lowercased()
        guard lowered.count == 40 || lowered.count == 64,
              lowered.allSatisfy({ $0.isHexDigit && $0.isASCII })
        else { return nil }
        rawValue = lowered
    }

    public var short: String { short(expert: false) }

    public func short(expert: Bool) -> String {
        String(rawValue.prefix(expert ? 10 : 7))
    }

    public var isZero: Bool { rawValue.allSatisfy { $0 == "0" } }

    public var description: String { rawValue }

    public static func < (lhs: OID, rhs: OID) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let oid = OID(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an object id: \(string)")
        }
        self = oid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
