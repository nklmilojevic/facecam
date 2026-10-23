import Foundation

public enum UnitRef: Hashable, Sendable {
    case cameraTerminal
    case processingUnit
    case extensionUnit(UUID)
}

public enum ValueKind: Equatable, Sendable {
    case unsigned
    case signed
    /// Two little-endian Int32 values (pan, tilt).
    case pair32
    case bytes
}

public enum Access: Sendable {
    case read
    case readWrite
    case write
}

public struct ControlOption: Sendable, Equatable {
    public let name: String
    public let value: Int
}

public struct ControlDefinition: Sendable, Identifiable {
    public let name: String
    public let unit: UnitRef
    public let selector: UInt8
    public let kind: ValueKind
    public let access: Access
    public let summary: String
    /// Bit in the unit's bmControls that advertises the control. XU bits are selector - 1.
    public let supportBit: Int
    /// Fixed payload size from the UVC spec. Extension-unit sizes come from GET_LEN instead,
    /// which standard units are not required to implement.
    public let fixedLength: Int?
    /// Named values for enumerated controls.
    public let options: [ControlOption]

    public var id: String { name }
    public var readable: Bool { access != .write }
    public var writable: Bool { access != .read }

    init(_ name: String, _ unit: UnitRef, _ selector: UInt8, _ kind: ValueKind, _ access: Access,
         _ summary: String, bit: Int? = nil, length: Int? = nil, options: KeyValuePairs<String, Int> = [:]) {
        self.name = name
        self.unit = unit
        self.selector = selector
        self.kind = kind
        self.access = access
        self.summary = summary
        fixedLength = length
        self.options = options.map { ControlOption(name: $0.key, value: $0.value) }
        if let bit {
            supportBit = bit
        } else {
            supportBit = Int(selector) - 1
        }
    }
}

public enum ElgatoXU {
    /// Image pipeline extension unit (unit 7 on the MK.2).
    public static let image = UUID(uuidString: "23E49ED0-1178-4F31-AE52-D2FB8A8D3001")!
    /// Device extension unit (unit 8 on the MK.2).
    public static let device = UUID(uuidString: "2C49D16A-32B8-4485-3EA8-643A15236002")!
}

public enum Controls {
    private static let ct = UnitRef.cameraTerminal
    private static let pu = UnitRef.processingUnit
    private static let xu1 = UnitRef.extensionUnit(ElgatoXU.image)
    private static let xu2 = UnitRef.extensionUnit(ElgatoXU.device)

    public static let all: [ControlDefinition] = [
        .init("brightness", pu, 0x02, .signed, .readWrite, "Brightness", bit: 0, length: 2),
        .init("contrast", pu, 0x03, .unsigned, .readWrite, "Contrast", bit: 1, length: 2),
        .init("hue", pu, 0x06, .signed, .readWrite, "Hue", bit: 2, length: 2),
        .init("saturation", pu, 0x07, .unsigned, .readWrite, "Saturation", bit: 3, length: 2),
        .init("sharpness", pu, 0x08, .unsigned, .readWrite, "Sharpness", bit: 4, length: 2),
        .init("gamma", pu, 0x09, .unsigned, .readWrite, "Gamma", bit: 5, length: 2),
        .init("white-balance", pu, 0x0A, .unsigned, .readWrite, "White balance temperature (K)", bit: 6, length: 2),
        .init("backlight-compensation", pu, 0x01, .unsigned, .readWrite, "Backlight compensation", bit: 8, length: 2,
              options: ["off": 0, "on": 1]),
        .init("gain", pu, 0x04, .unsigned, .readWrite, "Gain", bit: 9, length: 2),
        .init("power-line-frequency", pu, 0x05, .unsigned, .readWrite, "Anti-flicker", bit: 10, length: 1,
              options: ["off": 0, "50hz": 1, "60hz": 2, "auto": 3]),
        .init("white-balance-auto", pu, 0x0B, .unsigned, .readWrite, "Auto white balance", bit: 12, length: 1,
              options: ["off": 0, "on": 1]),

        .init("auto-exposure-mode", ct, 0x02, .unsigned, .readWrite, "Auto exposure mode", bit: 1, length: 1,
              options: ["manual": 1, "auto": 2, "shutter-priority": 4, "aperture-priority": 8]),
        .init("auto-exposure-priority", ct, 0x03, .unsigned, .readWrite, "Allow frame rate to drop in low light", bit: 2, length: 1,
              options: ["off": 0, "on": 1]),
        .init("exposure", ct, 0x04, .unsigned, .readWrite, "Exposure time (100 µs units)", bit: 3, length: 4),
        .init("focus", ct, 0x06, .unsigned, .readWrite, "Focus (absolute)", bit: 5, length: 2),
        .init("zoom", ct, 0x0B, .unsigned, .readWrite, "Zoom (absolute)", bit: 9, length: 2),
        .init("pan-tilt", ct, 0x0D, .pair32, .readWrite, "Pan/tilt (absolute, arc-seconds)", bit: 11, length: 8),
        .init("focus-auto", ct, 0x08, .unsigned, .readWrite, "Autofocus", bit: 17, length: 1,
              options: ["off": 0, "on": 1]),

        .init("camera-status", xu1, 0x01, .bytes, .read, "Camera state"),
        .init("metering", xu1, 0x02, .unsigned, .readWrite, "Exposure metering",
              options: ["center-weighted": 0, "spot": 1, "average": 2]),
        .init("sensor-gain", xu1, 0x08, .unsigned, .read, "Current sensor gain"),
        // Reports a 0…0 range on MK.2 firmware 2.0.350; read-only until its semantics are known.
        .init("exposure-time-control", xu1, 0x0A, .unsigned, .read, "Exposure time absolute"),
        .init("exposure-time", xu1, 0x0B, .unsigned, .read, "Current exposure time"),
        .init("focus-value", xu1, 0x0D, .unsigned, .read, "Current focus value"),
        .init("vibrancy", xu1, 0x0E, .unsigned, .readWrite, "Vibrancy"),
        .init("white-balance-value", xu1, 0x11, .unsigned, .read, "Current white balance temperature"),
        .init("tint", xu1, 0x12, .signed, .readWrite, "Tint"),
        .init("hdr", xu1, 0x15, .unsigned, .readWrite, "HDR",
              options: ["off": 0, "on": 1]),
        .init("noise-reduction", xu1, 0x16, .unsigned, .readWrite, "Noise reduction",
              options: ["off": 0, "low": 1, "medium": 2, "high": 3]),
        .init("framing", xu1, 0x18, .pair32, .readWrite, "Digital pan/tilt framing"),

        .init("features", xu2, 0x01, .bytes, .read, "Feature block (firmware/IQ version)"),
        .init("video-modes", xu2, 0x02, .bytes, .read, "Video mode / codec table"),
        .init("noise-reduction-2d", xu2, 0x03, .unsigned, .readWrite, "2D noise reduction"),
        .init("led", xu2, 0x04, .bytes, .read, "Status LED settings"),
        .init("usb-transfer-mode", xu2, 0x0B, .unsigned, .readWrite, "USB transfer mode"),
        .init("noise-reduction-3d", xu2, 0x14, .unsigned, .readWrite, "3D noise reduction"),
        .init("binning", xu2, 0x1D, .bytes, .read, "Sensor binning mode"),
    ]

