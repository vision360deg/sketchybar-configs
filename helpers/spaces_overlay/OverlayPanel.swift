import AppKit
import CoreGraphics

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SpacesOverlayController {
    private let panel: NonActivatingPanel
    private let spacesView: SpacesView

    init() {
        spacesView = SpacesView(frame: .zero)
        panel = NonActivatingPanel(contentRect: .zero,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        panel.contentView = spacesView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.level = OverlayWindowPolicy.level
        panel.collectionBehavior = OverlayWindowPolicy.collectionBehavior
    }

    func apply(_ snapshot: OverlaySnapshot) {
        let panelFrame = appKitFrame(for: snapshot.frame)
        panel.setFrame(panelFrame, display: false)
        spacesView.frame = CGRect(origin: .zero, size: panelFrame.size)
        spacesView.apply(snapshot)

        if snapshot.visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private func appKitFrame(for quartzFrame: CGRect) -> CGRect {
        let center = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)

        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }

            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard displayBounds.contains(center) else { continue }

            return CGRect(
                x: screen.frame.minX + quartzFrame.minX - displayBounds.minX,
                y: screen.frame.maxY - (quartzFrame.minY - displayBounds.minY) - quartzFrame.height,
                width: quartzFrame.width,
                height: quartzFrame.height
            )
        }

        guard let screen = NSScreen.main else { return quartzFrame }
        return CGRect(x: quartzFrame.minX,
                      y: screen.frame.maxY - quartzFrame.minY - quartzFrame.height,
                      width: quartzFrame.width,
                      height: quartzFrame.height)
    }
}
