import AppKit

final class SpacesView: NSView {
    private let yabaiExecutable = "/opt/homebrew/bin/yabai"
    var onHoverChanged: ((Int?, CGRect?) -> Void)?
    var onHoverReady: ((Int, CGRect) -> Void)?
    var onHoverEnded: (() -> Void)?
    var onSpaceClicked: ((Int, CGRect?) -> Void)?
    var onLayoutChanged: (() -> Void)?

    private struct ItemLayout {
        let space: Int
        let frame: CGRect
        let number: String
        let apps: [String]
    }

    private struct DragState {
        let sourceSpace: Int
        let startPoint: CGPoint
        let grabOffset: CGFloat
        var currentPoint: CGPoint
        var destination: Int?
        var active: Bool
        var hoverInvalidated: Bool
    }

    private let numberFont = NSFont(name: "SF Mono", size: 14)
        ?? NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
    private let white = NSColor(calibratedRed: 0xe2 / 255, green: 0xe2 / 255, blue: 0xe3 / 255, alpha: 1)
    private let red = NSColor(calibratedRed: 0xfc / 255, green: 0x5d / 255, blue: 0x7c / 255, alpha: 1)
    private let grey = NSColor(calibratedRed: 0x7f / 255, green: 0x84 / 255, blue: 0x90 / 255, alpha: 1)
    private let black = NSColor(calibratedRed: 0x18 / 255, green: 0x18 / 255, blue: 0x19 / 255, alpha: 1)
    private let background = NSColor(calibratedRed: 0x36 / 255, green: 0x39 / 255, blue: 0x44 / 255, alpha: 0.85)
    private let inactiveBorder = NSColor(calibratedRed: 0x2c / 255, green: 0x2e / 255, blue: 0x34 / 255, alpha: 1)
    private let cardSpacing: CGFloat = 5
    private let dragThreshold: CGFloat = 4

    private var snapshot: OverlaySnapshot?
    private var offset: CGFloat = 0
    private var contentWidth: CGFloat = 0
    private var dragState: DragState?
    private var iconCache: [String: NSImage] = [:]
    private var hoverState = HoverCardState()
    private var pointerTrackingArea: NSTrackingArea?