    public static func named(_ name: String) -> ControlDefinition? {
        all.first { $0.name == name }
    }

    /// Device XU profile save; writing slot 1 stores the current settings as power-on defaults.
    public static let save = ControlDefinition("save", xu2, 0x07, .unsigned, .write, "Store current settings in camera flash", length: 1)
}

extension ControlDefinition {
    /// Parses a CLI/profile value: an option name, an integer, or `a,b` for pairs.
    public func parse(_ text: String) -> ControlValue? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let option = options.first(where: { $0.name == text }) {
            return .integer(option.value)
        }
        let parts = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        switch (kind, parts.count) {
        case (.pair32, 2):
            guard let a = parts[0], let b = parts[1] else { return nil }
            return .pair(a, b)
        case (.unsigned, 1), (.signed, 1):
            return parts[0].map(ControlValue.integer)
        default:
            return nil
        }
    }

    public func label(for value: ControlValue) -> String {
        if case .integer(let v) = value, let option = options.first(where: { $0.value == v }) {
            return option.name
        }
        return value.description
    }
}

public enum ControlValue: Hashable, Sendable, CustomStringConvertible {
    case integer(Int)
    case pair(Int, Int)
    case bytes([UInt8])

    public init(decoding data: [UInt8], as kind: ValueKind) {
        switch kind {
        case .unsigned:
            self = .integer(Int(truncatingIfNeeded: data.littleEndianUInt))
        case .signed:
            self = .integer(data.littleEndianInt)
        case .pair32 where data.count >= 8:
            self = .pair(Array(data[0..<4]).littleEndianInt, Array(data[4..<8]).littleEndianInt)
        case .pair32, .bytes:
            self = .bytes(data)
        }
    }

    public func encoded(length: Int) -> [UInt8] {
        switch self {
        case .integer(let v):
            return (0..<length).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) }
        case .pair(let a, let b):
            let half = length / 2
            return ControlValue.integer(a).encoded(length: half) + ControlValue.integer(b).encoded(length: half)
        case .bytes(let b):
            return Array(b.prefix(length)) + Array(repeating: 0, count: max(0, length - b.count))
        }
    }

    public var description: String {
        switch self {
        case .integer(let v): "\(v)"
        case .pair(let a, let b): "\(a),\(b)"
        case .bytes(let b): b.map { String(format: "%02x", $0) }.joined()
        }
    }
}

extension Array where Element == UInt8 {
    var littleEndianUInt: UInt64 {
        prefix(8).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
    }

    var littleEndianInt: Int {
        guard !isEmpty else { return 0 }
        let bits = Swift.min(count, 8) * 8
        let raw = littleEndianUInt
        if bits == 64 { return Int(bitPattern: UInt(raw)) }
        let signBit = UInt64(1) << (bits - 1)
        return raw & signBit != 0 ? Int(Int64(bitPattern: raw | ~((signBit << 1) - 1))) : Int(raw)
    }
}
