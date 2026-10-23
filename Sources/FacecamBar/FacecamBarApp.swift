import AppKit
import FacecamKit
import SwiftUI

@main
struct FacecamBarApp: App {
    @State private var model = CameraModel()

    init() {
        // Menu bar only, also when run unbundled via `swift run`.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(systemName: model.isConnected ? "web.camera.fill" : "web.camera")
        }
        .menuBarExtraStyle(.window)
    }
}

struct PanelView: View {
    @Bindable var model: CameraModel
    @State private var newProfileName = ""
    @State private var preview = CameraPreview()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.isConnected {
                CameraPreviewPanel(preview: preview)
                if model.controls.isEmpty {
                    Text("No controls could be read. Try the reconnect button.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // A ScrollView in a MenuBarExtra window has no intrinsic height; give it one explicitly.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(PanelSection.allCases, id: \.self) { section in
                                let controls = model.controls(in: section)
                                if !controls.isEmpty {
                                    SectionView(title: section.rawValue, controls: controls, model: model)
                                }
                            }
                        }
                        .padding(.trailing, 12)
                    }
                    .frame(height: 360)
                }
                Divider()
                profiles
                Divider()
                actions
            }
            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.deviceName ?? "No Elgato camera")
                    .font(.headline)
                if let firmware = model.firmware {
                    Text("Firmware \(firmware)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.connect()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reconnect and re-read the camera")
        }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles").font(.subheadline.weight(.semibold))
            HStack {
                Menu("Apply") {
                    ForEach(model.profiles, id: \.self) { name in
                        Button(name) { model.applyProfile(name) }
                    }
                }
                .disabled(model.profiles.isEmpty)
                Menu("Delete") {
                    ForEach(model.profiles, id: \.self) { name in
                        Button(name, role: .destructive) { model.deleteProfile(name) }
                    }
                }
                .disabled(model.profiles.isEmpty)
            }
            HStack {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveProfile)
                Button("Save", action: saveProfile)
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Picker("Apply on connect", selection: $model.autoApplyProfile) {
                Text("None").tag(String?.none)
                ForEach(model.profiles, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("Save to camera") { model.saveToCamera() }
                .help("Store the current settings in the camera so they apply in every app without Facecam running")
            Spacer()
            Button("Reset") { model.resetToDefaults() }
                .help("Restore the camera's default for every control")
        }
    }

    private func saveProfile() {
        model.saveProfile(newProfileName)
        newProfileName = ""
    }
}

struct SectionView: View {
    let title: String
    let controls: [ControlState]
    let model: CameraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(controls) { control in
                ControlRow(control: control, model: model)
                    .disabled(model.isLocked(control.id))
            }
        }
    }
}

struct ControlRow: View {
    let control: ControlState
    let model: CameraModel

    private var title: String {
        switch control.definition.name {
        case "hdr": "HDR"
        case "white-balance-auto": "Auto white balance"
        case "auto-exposure-mode": "Exposure mode"
        case "auto-exposure-priority": "Low-light frame rate drop"
        case "power-line-frequency": "Anti-flicker"
        case let name: name.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private var axisLabels: (String, String) {
        control.definition.name == "pan-tilt" ? ("Pan", "Tilt") : ("\(title) X", "\(title) Y")
    }

    var body: some View {
        let options = control.definition.options
        if options.count == 2, Set(options.map(\.name)) == ["off", "on"] {
            Toggle(title, isOn: Binding(
                get: { control.value == .integer(1) },
                set: { model.set(control.id, .integer($0 ? 1 : 0)) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        } else if !options.isEmpty {
            Picker(title, selection: Binding(
                get: { control.value },
                set: { model.set(control.id, $0) }
            )) {
                ForEach(options, id: \.value) { option in
                    Text(option.name.capitalized).tag(ControlValue.integer(option.value))
                }
            }
        } else if case .pair(let a, let b) = control.value,
                  case .pair(let minA, let minB)? = control.minimum,
                  case .pair(let maxA, let maxB)? = control.maximum {
            labeledSlider(axisLabels.0, a, minA, maxA) { model.set(control.id, .pair($0, b)) }
            labeledSlider(axisLabels.1, b, minB, maxB) { model.set(control.id, .pair(a, $0)) }
        } else if case .integer(let v) = control.value,
                  case .integer(let lo)? = control.minimum,
                  case .integer(let hi)? = control.maximum, hi > lo {
            labeledSlider(title, v, lo, hi) { model.set(control.id, .integer($0)) }
        }
    }

    private func labeledSlider(_ label: String, _ value: Int, _ lo: Int, _ hi: Int,
                               set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(
                value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }),
                in: Double(lo)...Double(hi)
            )
            .controlSize(.small)
        }
    }
}
