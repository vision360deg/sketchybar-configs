import AppKit
import CoreGraphics
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SpacesOverlayController {
    private final class DisplayPanel {
        let panel: NonActivatingPanel
        let view: SpacesView
        let occlusionObserver: NSObjectProtocol

        init(panel: NonActivatingPanel,
             view: SpacesView,
             occlusionObserver: NSObjectProtocol) {
            self.panel = panel
            self.view = view
            self.occlusionObserver = occlusionObserver
        }

        deinit {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    private let yabaiExecutable = "/opt/homebrew/bin/yabai"
    private var displayPanels: [Int: DisplayPanel] = [:]
    private let carouselPanel: NonActivatingPanel
    private let carouselView: WindowCarouselView
    private var snapshot: OverlaySnapshot?
    private var carouselRequestGeneration: UInt64 = 0
    private var requestedCarouselSpace: Int?
    private var requestedCarouselDisplay: Int?
    private var carouselAnchor: CGPoint?
    private var pendingClosedWindowIDs = Set<CGWindowID>()
    private var suppressNextCarouselExit = false
    private var dismissalGeneration = HoverDismissalGeneration()

    init() {
        carouselView = WindowCarouselView(frame: .zero)
        carouselPanel = NonActivatingPanel(contentRect: .zero,
                                           styleMask: [.borderless, .nonactivatingPanel],
                                           backing: .buffered,
                                           defer: false)
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
                  let displayIndex = self.requestedCarouselDisplay,
                  let snapshot = self.snapshot,
                  let group = snapshot.group(forDisplay: displayIndex),
                  let position = group.position(of: space),
                  position < group.windowIDs.count,
                  group.windowIDs[position].contains(windowID) else {
                self.hideCarousel()
                return
            }
            let generation = self.carouselRequestGeneration
            self.focus(space: space,
                       windowID: windowID,
                       selectedSpace: group.selected) { [weak self] _ in
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
                  let displayIndex = requestedCarouselDisplay,
                  let group = snapshot.group(forDisplay: displayIndex),
                  let position = group.position(of: space),
                  position < group.foregroundWindowIDs.count {
            carouselView.setForegroundID(group.foregroundWindowIDs[position])
        }

        var reconciled: [Int: DisplayPanel] = [:]
        for group in snapshot.displays {
            if let existing = displayPanels[group.displayIndex] {
                reconciled[group.displayIndex] = existing
            } else {
                reconciled[group.displayIndex] = makeDisplayPanel(displayIndex: group.displayIndex)
            }
        }
        for (displayIndex, entry) in displayPanels where reconciled[displayIndex] == nil {
            entry.panel.orderOut(nil)
        }
        displayPanels = reconciled

        for group in snapshot.displays {
            guard let entry = displayPanels[group.displayIndex] else { continue }
            let panelFrame = appKitFrame(for: group.frame)
            entry.panel.setFrame(panelFrame, display: false)
            entry.view.frame = CGRect(origin: .zero, size: panelFrame.size)
            entry.view.apply(group: group,
                             visible: snapshot.visible,
                             rearrangeSpaces: snapshot.rearrangeSpaces)
            if snapshot.visible {
                entry.panel.orderFrontRegardless()
            } else {
                entry.panel.orderOut(nil)
            }
        }
    }

    func showCarousel(for space: Int, displayIndex: Int, anchor: CGPoint) {
        cancelCarouselDismissal()
        carouselRequestGeneration &+= 1
        let generation = carouselRequestGeneration
        requestedCarouselSpace = space
        requestedCarouselDisplay = displayIndex
        carouselAnchor = anchor
        carouselPanel.orderOut(nil)

        guard let snapshot,
              snapshot.visible,
              let group = snapshot.group(forDisplay: displayIndex),
              let position = group.position(of: space),
              position < group.windowIDs.count else {
            requestedCarouselSpace = nil
            requestedCarouselDisplay = nil
            carouselAnchor = nil
            carouselView.apply([])
            return
        }

        let windowIDs = group.windowIDs[position]
        guard !windowIDs.isEmpty else {
            requestedCarouselSpace = nil
            requestedCarouselDisplay = nil
            carouselAnchor = nil
            carouselView.apply([])
            return
        }

        WindowCapture.capture(ids: windowIDs) { [weak self] thumbnails in
            guard let self,
                  self.carouselRequestGeneration == generation,
                  self.requestedCarouselSpace == space,
                  self.requestedCarouselDisplay == displayIndex,
                  let currentSnapshot = self.snapshot,
                  currentSnapshot.visible,
                  let currentGroup = currentSnapshot.group(forDisplay: displayIndex),
                  let currentPosition = currentGroup.position(of: space),
                  currentPosition < currentGroup.windowIDs.count,
                  currentGroup.windowIDs[currentPosition] == windowIDs else { return }

            guard !thumbnails.isEmpty else {
                self.hideCarousel()
                return
            }

            let currentForegroundID = currentPosition < currentGroup.foregroundWindowIDs.count
                ? currentGroup.foregroundWindowIDs[currentPosition]
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
        requestedCarouselDisplay = nil
        carouselAnchor = nil
        pendingClosedWindowIDs.removeAll()
        suppressNextCarouselExit = false
        carouselPanel.orderOut(nil)
        carouselView.apply([])
    }

    private func makeDisplayPanel(displayIndex: Int) -> DisplayPanel {
        let view = SpacesView(frame: .zero)
        let panel = NonActivatingPanel(contentRect: .zero,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered,
                                       defer: false)
        panel.contentView = view
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.level = OverlayWindowPolicy.level
        panel.collectionBehavior = OverlayWindowPolicy.collectionBehavior

        view.onHoverChanged = { [weak self] space, anchor in
            guard let self else { return }
            guard let space else {
                self.scheduleCarouselDismissal()
                return
            }
            self.cancelCarouselDismissal()
            if self.requestedCarouselSpace != space
                || self.requestedCarouselDisplay != displayIndex {
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
        view.onHoverReady = { [weak self] space, anchor in
            self?.showCarousel(
                for: space,
                displayIndex: displayIndex,
                anchor: CGPoint(x: anchor.midX, y: anchor.minY)
            )
        }
        view.onSpaceClicked = { [weak self] space, anchor in
            guard let self, let anchor else { return }
            self.showCarousel(
                for: space,
                displayIndex: displayIndex,
                anchor: CGPoint(x: anchor.midX, y: anchor.minY)
            )
        }
        view.onHoverEnded = { [weak self] in
            self?.scheduleCarouselDismissal()
        }
        view.onLayoutChanged = { [weak self] in
            guard let self,
                  !WindowCarouselModel.shouldPreserveCarouselOnLayoutChange(
                      requestedSpace: self.requestedCarouselSpace
                  ) else { return }
            self.hideCarousel()
        }

        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.handleOverlayOcclusionChange(displayIndex: displayIndex)
        }
        return DisplayPanel(panel: panel, view: view, occlusionObserver: observer)
    }


    private func handleOverlayOcclusionChange(displayIndex: Int) {
        guard snapshot?.visible == true,
              let entry = displayPanels[displayIndex] else { return }

        guard entry.panel.occlusionState.contains(.visible) else {
            if requestedCarouselDisplay == displayIndex {
                hideCarousel()
            }
            entry.view.resetHover()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.snapshot?.visible == true,
                  let entry = self.displayPanels[displayIndex],
                  entry.panel.occlusionState.contains(.visible) else { return }
            entry.view.revalidateHover()
        }
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
              let displayIndex = requestedCarouselDisplay,
              let snapshot,
              let group = snapshot.group(forDisplay: displayIndex),
              let position = group.position(of: space),
              position < group.windowIDs.count,
              group.windowIDs[position].contains(windowID) else { return }

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
              let space = requestedCarouselSpace,
              let displayIndex = requestedCarouselDisplay else { return false }
        guard let previousGroup = previousSnapshot.group(forDisplay: displayIndex),
              let nextGroup = nextSnapshot.group(forDisplay: displayIndex),
              let previousPosition = previousGroup.position(of: space),
              let nextPosition = nextGroup.position(of: space),
              previousPosition < previousGroup.windowIDs.count,
              nextPosition < nextGroup.windowIDs.count else { return true }
        let previousWindowIDs = Set(previousGroup.windowIDs[previousPosition])
        let nextWindowIDs = Set(nextGroup.windowIDs[nextPosition])
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
              let displayIndex = requestedCarouselDisplay,
              let previousGroup = previousSnapshot.group(forDisplay: displayIndex),
              let nextGroup = nextSnapshot.group(forDisplay: displayIndex),
              let previousPosition = previousGroup.position(of: space),
              let nextPosition = nextGroup.position(of: space),
              previousPosition < previousGroup.foregroundWindowIDs.count,
              nextPosition < nextGroup.foregroundWindowIDs.count else { return false }
        return previousGroup.foregroundWindowIDs[previousPosition]
            != nextGroup.foregroundWindowIDs[nextPosition]
    }

    private func overlayMovedToDifferentDisplay(from previousSnapshot: OverlaySnapshot?,
                                                to nextSnapshot: OverlaySnapshot) -> Bool {
        guard let previousSnapshot,
              let displayIndex = requestedCarouselDisplay,
              let previousGroup = previousSnapshot.group(forDisplay: displayIndex),
              let nextGroup = nextSnapshot.group(forDisplay: displayIndex),
              let previousDisplay = displayID(containing: previousGroup.frame),
              let nextDisplay = displayID(containing: nextGroup.frame) else { return false }
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
