import Foundation

public enum UVCRequest: UInt8, Sendable {
    case setCur = 0x01
    case getCur = 0x81
    case getMin = 0x82
    case getMax = 0x83
    case getRes = 0x84
    case getLen = 0x85
    case getInfo = 0x86
    case getDef = 0x87

    /// Class request to an interface/entity: host-to-device 0x21, device-to-host 0xA1.
    public var requestType: UInt8 { self == .setCur ? 0x21 : 0xA1 }
}

public struct ExtensionUnit: Equatable, Sendable {
    public let id: UInt8
    public let guid: UUID
    public let numControls: UInt8
    public let bmControls: [UInt8]
}

public struct VideoControlTopology: Equatable, Sendable {
    public var interfaceNumber: UInt8
    public var cameraTerminal: (id: UInt8, bmControls: [UInt8])?
    public var processingUnit: (id: UInt8, bmControls: [UInt8])?
    public var extensionUnits: [ExtensionUnit]

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.interfaceNumber == rhs.interfaceNumber
            && lhs.cameraTerminal?.id == rhs.cameraTerminal?.id
            && lhs.cameraTerminal?.bmControls == rhs.cameraTerminal?.bmControls
            && lhs.processingUnit?.id == rhs.processingUnit?.id
            && lhs.processingUnit?.bmControls == rhs.processingUnit?.bmControls
            && lhs.extensionUnits == rhs.extensionUnits
    }

    public func extensionUnit(_ guid: UUID) -> ExtensionUnit? {
        extensionUnits.first { $0.guid == guid }
    }

    /// Parses the UVC class-specific VideoControl descriptors out of a full configuration descriptor.
    public init(configurationDescriptor bytes: [UInt8]) throws {
        var interfaceNumber: UInt8?
        var inVideoControl = false
        var cameraTerminal: (UInt8, [UInt8])?
        var processingUnit: (UInt8, [UInt8])?
        var extensionUnits: [ExtensionUnit] = []

        var i = 0
        while i + 2 <= bytes.count {
            let length = Int(bytes[i])
            guard length >= 2, i + length <= bytes.count else { break }
            let d = Array(bytes[i..<(i + length)])
            i += length

            switch d[1] {
            case 0x04 where length >= 9:
                inVideoControl = d[5] == 0x0E && d[6] == 0x01
                if inVideoControl, interfaceNumber == nil { interfaceNumber = d[2] }
            case 0x24 where inVideoControl && length >= 3:
                switch d[2] {
                case 0x02 where length >= 15 && d[4] == 0x01 && d[5] == 0x02:
                    let size = Int(d[14])
                    cameraTerminal = (d[3], Array(d[15..<min(15 + size, length)]))
                case 0x05 where length >= 8:
                    let size = Int(d[7])
                    processingUnit = (d[3], Array(d[8..<min(8 + size, length)]))
                case 0x06 where length >= 24:
                    let pins = Int(d[21])
                    let sizeIndex = 22 + pins
                    guard sizeIndex < length else { continue }
                    let size = Int(d[sizeIndex])
                    let start = sizeIndex + 1
                    extensionUnits.append(ExtensionUnit(
                        id: d[3],
                        guid: UUID(uvcGUID: Array(d[4..<20])),
                        numControls: d[20],
                        bmControls: Array(d[start..<min(start + size, length)])
                    ))
                default:
                    break
                }
            default:
                break
            }
        }

        guard let interfaceNumber else { throw FacecamError.noVideoControlInterface }
        self.interfaceNumber = interfaceNumber
        self.cameraTerminal = cameraTerminal
        self.processingUnit = processingUnit
        self.extensionUnits = extensionUnits
    }
}

extension UUID {
    /// UVC stores GUIDs in Microsoft mixed-endian layout (first three fields little-endian).
    init(uvcGUID b: [UInt8]) {
        precondition(b.count == 16)
        self.init(uuid: (b[3], b[2], b[1], b[0], b[5], b[4], b[7], b[6],
                         b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

func bitIsSet(_ bitmap: [UInt8], _ bit: Int) -> Bool {
    let byte = bit / 8
    return byte < bitmap.count && bitmap[byte] & (1 << (bit % 8)) != 0
}
