import CFacecamUSB
import Foundation

public enum FacecamError: Error, CustomStringConvertible {
    case usb(operation: String, code: Int32)
    case noVideoControlInterface
    case deviceNotFound
    case unsupported(String)
    case readOnly(String)

    public var description: String {
        switch self {
        case .usb(let operation, let code):
            String(format: "%@ failed: %@ (0x%08x)", operation, String(cString: fc_error_string(code)), UInt32(bitPattern: code))
        case .noVideoControlInterface: "device has no UVC VideoControl interface"
        case .deviceNotFound: "no Elgato camera found"
        case .unsupported(let name): "\(name) is not supported by this camera"
        case .readOnly(let name): "\(name) is read-only"
        }
    }
}

public protocol ControlTransport: AnyObject {
    var configurationDescriptor: [UInt8] { get }
    /// Performs a control request; returns bytes transferred. `data` is filled for IN requests.
    func control(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: inout [UInt8]) throws -> Int
}

public struct DeviceInfo: Sendable {
    public let registryID: UInt64
    public let vendorID: UInt16
    public let productID: UInt16
    public let name: String
    public let serial: String
}

public final class IOKitTransport: ControlTransport {
    public static let elgatoVendorID: UInt16 = 0x0FD9

    private let handle: OpaquePointer
    public let configurationDescriptor: [UInt8]

    public static func list(vendorID: UInt16 = elgatoVendorID) throws -> [DeviceInfo] {
        var infos = [fc_device_info](repeating: fc_device_info(), count: 16)
        let count = fc_list(vendorID, &infos, Int32(infos.count))
        guard count >= 0 else { throw FacecamError.usb(operation: "list", code: count) }
        return infos.prefix(Int(count)).map { info in
            var info = info
            return DeviceInfo(
                registryID: info.registry_id,
                vendorID: info.vendor_id,
                productID: info.product_id,
                name: withUnsafeBytes(of: &info.name) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) },
                serial: withUnsafeBytes(of: &info.serial) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            )
        }
    }

    public init(registryID: UInt64) throws {
        var handle: OpaquePointer?
        let kr = fc_open(registryID, &handle)
        guard kr == 0, let handle else { throw FacecamError.usb(operation: "open", code: kr) }
        self.handle = handle
        var length = 0
        let pointer = fc_config_descriptor(handle, &length)!
        configurationDescriptor = Array(UnsafeBufferPointer(start: pointer, count: length))
    }

    deinit { fc_close(handle) }

    public func control(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: inout [UInt8]) throws -> Int {
        var transferred: UInt32 = 0
        let kr = data.withUnsafeMutableBytes { buffer in
            fc_control(handle, requestType, request, value, index, buffer.baseAddress, UInt16(buffer.count), &transferred)
        }
        guard kr == 0 else {
            throw FacecamError.usb(operation: String(format: "request 0x%02x sel 0x%02x unit %d", request, value >> 8, index >> 8), code: kr)
        }
        return Int(transferred)
    }
}

public struct ControlReading: Sendable {
    public let definition: ControlDefinition
    public let current: ControlValue
    public let minimum: ControlValue?
    public let maximum: ControlValue?
    public let defaultValue: ControlValue?
}

public final class Facecam {
    public let transport: ControlTransport
    public let topology: VideoControlTopology

    public init(transport: ControlTransport) throws {
        self.transport = transport
        topology = try VideoControlTopology(configurationDescriptor: transport.configurationDescriptor)
    }

    public static func openFirst() throws -> (DeviceInfo, Facecam) {
        guard let info = try IOKitTransport.list().first else { throw FacecamError.deviceNotFound }
        return (info, try Facecam(transport: IOKitTransport(registryID: info.registryID)))
    }

    public func unitID(_ unit: UnitRef) -> UInt8? {
        switch unit {
        case .cameraTerminal: topology.cameraTerminal?.id
        case .processingUnit: topology.processingUnit?.id
        case .extensionUnit(let guid): topology.extensionUnit(guid)?.id
        }
    }

    public func isSupported(_ control: ControlDefinition) -> Bool {
        let bitmap: [UInt8]? = switch control.unit {
        case .cameraTerminal: topology.cameraTerminal?.bmControls
        case .processingUnit: topology.processingUnit?.bmControls
        case .extensionUnit(let guid): topology.extensionUnit(guid)?.bmControls
        }
        guard let bitmap else { return false }
        return bitIsSet(bitmap, control.supportBit)
    }

    public var supportedControls: [ControlDefinition] {
        Controls.all.filter(isSupported)
    }

