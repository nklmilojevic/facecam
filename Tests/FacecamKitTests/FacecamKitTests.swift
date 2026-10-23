import Foundation
import Testing
@testable import FacecamKit

/// VideoControl descriptors captured from a Facecam MK.2 (0fd9:0093, firmware 2.0.350).
let mk2Descriptors: [UInt8] = hex("""
    09040000010e010000
    0d24010001a50080c3c9010101
    092403040101000200
    1c2406026ad1492cb83285443ea8643a152362f2060106033f000000
    1c240606d09ee4237811314fae52d2fb8a8d3b4805010303ff6f0000
    1d240607d09ee4237811314fae52d2fb8a8d3001200103048326b30000
    1d2406086ad1492cb83285443ea8643a15236002200103046391010000
    1224020101020000000000000000030e0a04
    0b240503010000025b1700
    """)

func hex(_ s: String) -> [UInt8] {
    let digits = s.filter(\.isHexDigit)
    return stride(from: 0, to: digits.count, by: 2).map {
        let start = digits.index(digits.startIndex, offsetBy: $0)
        return UInt8(digits[start...digits.index(after: start)], radix: 16)!
    }
}

final class FakeTransport: ControlTransport {
    struct Request: Equatable {
        let requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: [UInt8]
    }

    let configurationDescriptor: [UInt8]
    var requests: [Request] = []
    var responses: [UInt8: [UInt8]] = [:]

    init(_ descriptor: [UInt8] = mk2Descriptors) {
        configurationDescriptor = descriptor
    }

    func control(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: inout [UInt8]) throws -> Int {
        requests.append(Request(requestType: requestType, request: request, value: value, index: index, data: data))
        guard let response = responses[request] else { return data.count }
        let n = min(response.count, data.count)
        data.replaceSubrange(0..<n, with: response.prefix(n))
        return n
    }
}

@Suite struct TopologyTests {
    @Test func parsesMK2Units() throws {
        let t = try VideoControlTopology(configurationDescriptor: mk2Descriptors)
        #expect(t.interfaceNumber == 0)
        #expect(t.cameraTerminal?.id == 1)
        #expect(t.cameraTerminal?.bmControls == [0x0E, 0x0A, 0x04])
        #expect(t.processingUnit?.id == 3)
        #expect(t.processingUnit?.bmControls == [0x5B, 0x17])
        #expect(t.extensionUnits.map(\.id) == [2, 6, 7, 8])
    }

    @Test func mapsElgatoGUIDsToUnits() throws {
        let t = try VideoControlTopology(configurationDescriptor: mk2Descriptors)
        #expect(t.extensionUnit(ElgatoXU.image)?.id == 7)
        #expect(t.extensionUnit(ElgatoXU.device)?.id == 8)
        #expect(t.extensionUnit(ElgatoXU.image)?.bmControls == [0x83, 0x26, 0xB3, 0x00])
    }

    @Test func rejectsDescriptorWithoutVideoControl() {
        #expect(throws: FacecamError.self) {
            try VideoControlTopology(configurationDescriptor: hex("09040000010e020000"))
        }
    }
}

@Suite struct SupportTests {
    @Test func mk2SupportMatchesAdvertisedSelectors() throws {
        let cam = try Facecam(transport: FakeTransport())
        let names = Set(cam.supportedControls.map(\.name))
        #expect(names.isSuperset(of: ["hdr", "tint", "vibrancy", "noise-reduction", "framing", "metering",
                                      "features", "video-modes", "brightness", "zoom", "pan-tilt"]))
        #expect(names.isDisjoint(with: ["led", "binning", "noise-reduction-2d", "focus-value", "focus"]))
    }
}

@Suite struct RequestTests {
    @Test func readSendsGetLenThenGetCur() throws {
        let transport = FakeTransport()
        transport.responses = [UVCRequest.getLen.rawValue: [1, 0], UVCRequest.getCur.rawValue: [1]]
        let cam = try Facecam(transport: transport)

        let value = try cam.read(Controls.named("hdr")!)

        #expect(value == .integer(1))
        #expect(transport.requests.map(\.request) == [0x85, 0x81])
        #expect(transport.requests.allSatisfy { $0.requestType == 0xA1 && $0.value == 0x1500 && $0.index == 0x0700 })
    }

    @Test func writeEncodesSignedLittleEndian() throws {
        let transport = FakeTransport()
        transport.responses = [UVCRequest.getLen.rawValue: [2, 0]]
        let cam = try Facecam(transport: transport)

        try cam.write(Controls.named("tint")!, .integer(-2))

        let set = try #require(transport.requests.last)
        #expect(set == .init(requestType: 0x21, request: 0x01, value: 0x1200, index: 0x0700, data: [0xFE, 0xFF]))
    }

    @Test func standardControlsTargetProcessingUnit() throws {
        let transport = FakeTransport()
        transport.responses = [UVCRequest.getLen.rawValue: [2, 0]]
        let cam = try Facecam(transport: transport)

        try cam.write(Controls.named("brightness")!, .integer(10))

        #expect(transport.requests.last?.value == 0x0200)
        #expect(transport.requests.last?.index == 0x0300)
    }

