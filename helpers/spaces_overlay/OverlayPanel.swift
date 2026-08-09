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
    private var carouselAnchor: CGPoint?
    private var pendingClosedWindowIDs = Set<CGWindowID>()
    private var suppressNextCarouselExit = false
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

        spacesView.onHoverChanged = { [weak self] space, anchor in
            guard let self else { return }
            guard let space else {
                self.scheduleCarouselDismissal()
                return
            }
            self.cancelCarouselDismissal()
            if self.requestedCarouselSpace != space {
                self.hideCarousel()
                return
            }
            if let anchor {
                self.carouselAnchor = CGPoint(x: anchor.midX, y: anchor.minY)
                if self.carouselView.thumbnailCount > 0 {
                    self.resizeCarousel()
                }
            }
        }
        spacesView.onHoverReady = { [weak self] space, anchor in
            self?.showCarousel(
                for: space,
                anchor: CGPoint(x: anchor.midX, y: anchor.minY)
            )
        }
        spacesView.onSpaceClicked = { [weak self] space, anchor in
            guard let self, let anchor else { return }
            self.showCarousel(
                for: space,
                anchor: CGPoint(x: anchor.midX, y: anchor.minY)
            )
        }
        spacesView.onHoverEnded = { [weak self] in
            self?.scheduleCarouselDismissal()
        }
        spacesView.onLayoutChanged = { [weak self] in
            guard let self,
                  !WindowCarouselModel.shouldPreserveCarouselOnLayoutChange(
                      requestedSpace: self.requestedCarouselSpace
                  ) else { return }
            self.hideCarousel()
        }
        carouselView.onRegionChanged = { [weak self] isInside in
            guard let self else { return }
            if isInside {
                self.cancelCarouselDismissal()
            } else if self.suppressNextCarouselExit {
                self.suppressNextCarouselExit = false
                self.cancelCarouselDismissal()
            } else {
                self.scheduleCarouselDismissal()
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
        carouselView.onClose = { [weak self] windowID in
            self?.close(windowID: windowID)
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
        carouselAnchor = anchor
        carouselPanel.orderOut(nil)

        guard let snapshot,
              snapshot.visible,
              space > 0,
              space <= snapshot.windowIDs.count else {
            requestedCarouselSpace = nil
            carouselAnchor = nil
            carouselView.apply([])
            return
        }

        let windowIDs = snapshot.windowIDs[space - 1]
        guard !windowIDs.isEmpty else {
            requestedCarouselSpace = nil
            carouselAnchor = nil
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
        carouselAnchor = nil
        pendingClosedWindowIDs.removeAll()
        suppressNextCarouselExit = false
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

    private func close(windowID: CGWindowID) {
        guard let space = requestedCarouselSpace,
              let snapshot,
              space > 0,
              space <= snapshot.windowIDs.count,
              snapshot.windowIDs[space - 1].contains(windowID) else { return }

        pendingClosedWindowIDs.insert(windowID)
        runYabai(YabaiCommandModel.closeCommand(windowID: windowID)) { [weak self] succeeded in
            guard let self else { return }
            if succeeded {
                self.carouselView.remove(id: windowID)
                self.resizeCarousel()
            } else {
                self.pendingClosedWindowIDs.remove(windowID)
            }
        }
    }

    private func resizeCarousel() {
        guard let anchor = carouselAnchor else { return }
        let entryCount = carouselView.thumbnailCount
        guard entryCount > 0 else {
            hideCarousel()
            return
        }

        let screen = screen(containing: anchor)
        let panelSize = carouselPanelSize(entryCount: entryCount, on: screen)
        let panelFrame = carouselPanelFrame(size: panelSize,
                                            below: anchor,
                                            on: screen)
        suppressNextCarouselExit = true
        carouselPanel.setFrame(panelFrame, display: false)
        carouselView.frame = CGRect(origin: .zero, size: panelSize)
        carouselPanel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.suppressNextCarouselExit = false
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
        let previousWindowIDs = Set(previousSnapshot.windowIDs[space - 1])
        let nextWindowIDs = Set(nextSnapshot.windowIDs[space - 1])
        guard previousWindowIDs != nextWindowIDs else { return false }

        let removedWindowIDs = previousWindowIDs.subtracting(nextWindowIDs)
        let addedWindowIDs = nextWindowIDs.subtracting(previousWindowIDs)
        guard WindowCarouselModel.canReconcileWindowRemoval(
            addedWindowIDs: Array(addedWindowIDs),
            removedWindowIDs: Array(removedWindowIDs)
        ) else {
            return true
        }

        for windowID in removedWindowIDs {
            carouselView.remove(id: windowID)
            pendingClosedWindowIDs.remove(windowID)
        }
        resizeCarousel()
        return false
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
        let contentWidth = WindowCarouselModel.carouselWidth(entryCount: entryCount)
        let preferredMaximumWidth = WindowCarouselModel.carouselWidth(entryCount: 3)
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