    private lazy var fallbackIcon: NSImage = {
        NSWorkspace.shared.icon(
            forFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
        )
    }()

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func apply(_ snapshot: OverlaySnapshot) {
        let previousFrames = itemLayouts().map(\.frame)
        let previousOffset = offset
        let wasDragging = dragState?.active == true
        let previousSelection = self.snapshot?.selected
        self.snapshot = snapshot
        if !snapshot.visible { hoverState.reset() }
        if !snapshot.rearrangeSpaces { dragState = nil }
        let layouts = itemLayouts()
        contentWidth = layouts.last.map { $0.frame.maxX + SpaceLayoutModel.horizontalPadding } ?? 0
        offset = ScrollModel.clampOffset(offset,
                                         contentWidth: contentWidth,
                                         viewportWidth: bounds.width)

        if previousSelection != snapshot.selected,
           let selected = layouts.first(where: { $0.space == snapshot.selected }) {
            if selected.frame.minX < offset {
                offset = selected.frame.minX
            } else if selected.frame.maxX > offset + bounds.width {
                offset = selected.frame.maxX - bounds.width
            }
            offset = ScrollModel.clampOffset(offset,
                                             contentWidth: contentWidth,
                                             viewportWidth: bounds.width)
        }
        if snapshot.visible,
           (previousFrames != layouts.map(\.frame)
            || previousOffset != offset
            || wasDragging && dragState == nil) {
            let point = dragState?.active == true ? nil : currentPointerLocation()
            invalidateHover(reEvaluateAt: point)
        }
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousFrames = itemLayouts().map(\.frame)
        let previousOffset = offset
        super.setFrameSize(newSize)
        let layouts = itemLayouts()
        contentWidth = layouts.last.map { $0.frame.maxX + SpaceLayoutModel.horizontalPadding } ?? 0
        offset = ScrollModel.clampOffset(offset,
                                         contentWidth: contentWidth,
                                         viewportWidth: newSize.width)
        if snapshot?.visible == true,
           (previousFrames != layouts.map(\.frame) || previousOffset != offset) {
            let point = dragState?.active == true ? nil : currentPointerLocation()
            invalidateHover(reEvaluateAt: point)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let snapshot else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        let shellFrame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shellPath = NSBezierPath(roundedRect: shellFrame,
                                     xRadius: SpaceLayoutModel.cardCornerRadius,
                                     yRadius: SpaceLayoutModel.cardCornerRadius)
        shellPath.addClip()
        drawOverlayShell(shellFrame)

        let layouts = itemLayouts()
        if snapshot.rearrangeSpaces,
           let dragState, dragState.active,
           let destination = dragState.destination,
           destination >= 1,
           destination <= layouts.count,
           let source = layouts.first(where: { $0.space == dragState.sourceSpace }) {
            drawDragging(layouts,
                         source: source,
                         destination: destination,
                         state: dragState,
                         selectedSpace: snapshot.selected,
                         dirtyRect: dirtyRect)
        } else {
            for item in layouts {
                drawCard(item,
                         frame: item.frame.offsetBy(dx: -offset, dy: 0),
                         selected: item.space == snapshot.selected,
                         alpha: 1,
                         dirtyRect: dirtyRect)
            }
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawDragging(_ layouts: [ItemLayout],
                              source: ItemLayout,
                              destination: Int,
                              state: DragState,
                              selectedSpace: Int,
                              dirtyRect: NSRect) {
        let remaining = layouts.filter { $0.space != source.space }
        var x: CGFloat = SpaceLayoutModel.horizontalPadding
        var remainingIndex = 0

        for slot in 1...layouts.count {
            if slot == destination {
                x += source.frame.width + cardSpacing
                continue
            }

            let item = remaining[remainingIndex]
            remainingIndex += 1
            let frame = CGRect(x: x,
                               y: item.frame.minY,
                               width: item.frame.width,
                               height: item.frame.height)
            drawCard(ItemLayout(space: item.space,
                                frame: frame,
                                number: item.number,
                                apps: item.apps),
                     frame: frame.offsetBy(dx: -offset, dy: 0),
                     selected: item.space == selectedSpace,
                     alpha: 1,
                     dirtyRect: dirtyRect)
            x += item.frame.width + cardSpacing
        }

        let contentPointX = state.currentPoint.x + offset - state.grabOffset
        let ghostFrame = CGRect(x: contentPointX,
                                y: source.frame.minY,
                                width: source.frame.width,
                                height: source.frame.height)
        drawCard(source,
                 frame: ghostFrame.offsetBy(dx: -offset, dy: 0),
                 selected: source.space == selectedSpace,
                 alpha: 0.55,
                 dirtyRect: dirtyRect)

        guard let indicatorX = SpaceReorderModel.insertionX(
            for: destination,
            frames: layouts.map(\.frame),
            source: source.space,
            spacing: cardSpacing
        ) else { return }

        let indicatorFrame = CGRect(x: indicatorX - offset - 1,
                                    y: source.frame.minY - 4,
                                    width: 2,
                                    height: source.frame.height + 8)
        if indicatorFrame.maxX >= dirtyRect.minX && indicatorFrame.minX <= dirtyRect.maxX {
            red.setFill()
            NSBezierPath(rect: indicatorFrame).fill()
        }
    }

    private func drawCard(_ item: ItemLayout,
                          frame: CGRect,
                          selected: Bool,
                          alpha: CGFloat,
                          dirtyRect: NSRect) {
        if frame.maxX < dirtyRect.minX || frame.minX > dirtyRect.maxX { return }

        let outer = NSBezierPath(roundedRect: frame,
                                 xRadius: SpaceLayoutModel.cardCornerRadius,
                                 yRadius: SpaceLayoutModel.cardCornerRadius)
        (selected ? grey : inactiveBorder).withAlphaComponent(alpha).setStroke()
        outer.lineWidth = SpaceLayoutModel.cardStrokeWidth
        outer.stroke()

        let inner = frame.insetBy(dx: 1, dy: 1)
        let innerPath = NSBezierPath(roundedRect: inner,
                                     xRadius: SpaceLayoutModel.cardInnerCornerRadius,
                                     yRadius: SpaceLayoutModel.cardInnerCornerRadius)
        background.withAlphaComponent(alpha).setFill()
        innerPath.fill()
        (selected ? black : inactiveBorder).withAlphaComponent(alpha).setStroke()
        innerPath.lineWidth = SpaceLayoutModel.cardStrokeWidth
        innerPath.stroke()

        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: (selected ? red : white).withAlphaComponent(alpha),
        ]
        let numberSize = item.number.size(withAttributes: numberAttributes)
        let numberPoint = CGPoint(x: frame.minX + 14,
                                  y: frame.midY - numberSize.height / 2 + 1)
        item.number.draw(at: numberPoint, withAttributes: numberAttributes)

        for (index, appName) in item.apps.enumerated() {
            let iconX = numberPoint.x
                + numberSize.width
                + SpaceLayoutModel.numberToIconsSpacing
                + CGFloat(index) * (SpaceLayoutModel.iconSize + SpaceLayoutModel.iconSpacing)
            let iconFrame = CGRect(x: iconX,
                                   y: frame.midY - SpaceLayoutModel.iconSize / 2,
                                   width: SpaceLayoutModel.iconSize,
                                   height: SpaceLayoutModel.iconSize)
            let image = appIcon(for: appName)
            image.draw(in: iconFrame,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: alpha,
                       respectFlipped: true,
                       hints: nil)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        var delta = event.scrollingDeltaX
        if abs(delta) < 0.001 {
            delta = event.scrollingDeltaY
        }
        guard abs(delta) >= 0.001 else { return }

        let previousOffset = offset
        offset = ScrollModel.clampOffset(offset - delta,
                                         contentWidth: contentWidth,
                                         viewportWidth: bounds.width)
        if offset != previousOffset {
            let point = dragState?.active == true
                ? nil
                : convert(event.locationInWindow, from: nil)
            invalidateHover(reEvaluateAt: point)
        }
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverState.reset()
        onHoverChanged?(nil, nil)
        onHoverEnded?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        guard snapshot?.rearrangeSpaces == true else {
            guard let space = space(at: point) else { return }
            onSpaceClicked?(space, cardScreenRect(for: space))
            runYabai(["-m", "space", "--focus", String(space)])
            return
        }

        guard let source = itemLayouts().first(where: { $0.frame.offsetBy(dx: -offset, dy: 0).contains(point) }) else {
            dragState = nil
            return
        }

        let contentPointX = point.x + offset
        dragState = DragState(sourceSpace: source.space,
                              startPoint: point,
                              grabOffset: contentPointX - source.frame.minX,
                              currentPoint: point,
                              destination: source.space,
                              active: false,
                              hoverInvalidated: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard snapshot?.rearrangeSpaces == true else { return }
        guard var state = dragState else { return }

        let point = convert(event.locationInWindow, from: nil)
        state.currentPoint = point

        if !state.hoverInvalidated {
            state.hoverInvalidated = true
            invalidateHover(reEvaluateAt: nil)
        }

        if !state.active {
            let deltaX = point.x - state.startPoint.x
            let deltaY = point.y - state.startPoint.y
            guard deltaX * deltaX + deltaY * deltaY >= dragThreshold * dragThreshold else {
                dragState = state
                return
            }
            state.active = true
        }

        if bounds.contains(point) {
            state.destination = SpaceReorderModel.destinationIndex(
                for: point.x + offset,
                frames: itemLayouts().map(\.frame),
                source: state.sourceSpace
            )
        } else {
            state.destination = nil
        }

        dragState = state
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let state = dragState else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragState = nil
        needsDisplay = true

        if state.hoverInvalidated {
            invalidateHover(reEvaluateAt: bounds.contains(point) ? point : nil)
        }

        guard state.active else {
            if SpaceCardClickModel.shouldOpenCarousel(afterDrag: state.active) {
                onSpaceClicked?(state.sourceSpace, cardScreenRect(for: state.sourceSpace))
            }
            runYabai(["-m", "space", "--focus", String(state.sourceSpace)])
            return
        }

        guard let destination = state.destination,
              destination != state.sourceSpace else { return }

        runYabai(["-m", "space", String(state.sourceSpace), "--move", String(destination)]) {
            self.triggerSpaceOrderRefresh()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let space = space(at: convert(event.locationInWindow, from: nil)) else { return }
        runYabai(["-m", "space", "--destroy", String(space)])
    }

    private func space(at point: CGPoint) -> Int? {
        let contentPoint = CGPoint(x: point.x + offset, y: point.y)
        return itemLayouts().first(where: { $0.frame.contains(contentPoint) })?.space
    }

    private func updateHover(at point: CGPoint) {
        let next = space(at: point)
        guard let generation = hoverState.transition(to: next) else { return }
        publishHover(next, generation: generation)
    }

    private func invalidateHover(reEvaluateAt point: CGPoint?) {
        let next = point.flatMap { bounds.contains($0) ? space(at: $0) : nil }
        let generation = hoverState.invalidateAndTransition(to: next)
        onLayoutChanged?()
        guard next != nil else { return }
        publishHover(next, generation: generation)
    }

    private func publishHover(_ next: Int?, generation: Int) {
        let anchor = next.flatMap { cardScreenRect(for: $0) }
        onHoverChanged?(next, anchor)
        guard let next, anchor != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self,
                  self.hoverState.isCurrent(generation, space: next) else { return }
            guard let anchor = self.cardScreenRect(for: next) else { return }
            self.onHoverReady?(next, anchor)
        }
    }

    private func currentPointerLocation() -> CGPoint? {
        guard let window else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(pointInWindow, from: nil)
        return bounds.contains(point) ? point : nil
    }

    private func cardScreenRect(for space: Int) -> CGRect? {
        guard let window,
              let item = itemLayouts().first(where: { $0.space == space }) else { return nil }
        let localRect = item.frame.offsetBy(dx: -offset, dy: 0)
        return window.convertToScreen(convert(localRect, to: nil))
    }

    private func itemLayouts() -> [ItemLayout] {
        guard let snapshot else { return [] }
        var x: CGFloat = SpaceLayoutModel.horizontalPadding

        return snapshot.apps.enumerated().map { index, apps in
            let number = String(index + 1)
            let numberWidth = number.size(withAttributes: [.font: numberFont]).width
            let width = SpaceLayoutModel.cardWidth(numberWidth: numberWidth,
                                                    appCount: apps.count)
            let frame = CGRect(x: x,
                               y: max(0, (bounds.height - SpaceLayoutModel.cardHeight) / 2),
                               width: width,
                               height: SpaceLayoutModel.cardHeight)
            x += width + cardSpacing
            return ItemLayout(space: index + 1,
                              frame: frame,
                              number: number,
                              apps: apps)
        }
    }

    private func appIcon(for appName: String) -> NSImage {
        if let cached = iconCache[appName] {
            return cached
        }

        if let icon = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == appName })?.icon {
            iconCache[appName] = icon
            return icon
        }

        return fallbackIcon
    }

    private func drawOverlayShell(_ frame: CGRect) {
        let radius = SpaceLayoutModel.cardCornerRadius
        let curveFactor: CGFloat = 0.55228475
        let sides = NSBezierPath()

        sides.move(to: CGPoint(x: frame.minX + radius, y: frame.maxY))
        sides.curve(to: CGPoint(x: frame.minX, y: frame.maxY - radius),
                    controlPoint1: CGPoint(x: frame.minX + radius * (1 - curveFactor),
                                           y: frame.maxY),
                    controlPoint2: CGPoint(x: frame.minX,
                                           y: frame.maxY - radius * (1 - curveFactor)))
        sides.line(to: CGPoint(x: frame.minX, y: frame.minY + radius))
        sides.curve(to: CGPoint(x: frame.minX + radius, y: frame.minY),
                    controlPoint1: CGPoint(x: frame.minX,
                                           y: frame.minY + radius * (1 - curveFactor)),
                    controlPoint2: CGPoint(x: frame.minX + radius * (1 - curveFactor),
                                           y: frame.minY))

        sides.move(to: CGPoint(x: frame.maxX - radius, y: frame.maxY))
        sides.curve(to: CGPoint(x: frame.maxX, y: frame.maxY - radius),
                    controlPoint1: CGPoint(x: frame.maxX - radius * (1 - curveFactor),
                                           y: frame.maxY),
                    controlPoint2: CGPoint(x: frame.maxX,
                                           y: frame.maxY - radius * (1 - curveFactor)))
        sides.line(to: CGPoint(x: frame.maxX, y: frame.minY + radius))
        sides.curve(to: CGPoint(x: frame.maxX - radius, y: frame.minY),
                    controlPoint1: CGPoint(x: frame.maxX,
                                           y: frame.minY + radius * (1 - curveFactor)),
                    controlPoint2: CGPoint(x: frame.maxX - radius * (1 - curveFactor),
                                           y: frame.minY))

        inactiveBorder.setStroke()
        sides.lineWidth = SpaceLayoutModel.cardStrokeWidth
        sides.stroke()
    }

    private func runYabai(_ arguments: [String], onSuccess: (() -> Void)? = nil) {
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
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return }
            onSuccess?()
        }
    }

    private func triggerSpaceOrderRefresh() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sketchybar", "--trigger", "spaces_order_changed"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