    @Test func refusesReadOnlyAndUnsupported() throws {
        let cam = try Facecam(transport: FakeTransport())
        #expect(throws: FacecamError.self) { try cam.write(Controls.named("sensor-gain")!, .integer(1)) }
        #expect(throws: FacecamError.self) { try cam.read(Controls.named("led")!) }
    }
}

@Suite struct ValueTests {
    @Test func decodesSignedAndPairs() {
        #expect(ControlValue(decoding: [0xFE, 0xFF], as: .signed) == .integer(-2))
        #expect(ControlValue(decoding: [0xFE, 0xFF], as: .unsigned) == .integer(65534))
        #expect(ControlValue(decoding: [0x10, 0, 0, 0, 0xF0, 0xFF, 0xFF, 0xFF], as: .pair32) == .pair(16, -16))
    }

    @Test func encodesPairs() {
        #expect(ControlValue.pair(16, -16).encoded(length: 8) == [0x10, 0, 0, 0, 0xF0, 0xFF, 0xFF, 0xFF])
    }
}

@Suite struct FeaturesTests {
    @Test func decodesFirmwareAndIQVersions() {
        var raw = [UInt8](repeating: 0, count: 100)
        raw[0] = 2
        raw[1] = 0
        raw[2] = 0x5E // 350
        raw[3] = 0x01
        let iq: UInt32 = 1_000_024
        withUnsafeBytes(of: iq.littleEndian) { raw.replaceSubrange(0x16..<0x1A, with: $0) }

        let f = Features(raw)

        #expect(f.firmwareVersion == "2.0.350")
        #expect(f.iqVersion == "1.00.00.24")
    }
}

@Suite struct OptionTests {
    @Test func parsesNamesNumbersAndPairs() {
        #expect(Controls.named("metering")?.parse("spot") == .integer(1))
        #expect(Controls.named("noise-reduction")?.parse("HIGH") == .integer(3))
        #expect(Controls.named("hdr")?.parse("on") == .integer(1))
        #expect(Controls.named("tint")?.parse("-12") == .integer(-12))
        #expect(Controls.named("framing")?.parse("100, -50") == .pair(100, -50))
        #expect(Controls.named("metering")?.parse("bogus") == nil)
    }

    @Test func labelsKnownValues() {
        #expect(Controls.named("metering")?.label(for: .integer(2)) == "average")
        #expect(Controls.named("metering")?.label(for: .integer(9)) == "9")
    }
}

@Suite struct SaveAndApplyTests {
    @Test func saveWritesSlotOneToDeviceUnit() throws {
        let transport = FakeTransport()
        let cam = try Facecam(transport: transport)

        try cam.saveToCamera()

        #expect(transport.requests == [.init(requestType: 0x21, request: 0x01, value: 0x0700, index: 0x0800, data: [1])])
    }

    @Test func applyWritesAutoModesFirstAndSkipsLockedManualValues() throws {
        let transport = FakeTransport()
        transport.responses = [UVCRequest.getLen.rawValue: [1, 0]]
        let cam = try Facecam(transport: transport)

        let failures = cam.apply([
            "exposure": .integer(200),
            "auto-exposure-mode": .integer(2),
            "white-balance": .integer(4000),
            "white-balance-auto": .integer(0),
        ])

        #expect(failures.isEmpty)
        let sets = transport.requests.filter { $0.request == 0x01 }.map { ($0.index >> 8, $0.value >> 8) }
        // Auto modes (PU 0x0B white-balance-auto, CT 0x02 auto-exposure-mode) before manual white-balance (PU 0x0A);
        // manual exposure (CT 0x04) skipped because auto exposure is on.
        #expect(sets.count == 3)
        #expect(Set(sets.prefix(2).map { "\($0.0):\($0.1)" }) == ["3:11", "1:2"])
        #expect(sets.last.map { "\($0.0):\($0.1)" } == "3:10")
    }

    @Test func settableControlsExcludeReadOnlyAndBlobs() throws {
        let cam = try Facecam(transport: FakeTransport())
        let names = cam.settableControls.map(\.name)
        #expect(!names.contains("features"))
        #expect(!names.contains("exposure-time-control"))
        #expect(!names.contains("sensor-gain"))
        #expect(names.contains("pan-tilt"))
        #expect(!names.contains("framing"))
        let autos: Set = ["auto-exposure-mode", "white-balance-auto"]
        #expect(Set(names.prefix(2)) == autos)
    }
}

@Suite struct ProfileTests {
    @Test func roundTripsReadableJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        let values: [String: ControlValue] = ["metering": .integer(1), "framing": .pair(10, -20), "brightness": .integer(-3)]

        try store.save("calls", values: values)

        #expect(store.list() == ["calls"])
        #expect(try store.load("calls") == values)
        let json = try String(contentsOf: dir.appending(path: "calls.json"), encoding: .utf8)
        #expect(json.contains(#""metering" : "spot""#))
        try store.delete("calls")
        #expect(store.list().isEmpty)
    }

    @Test func rejectsInvalidEntries() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"metering": "sideways"}"#.write(to: dir.appending(path: "bad.json"), atomically: true, encoding: .utf8)

        #expect(throws: ProfileError.self) { try ProfileStore(directory: dir).load("bad") }
    }
}
