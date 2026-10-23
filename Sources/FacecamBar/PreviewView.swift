import AVFoundation
import SwiftUI

/// Owns the capture session; all session work runs on a private serial queue.
final class CameraPreview: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "facecam.preview")
    private var configuredDeviceID: String?

    /// Elgato UVC devices report a model ID like "UVC Camera VendorID_4057 ProductID_147".
    private static func elgatoCamera() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        ).devices.first { $0.modelID.contains("VendorID_4057") }
    }

    func start(onDenied: @escaping @Sendable () -> Void) {
        log.notice("preview start, authorization \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
        AVCaptureDevice.requestAccess(for: .video) { [self] granted in
            log.notice("camera access granted: \(granted)")
            guard granted else { return onDenied() }
            queue.async { [self] in
                guard let device = Self.elgatoCamera() else {
                    log.error("no Elgato capture device found")
                    return
                }
                if configuredDeviceID != device.uniqueID {
                    session.beginConfiguration()
                    session.inputs.forEach(session.removeInput)
                    if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                        session.addInput(input)
                        configuredDeviceID = device.uniqueID
                    }
                    session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                log.notice("preview \(device.localizedName, privacy: .public) running: \(self.session.isRunning)")
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

/// Hosts the preview as a sublayer and keeps it sized to the view; a layer-hosting view with the
/// preview layer as its own backing layer can stay zero-sized inside a MenuBarExtra window.
final class PreviewNSView: NSView {
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.needsLayout = true
    }
}

struct CameraPreviewPanel: View {
    let preview: CameraPreview
    @State private var denied = false

    var body: some View {
        ZStack {
            Color.black
            if denied {
                Text("Camera access denied.\nAllow Facecam in System Settings → Privacy & Security → Camera.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                PreviewView(session: preview.session)
            }
        }
        .frame(width: 312, height: 175.5)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            preview.start { Task { @MainActor in denied = true } }
        }
        .onDisappear { preview.stop() }
    }
}
