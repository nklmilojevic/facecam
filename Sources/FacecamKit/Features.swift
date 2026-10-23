import Foundation

/// Decoded device extension unit FEATURES block (selector 0x01).
public struct Features: Equatable, Sendable {
    public let raw: [UInt8]

    public init(_ raw: [UInt8]) {
        self.raw = raw
    }

    /// Firmware version as (u8 major, u8 minor, u16 build) at offset 0, e.g. "2.0.350".
    public var firmwareVersion: String? {
        guard raw.count >= 4 else { return nil }
        let build = Array(raw[2..<4]).littleEndianUInt
        return "\(raw[0]).\(raw[1]).\(build)"
    }

    /// Image-quality tuning version: u32 at 0x16 rendered as base-100 digit groups, e.g. 1000024 -> "1.00.00.24".
    public var iqVersion: String? {
        guard raw.count >= 0x1A else { return nil }
        var value = Array(raw[0x16..<0x1A]).littleEndianUInt
        guard value > 0 else { return nil }
        var groups: [UInt64] = []
        repeat {
            groups.append(value % 100)
            value /= 100
        } while value > 0
        while groups.count < 4 { groups.append(0) }
        let ordered = groups.reversed()
        return ordered.enumerated().map { $0.offset == 0 ? "\($0.element)" : String(format: "%02d", $0.element) }
            .joined(separator: ".")
    }
}