    private func address(_ control: ControlDefinition) throws -> (value: UInt16, index: UInt16) {
        guard isSupported(control), let unit = unitID(control.unit) else {
            throw FacecamError.unsupported(control.name)
        }
        return (UInt16(control.selector) << 8, UInt16(unit) << 8 | UInt16(topology.interfaceNumber))
    }

    public func raw(_ request: UVCRequest, _ control: ControlDefinition, length: Int) throws -> [UInt8] {
        let (value, index) = try address(control)
        var data = [UInt8](repeating: 0, count: length)
        let count = try transport.control(requestType: request.requestType, request: request.rawValue,
                                          value: value, index: index, data: &data)
        return Array(data.prefix(count))
    }

    public func length(of control: ControlDefinition) throws -> Int {
        if let fixed = control.fixedLength { return fixed }
        return Int(try raw(.getLen, control, length: 2).littleEndianUInt)
    }

    public func read(_ control: ControlDefinition, request: UVCRequest = .getCur) throws -> ControlValue {
        let length = try length(of: control)
        return ControlValue(decoding: try raw(request, control, length: length), as: control.kind)
    }

    public func reading(_ control: ControlDefinition) throws -> ControlReading {
        let length = try length(of: control)
        func get(_ request: UVCRequest) -> ControlValue? {
            guard control.kind != .bytes,
                  let data = try? raw(request, control, length: length) else { return nil }
            return ControlValue(decoding: data, as: control.kind)
        }
        return ControlReading(
            definition: control,
            current: ControlValue(decoding: try raw(.getCur, control, length: length), as: control.kind),
            minimum: get(.getMin),
            maximum: get(.getMax),
            defaultValue: get(.getDef)
        )
    }

    public func write(_ control: ControlDefinition, _ value: ControlValue) throws {
        guard control.writable else { throw FacecamError.readOnly(control.name) }
        let (wValue, wIndex) = try address(control)
        var data = value.encoded(length: try length(of: control))
        _ = try transport.control(requestType: UVCRequest.setCur.requestType, request: UVCRequest.setCur.rawValue,
                                  value: wValue, index: wIndex, data: &data)
    }

    public func features() throws -> Features {
        guard let control = Controls.named("features") else { throw FacecamError.unsupported("features") }
        return Features(try raw(.getCur, control, length: try length(of: control)))
    }
}

extension Facecam {
    /// Controls a profile or reset touches: readable, writable, scalar, in apply order.
    public var settableControls: [ControlDefinition] {
        let auto = ["auto-exposure-mode", "white-balance-auto", "focus-auto"]
        let supported = supportedControls
        // On the MK.2 the Elgato framing control mirrors standard pan-tilt (verified on firmware 2.0.350).
        let hasPanTilt = supported.contains { $0.name == "pan-tilt" }
        let candidates = supported.filter {
            $0.readable && $0.writable && $0.kind != .bytes && !(hasPanTilt && $0.name == "framing")
        }
        return candidates.filter { auto.contains($0.name) } + candidates.filter { !auto.contains($0.name) }
    }

    /// Manual values the camera rejects while the matching auto mode is on.
    public static func isLockedByAuto(_ name: String, values: [String: ControlValue]) -> Bool {
        switch name {
        case "exposure": values["auto-exposure-mode"].map { $0 != .integer(1) && $0 != .integer(4) } ?? false
        case "white-balance": values["white-balance-auto"] == .integer(1)
        case "focus": values["focus-auto"] == .integer(1)
        default: false
        }
    }

    /// Writes values in apply order, skipping manual values locked by an auto mode.
    /// Returns per-control failures instead of stopping at the first one.
    @discardableResult
    public func apply(_ values: [String: ControlValue]) -> [(String, Error)] {
        var failures: [(String, Error)] = []
        for control in settableControls {
            guard let value = values[control.name], !Self.isLockedByAuto(control.name, values: values) else { continue }
            do {
                try write(control, value)
            } catch {
                failures.append((control.name, error))
            }
        }
        return failures
    }

    public func snapshot() -> [String: ControlValue] {
        var values: [String: ControlValue] = [:]
        for control in settableControls {
            values[control.name] = try? read(control)
        }
        return values
    }

    public func defaults() -> [String: ControlValue] {
        var values: [String: ControlValue] = [:]
        for control in settableControls {
            values[control.name] = try? read(control, request: .getDef)
        }
        return values
    }

    /// Persists the current settings as the camera's power-on defaults.
    public func saveToCamera() throws {
        try write(Controls.save, .integer(1))
    }
}
