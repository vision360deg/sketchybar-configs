import AppKit
import CoreGraphics

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SpacesOverlayController {
    private let yabaiExecutable = "/opt/homebrew/bin/yabai"
    private let panel: NonActivatingPanel
    private let spacesView: SpacesView
    private let carouselPanel: NonActivatingPanel
    private let carouselView: WindowCarouselView
    private var snapshot: OverlaySnapshot?
    private var carouselRequestGeneration: UInt64 = 0
    private var requestedCarouselSpace: Int?
    private var dismissalGeneration = HoverDismissalGeneration()

    init() {
        spacesView = SpacesView(frame: .zero)
        carouselView = WindowCarouselView(frame: .zero)
        panel = NonActivatingPanel(contentRect: .zero,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        carouselPanel = NonActivatingPanel(contentRect: .zero,
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

        carouselPanel.contentView = carouselView
        carouselPanel.backgroundColor = .clear
        carouselPanel.isOpaque = false
        carouselPanel.hasShadow = false
        carouselPanel.hidesOnDeactivate = false
        carouselPanel.isReleasedWhenClosed = false
        carouselPanel.ignoresMouseEvents = false
        carouselPanel.level = OverlayWindowPolicy.level
        carouselPanel.collectionBehavior = OverlayWindowPolicy.collectionBehavior
        carouselPanel.orderOut(nil)

        spacesView.onHoverChanged = { [weak self] space, _ in
            guard let self else { return }
            guard let space else {
                self.scheduleCarouselDismissal()
                return
            }
            self.cancelCarouselDismissal()
            if self.requestedCarouselSpace != space {
                self.hideCarousel()
            }
        }
        spacesView.onHoverReady = { [weak self] space, anchor in
            self?.showCarousel(
                for: space,
                anchor: CGPoint(x: anchor.midX, y: anchor.minY)
            )
        }
        spacesView.onHoverEnded = { [weak self] in
            self?.scheduleCarouselDismissal()
        }
        spacesView.onLayoutChanged = { [weak self] in
            self?.hideCarousel()
        }
        carouselView.onRegionChanged = { [weak self] isInside in
            if isInside {
                self?.cancelCarouselDismissal()
            } else {
                self?.scheduleCarouselDismissal()
            }
        }
        carouselView.onSelect = { [weak self] windowID in
            guard let self else { return }
            guard let space = self.requestedCarouselSpace,
                  let snapshot = self.snapshot,
                  space > 0,
                  space <= snapshot.windowIDs.count,
                  snapshot.windowIDs[space - 1].contains(windowID) else {
                self.hideCarousel()
                return
            }
            let generation = self.carouselRequestGeneration
            self.focus(space: space,
                       windowID: windowID,
                       selectedSpace: snapshot.selected) { [weak self] _ in
                guard let self,
                      self.carouselRequestGeneration == generation else { return }
                self.hideCarousel()
            }
        }
    }

    func apply(_ snapshot: OverlaySnapshot) {
        let previousSnapshot = self.snapshot
        let shouldHideCarousel = !snapshot.visible
            || carouselWindowSetChanged(from: previousSnapshot, to: snapshot)
            || overlayMovedToDifferentDisplay(from: previousSnapshot, to: snapshot)
        let foregroundChanged = carouselForegroundChanged(from: previousSnapshot,
                                                          to: snapshot)
        self.snapshot = snapshot
        if shouldHideCarousel {
            hideCarousel()
        } else if foregroundChanged,
                  let space = requestedCarouselSpace,
                  space > 0,
                  space <= snapshot.foregroundWindowIDs.count {
            carouselView.setForegroundID(snapshot.foregroundWindowIDs[space - 1])
        }

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

    func showCarousel(for space: Int, anchor: CGPoint) {
        cancelCarouselDismissal()
        carouselRequestGeneration &+= 1
        let generation = carouselRequestGeneration
        requestedCarouselSpace = space
        carouselPanel.orderOut(nil)

        guard let snapshot,
              snapshot.visible,
              space > 0,
              space <= snapshot.windowIDs.count else {
            requestedCarouselSpace = nil
            carouselView.apply([])
            return
        }

        let windowIDs = snapshot.windowIDs[space - 1]
        guard !windowIDs.isEmpty else {
            requestedCarouselSpace = nil
            carouselView.apply([])
            return
        }

        WindowCapture.capture(ids: windowIDs) { [weak self] thumbnails in
            guard let self,
                  self.carouselRequestGeneration == generation,
                  self.requestedCarouselSpace == space,
                  let currentSnapshot = self.snapshot,
                  currentSnapshot.visible,
                  WindowCarouselModel.matchesWindowIDs(
                      windowIDs,
                      for: space,
                      in: currentSnapshot.windowIDs
                  ) else { return }

            guard !thumbnails.isEmpty else {
                self.hideCarousel()
                return
            }

            let currentForegroundID = space <= currentSnapshot.foregroundWindowIDs.count
                ? currentSnapshot.foregroundWindowIDs[space - 1]
                : nil
            let screen = self.screen(containing: anchor)
            let panelSize = self.carouselPanelSize(entryCount: thumbnails.count,
                                                   on: screen)
            let panelFrame = self.carouselPanelFrame(size: panelSize,
                                                     below: anchor,
                                                     on: screen)
            self.carouselPanel.setFrame(panelFrame, display: false)
            self.carouselView.frame = CGRect(origin: .zero, size: panelSize)
            self.carouselView.apply(thumbnails, foregroundID: currentForegroundID)
            self.carouselPanel.orderFrontRegardless()
        }
    }

    func hideCarousel() {
        cancelCarouselDismissal()
        carouselRequestGeneration &+= 1
        requestedCarouselSpace = nil
        carouselPanel.orderOut(nil)
        carouselView.apply([])
    }

    private func scheduleCarouselDismissal() {
        let generation = dismissalGeneration.schedule()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self,
                  self.dismissalGeneration.isCurrent(generation) else { return }
            self.hideCarousel()
        }
    }

    private func cancelCarouselDismissal() {
        dismissalGeneration.cancel()
    }

    private func focus(space: Int,
                       windowID: CGWindowID,
                       selectedSpace: Int,
                       completion: @escaping (Bool) -> Void) {
        let commands = YabaiCommandModel.focusCommands(
            space: space,
            windowID: windowID,
            selectedSpace: selectedSpace
        )
        guard let windowCommand = commands.last else {
            completion(false)
            return
        }

        if commands.count == 1 {
            runYabai(windowCommand, completion: completion)
            return
        }

        runYabai(commands[0]) { spaceOK in
            guard spaceOK else {
                completion(false)
                return
            }
            self.runYabai(windowCommand) { windowOK in
                completion(windowOK)
            }
        }
    }

    private func runYabai(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.yabaiExecutable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            environment["HOME"] = homeDirectory
            environment["XDG_CONFIG_HOME"] = environment["XDG_CONFIG_HOME"]
                ?? "\(homeDirectory)/.config"
            environment["USER"] = environment["USER"] ?? NSUserName()
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            let succeeded: Bool
            do {
                try process.run()
                process.waitUntilExit()
                succeeded = process.terminationStatus == 0
            } catch {
                succeeded = false
            }

            DispatchQueue.main.async {
                completion(succeeded)
            }
        }
    }

    private func carouselWindowSetChanged(from previousSnapshot: OverlaySnapshot?,
                                          to nextSnapshot: OverlaySnapshot) -> Bool {
        guard let previousSnapshot,
              previousSnapshot.revision != nextSnapshot.revision,
              let space = requestedCarouselSpace else { return false }
        guard space > 0,
              space <= previousSnapshot.windowIDs.count,
              space <= nextSnapshot.windowIDs.count else { return true }
        return Set(previousSnapshot.windowIDs[space - 1])
            != Set(nextSnapshot.windowIDs[space - 1])
    }

    private func carouselForegroundChanged(from previousSnapshot: OverlaySnapshot?,
                                           to nextSnapshot: OverlaySnapshot) -> Bool {
        guard let previousSnapshot,
              previousSnapshot.revision != nextSnapshot.revision,
              let space = requestedCarouselSpace,
              space > 0,
              space <= previousSnapshot.foregroundWindowIDs.count,
              space <= nextSnapshot.foregroundWindowIDs.count else { return false }
        return previousSnapshot.foregroundWindowIDs[space - 1]
            != nextSnapshot.foregroundWindowIDs[space - 1]
    }

    private func overlayMovedToDifferentDisplay(from previousSnapshot: OverlaySnapshot?,
                                                to nextSnapshot: OverlaySnapshot) -> Bool {
        guard let previousSnapshot,
              let previousDisplay = displayID(containing: previousSnapshot.frame),
              let nextDisplay = displayID(containing: nextSnapshot.frame) else { return false }
        return previousDisplay != nextDisplay
    }

    private func displayID(containing quartzFrame: CGRect) -> CGDirectDisplayID? {
        let center = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            if CGDisplayBounds(displayID).contains(center) {
                return displayID
            }
        }
        return nil
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

    private func screen(containing anchor: CGPoint) -> NSScreen {
        NSScreen.screens.first(where: { $0.frame.contains(anchor) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func carouselPanelSize(entryCount: Int, on screen: NSScreen) -> CGSize {
        let count = max(1, entryCount)
        let contentWidth = WindowCarouselModel.horizontalPadding * 2
            + CGFloat(count) * WindowCarouselModel.cardWidth
            + CGFloat(count - 1) * WindowCarouselModel.cardSpacing
        let maximumCardCount = 3
        let preferredMaximumWidth = WindowCarouselModel.horizontalPadding * 2
            + CGFloat(maximumCardCount) * WindowCarouselModel.cardWidth
            + CGFloat(maximumCardCount - 1) * WindowCarouselModel.cardSpacing
        let width = min(contentWidth,
                        preferredMaximumWidth,
                        screen.visibleFrame.width)
        let preferredHeight = WindowCarouselModel.cardHeight
            + WindowCarouselModel.horizontalPadding * 2
        let height = min(preferredHeight, screen.visibleFrame.height)
        return CGSize(width: width, height: height)
    }

    private func carouselPanelFrame(size: CGSize,
                                    below anchor: CGPoint,
                                    on screen: NSScreen) -> CGRect {
        let available = screen.visibleFrame
        let maximumX = max(available.minX, available.maxX - size.width)
        let maximumY = max(available.minY, available.maxY - size.height)
        let x = min(max(anchor.x - size.width / 2, available.minX), maximumX)
        let y = min(max(anchor.y - size.height, available.minY), maximumY)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
