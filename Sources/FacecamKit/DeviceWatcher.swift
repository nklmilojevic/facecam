import CFacecamUSB
import Foundation

/// Reports Elgato camera arrival/removal, including cameras already connected at start.
public final class DeviceWatcher {
    private final class Box {
        let handler: (Bool) -> Void
        init(_ handler: @escaping (Bool) -> Void) { self.handler = handler }
    }

    private var watcher: OpaquePointer?
    private let box: Box

    public init(vendorID: UInt16 = IOKitTransport.elgatoVendorID, queue: DispatchQueue = .main,
                handler: @escaping (_ arrived: Bool) -> Void) {
        box = Box(handler)
        watcher = fc_watch(vendorID, queue, { context, arrived in
            Unmanaged<Box>.fromOpaque(context!).takeUnretainedValue().handler(arrived != 0)
        }, Unmanaged.passUnretained(box).toOpaque())
    }

    deinit { fc_unwatch(watcher) }
}
