import ArgumentParser
import FacecamKit
import Foundation

@main
struct FacecamCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "facecam",
        abstract: "Control Elgato Facecam cameras over UVC.",
        subcommands: [List.self, Info.self, Get.self, SetCommand.self, Save.self, Reset.self, Profile.self]
    )
}

func padded(_ name: String) -> String {
    name.padding(toLength: 24, withPad: " ", startingAt: 0)
}

func control(named name: String) throws -> ControlDefinition {
    guard let control = Controls.named(name) else { throw ValidationError("unknown control \(name)") }
    return control
}

func printFailures(_ failures: [(String, Error)]) {
    for (name, error) in failures {
        print("\(padded(name)) error: \(error)")
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List connected Elgato cameras.")

    func run() throws {
        let devices = try IOKitTransport.list()
        if devices.isEmpty { throw FacecamError.deviceNotFound }
        for d in devices {
            print(String(format: "%@  pid=0x%04x  serial=%@", d.name, d.productID, d.serial))
        }
    }
}

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show UVC units, extension units and firmware.")

    func run() throws {
        let (device, cam) = try Facecam.openFirst()
        let t = cam.topology
        print(String(format: "%@ (pid 0x%04x, serial %@)", device.name, device.productID, device.serial))
        print("VideoControl interface: \(t.interfaceNumber)")
        if let ct = t.cameraTerminal { print("Camera terminal: unit \(ct.id)") }
        if let pu = t.processingUnit { print("Processing unit: unit \(pu.id)") }
        for xu in t.extensionUnits {
            let label = switch xu.guid {
            case ElgatoXU.image: " (Elgato image)"
            case ElgatoXU.device: " (Elgato device)"
            default: ""
            }
            print("Extension unit \(xu.id): \(xu.guid)\(label)")
        }
        if let features = try? cam.features() {
            print("Firmware: \(features.firmwareVersion ?? "?")  IQ: \(features.iqVersion ?? "?")")
        }
    }
}

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read controls (all supported controls by default).")

    @Argument(help: "Control names; run without arguments to list them.")
    var names: [String] = []

    func run() throws {
        let (_, cam) = try Facecam.openFirst()
        let controls = try names.isEmpty ? cam.supportedControls.filter(\.readable) : names.map(control(named:))
        for control in controls {
            let flag = control.writable ? "rw" : "r "
            do {
                let r = try cam.reading(control)
                var line = "\(flag) \(padded(control.name)) \(control.label(for: r.current))"
                if !control.options.isEmpty {
                    line += "  (\(control.options.map(\.name).joined(separator: "|")))"
                } else if let min = r.minimum, let max = r.maximum {
                    line += "  [\(min)…\(max)"
                    if let def = r.defaultValue { line += ", default \(def)" }
                    line += "]"
                }
                print(line)
            } catch {
                print("\(flag) \(padded(control.name)) error: \(error)")
            }
        }
    }
}

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Write one or more controls.",
        discussion: "Example: facecam set hdr=on noise-reduction=low brightness=4 framing=0,0"
    )

    @Argument(help: "name=value pairs. Values are integers, option names, or `a,b` for pairs.")
    var assignments: [String]

    func run() throws {
        var values: [String: ControlValue] = [:]
        for assignment in assignments {
            let parts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { throw ValidationError("expected name=value, got \(assignment)") }
            let control = try control(named: parts[0])
            guard control.writable else { throw FacecamError.readOnly(control.name) }
            guard let value = control.parse(parts[1]) else {
                throw ValidationError("invalid value \(parts[1]) for \(control.name)")
            }
            values[control.name] = value
        }

        let (_, cam) = try Facecam.openFirst()
        for (name, value) in values {
            let control = try control(named: name)
            try cam.write(control, value)
            // Elgato XU controls report 0xff for ~600 ms after SET_CUR while the change is applied.
            var current = try cam.read(control)
            for _ in 0..<15 where current != value {
                Thread.sleep(forTimeInterval: 0.1)
                current = try cam.read(control)
            }
            print("\(padded(name)) \(control.label(for: current))")
        }
    }
}

struct Save: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Store the current settings in the camera's flash as its power-on defaults."
    )

    func run() throws {
        let (_, cam) = try Facecam.openFirst()
        try cam.saveToCamera()
        print("Saved current settings to the camera.")
    }
}

struct Reset: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Restore every control to the camera's reported default.")

    func run() throws {
        let (_, cam) = try Facecam.openFirst()
        printFailures(cam.apply(cam.defaults()))
        print("Restored defaults. Run `facecam save` to make them the power-on settings.")
    }
}

struct Profile: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage named setting snapshots.",
        subcommands: [ProfileList.self, ProfileSave.self, ProfileApply.self, ProfileDelete.self]
    )
}

struct ProfileList: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List profiles.")

    func run() {
        let store = ProfileStore.standard
        for name in store.list() { print(name) }
    }
}

struct ProfileSave: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "save", abstract: "Save the camera's current settings as a profile.")

    @Argument var name: String

    func run() throws {
        let (_, cam) = try Facecam.openFirst()
        try ProfileStore.standard.save(name, values: cam.snapshot())
        print("Saved profile \(name).")
    }
}

struct ProfileApply: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "apply", abstract: "Apply a profile to the camera.")

    @Argument var name: String

    func run() throws {
        let values = try ProfileStore.standard.load(name)
        let (_, cam) = try Facecam.openFirst()
        printFailures(cam.apply(values))
        print("Applied profile \(name).")
    }
}

struct ProfileDelete: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a profile.")

    @Argument var name: String

    func run() throws {
        try ProfileStore.standard.delete(name)
        print("Deleted profile \(name).")
    }
}
