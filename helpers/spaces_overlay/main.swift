import AppKit
import Foundation

private let serviceName = "com.vision3.sketchybar.spaces"
private var overlayController: SpacesOverlayController?

@_cdecl("spaces_overlay_receive")
func spacesOverlayReceive(_ payload: UnsafeRawPointer?, _ length: Int) {
    guard let payload, length > 0 else { return }
    let data = Data(bytes: payload, count: length)
    let environment = MachEnvironment.parse(data)
    guard let snapshot = OverlaySnapshot(environment: environment) else { return }

    DispatchQueue.main.async {
        overlayController?.apply(snapshot)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
overlayController = SpacesOverlayController()

DispatchQueue.global(qos: .userInitiated).async {
    let result = spaces_mach_service_run(serviceName)
    if result != 0 {
        fputs("spaces_overlay: Mach service failed with status \(result)\n", stderr)
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}

application.run()
