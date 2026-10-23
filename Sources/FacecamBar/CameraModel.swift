import FacecamKit
import Foundation
import Observation
import os

let log = Logger(subsystem: "io.github.facecam.FacecamBar", category: "app")

struct ControlState: Identifiable {
    let definition: ControlDefinition
    var value: ControlValue
    let minimum: ControlValue?
    let maximum: ControlValue?
    let defaultValue: ControlValue?

    var id: String { definition.name }
}

enum PanelSection: String, CaseIterable {
    case image = "Image"
    case exposure = "Exposure"
    case whiteBalance = "White balance"
    case framing = "Framing"

    static func of(_ name: String) -> PanelSection? {
        switch name {
        case "brightness", "contrast", "saturation", "sharpness", "hue", "gamma", "vibrancy", "hdr",
             "noise-reduction", "noise-reduction-2d", "noise-reduction-3d", "backlight-compensation":
            .image
        case "auto-exposure-mode", "exposure", "auto-exposure-priority", "metering", "gain", "power-line-frequency":
            .exposure
        case "white-balance-auto", "white-balance", "tint":
            .whiteBalance
        case "zoom", "pan-tilt", "framing", "focus-auto", "focus":
            .framing
        default:
            nil
        }
    }
}

@MainActor
@Observable
final class CameraModel {
    private(set) var deviceName: String?
    private(set) var firmware: String?
    private(set) var controls: [ControlState] = []
    private(set) var profiles: [String] = []
    var status: String?

    var autoApplyProfile: String? {
        didSet { UserDefaults.standard.set(autoApplyProfile, forKey: "autoApplyProfile") }
    }

    private var camera: Facecam?
    private var watcher: DeviceWatcher?
    private var pendingWrites: [String: Task<Void, Never>] = [:]
    private let store = ProfileStore.standard

    init() {
        autoApplyProfile = UserDefaults.standard.string(forKey: "autoApplyProfile")
        profiles = store.list()
        watcher = DeviceWatcher { [weak self] arrived in
            MainActor.assumeIsolated { self?.deviceChanged(arrived: arrived) }
        }
    }

    var isConnected: Bool { camera != nil }

    func controls(in section: PanelSection) -> [ControlState] {
        controls.filter { PanelSection.of($0.id) == section }
    }

    private func deviceChanged(arrived: Bool) {
        guard arrived else {
            camera = nil
            deviceName = nil
            firmware = nil
            controls = []
            return
        }
        // Give the camera a moment to finish enumerating before talking to it.
        Task {
            try? await Task.sleep(for: .seconds(1))
            connect(applyingAutoProfile: true)
        }
    }

    func connect(applyingAutoProfile: Bool = false) {
        do {
            let (info, cam) = try Facecam.openFirst()
            log.notice("connected to \(info.name, privacy: .public)")
            camera = cam
            deviceName = info.name
            firmware = (try? cam.features())?.firmwareVersion
            if applyingAutoProfile, let name = autoApplyProfile {
                applyProfile(name)
            } else {
                refresh()
            }
        } catch {
            camera = nil
            controls = []
            status = "\(error)"
            log.error("connect failed: \(String(describing: error), privacy: .public)")
        }
    }

    func refresh() {
        guard let camera else { return }
        controls = camera.settableControls.compactMap { definition in
            guard let reading = try? camera.reading(definition) else { return nil }
            return ControlState(definition: definition, value: reading.current, minimum: reading.minimum,
                                maximum: reading.maximum, defaultValue: reading.defaultValue)
        }
        log.notice("read \(self.controls.count) of \(camera.settableControls.count) controls")
    }

    func value(_ name: String) -> ControlValue? {
        controls.first { $0.id == name }?.value
    }

    /// Manual controls are disabled while their auto mode is on, mirroring what the camera accepts.
    func isLocked(_ name: String) -> Bool {
        var values: [String: ControlValue] = [:]
        for control in controls { values[control.id] = control.value }
        return Facecam.isLockedByAuto(name, values: values)
    }

    func set(_ name: String, _ value: ControlValue) {
        guard let index = controls.firstIndex(where: { $0.id == name }), controls[index].value != value else { return }
        controls[index].value = value
        let definition = controls[index].definition
        pendingWrites[name]?.cancel()
        pendingWrites[name] = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            do {
                try camera?.write(definition, value)
            } catch {
                status = "\(name): \(error)"
            }
        }
    }

    func resetToDefaults() {
        guard let camera else { return }
        report(camera.apply(camera.defaults()), success: "Restored defaults")
        refresh()
    }

    func saveToCamera() {
        do {
            try camera?.saveToCamera()
            status = "Saved to camera"
        } catch {
            status = "Save failed: \(error)"
        }
    }

    func applyProfile(_ name: String) {
        guard let camera else { return }
        do {
            report(camera.apply(try store.load(name)), success: "Applied \(name)")
        } catch {
            status = "\(error)"
        }
        refresh()
    }

    func saveProfile(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let camera, !name.isEmpty else { return }
        do {
            try store.save(name, values: camera.snapshot())
            profiles = store.list()
            status = "Saved profile \(name)"
        } catch {
            status = "\(error)"
        }
    }

    func deleteProfile(_ name: String) {
        try? store.delete(name)
        profiles = store.list()
        if autoApplyProfile == name { autoApplyProfile = nil }
    }

    private func report(_ failures: [(String, Error)], success: String) {
        status = failures.isEmpty ? success : failures.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }
}
