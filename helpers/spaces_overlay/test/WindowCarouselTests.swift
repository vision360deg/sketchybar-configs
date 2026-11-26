import CoreGraphics

enum WindowCarouselTests {
    static func run() {
        let thumbnails = (1...3).map { id in
            WindowThumbnailData(id: CGWindowID(id),
                                image: nil,
                                sourceSize: .zero,
                                appName: "",
                                title: "Window \(id)",
                                ownerPID: nil)
        }
        let carousel = WindowCarouselView(
            frame: CGRect(x: 0, y: 0, width: 480, height: 194)
        )
        carousel.apply(thumbnails)
        carousel.apply(thumbnails, foregroundID: thumbnails[1].id)
        SpacesOverlayTests.expect(carousel.foregroundID == thumbnails[1].id,
                                  "stores the foreground window for the carousel")
        let frames = carousel.cardFrames()

        SpacesOverlayTests.expect(frames.count == 3,
                                  "lays out one card per thumbnail")
        SpacesOverlayTests.expect(frames[0].minX == WindowCarouselModel.horizontalPadding,
                                  "starts the first card at the horizontal padding")
        SpacesOverlayTests.expect(frames[1].minX - frames[0].maxX == WindowCarouselModel.cardSpacing,
                                  "separates the first two cards by card spacing")
        SpacesOverlayTests.expect(frames[2].minX - frames[1].maxX == WindowCarouselModel.cardSpacing,
                                  "separates the final two cards by card spacing")
        SpacesOverlayTests.expect(carousel.clampedOffset(40) == 40,
                                  "allows scrolling when cards exceed the viewport")

        let titleRowLayout = WindowCarouselModel.titleRowLayout(
            in: CGRect(x: 10, y: 8, width: 200, height: 16)
        )
        SpacesOverlayTests.expect(
            titleRowLayout.icon == CGRect(x: 10, y: 8, width: 16, height: 16)
                && titleRowLayout.title == CGRect(x: 34, y: 8, width: 176, height: 16),
            "reserves a 16px app icon and the remaining width for the window title"
        )

        let closeCarousel = WindowCarouselView(
            frame: CGRect(x: 0, y: 0, width: 480, height: 194)
        )
        closeCarousel.apply(thumbnails)
        let closeRect = WindowCarouselModel.closeButtonRect(in: closeCarousel.cardFrames()[0])
        var closedWindowID: CGWindowID?
        closeCarousel.onClose = { closedWindowID = $0 }
        SpacesOverlayTests.expect(
            closeCarousel.close(at: CGPoint(x: closeRect.midX, y: closeRect.midY)) == thumbnails[0].id
                && closedWindowID == thumbnails[0].id,
            "routes a close-button click to the preview window"
        )
        SpacesOverlayTests.expect(
            YabaiCommandModel.closeCommand(windowID: thumbnails[0].id)
                == ["-m", "window", "1", "--close"],
            "closes a window directly without focusing its space"
        )
        SpacesOverlayTests.expect(
            WindowCarouselModel.carouselWidth(entryCount: 2) == 468
                && WindowCarouselModel.carouselWidth(entryCount: 3) == 696
                && WindowCarouselModel.carouselWidth(entryCount: 2)
                    < WindowCarouselModel.carouselWidth(entryCount: 3),
            "shrinks the carousel width when a preview card is removed"
        )
        SpacesOverlayTests.expect(
            WindowCarouselModel.shouldPreserveCarouselOnLayoutChange(requestedSpace: 3)
                && !WindowCarouselModel.shouldPreserveCarouselOnLayoutChange(requestedSpace: nil),
            "keeps an open carousel through a space-card layout change"
        )
        SpacesOverlayTests.expect(
            WindowCarouselModel.shouldDrawCloseButton(windowID: 1, hoveredID: 1)
                && !WindowCarouselModel.shouldDrawCloseButton(windowID: 1, hoveredID: 2),
            "shows the close button only while its preview card is hovered"
        )
        SpacesOverlayTests.expect(
            SpaceCardClickModel.action(clickedSpace: 2, selectedSpace: 2, carouselOpen: false) == .openCarousel
                && SpaceCardClickModel.action(clickedSpace: 2, selectedSpace: 2, carouselOpen: true) == .closeCarousel
                && SpaceCardClickModel.action(clickedSpace: 3, selectedSpace: 2, carouselOpen: true) == .switchSpace
                && SpaceCardClickModel.action(clickedSpace: 3, selectedSpace: nil, carouselOpen: false) == .switchSpace,
            "the selected space's card toggles its previews; another card switches spaces"
        )

        let scrolledOffset = carousel.clampedOffset(240)
        carousel.scroll(by: -240)
        let scrolledSelectionPoint = CGPoint(
            x: frames[1].midX - scrolledOffset,
            y: frames[1].midY
        )
        var selectedWindowID: CGWindowID?
        carousel.onSelect = { selectedWindowID = $0 }
        SpacesOverlayTests.expect(carousel.select(at: scrolledSelectionPoint) == thumbnails[1].id,
                                  "maps a scrolled card click to its original window ID")
        SpacesOverlayTests.expect(selectedWindowID == thumbnails[1].id,
                                  "reports only the clicked window ID")

        let currentThumbnails = [
            WindowThumbnailData(id: 101,
                                image: nil,
                                sourceSize: .zero,
                                appName: "Safari",
                                title: "Browser",
                                ownerPID: nil),
        ]
        let staleSelectionCarousel = WindowCarouselView(
            frame: CGRect(x: 0, y: 0, width: 480, height: 194)
        )
        staleSelectionCarousel.apply(currentThumbnails)
        var staleSelection: CGWindowID?
        staleSelectionCarousel.onSelect = { staleSelection = $0 }
        SpacesOverlayTests.expect(
            staleSelectionCarousel.select(id: 202) == nil && staleSelection == nil,
            "does not select an ID missing from the current thumbnail list"
        )
        SpacesOverlayTests.expect(
            WindowCapture.displayTitle(title: "", appName: "Safari") == "Safari",
            "uses the app name when a captured window title is empty"
        )

        let fittingCarousel = WindowCarouselView(
            frame: CGRect(x: 0, y: 0, width: 720, height: 194)
        )
        fittingCarousel.apply(thumbnails)
        SpacesOverlayTests.expect(fittingCarousel.clampedOffset(40) == 0,
                                  "prevents scrolling when cards fit the viewport")

        let fitted = WindowCarouselModel.aspectFit(
            source: CGSize(width: 1600, height: 900),
            in: CGRect(x: 0, y: 0, width: 220, height: 160)
        )
        SpacesOverlayTests.expect(abs(fitted.width - 220) < 0.001,
                                  "fits a wide thumbnail to the card width")
        SpacesOverlayTests.expect(abs(fitted.height - 123.75) < 0.001,
                                  "preserves a wide thumbnail aspect ratio")
        let fullImageRect = CGRect(x: 10, y: 30, width: 200, height: 132)
        let zeroSized = WindowCarouselModel.aspectFit(source: .zero, in: fullImageRect)
        SpacesOverlayTests.expect(zeroSized == fullImageRect,
                                  "uses the full image rectangle for a zero-size source")
        SpacesOverlayTests.expect(zeroSized.origin.x.isFinite
                                  && zeroSized.origin.y.isFinite
                                  && zeroSized.width.isFinite
                                  && zeroSized.height.isFinite,
                                  "keeps zero-size source geometry finite")
        SpacesOverlayTests.expect(WindowCarouselModel.clampOffset(-1, contentWidth: 800, viewportWidth: 420) == 0,
                                  "clamps carousel offset at zero")
        SpacesOverlayTests.expect(WindowCarouselModel.clampOffset(900, contentWidth: 800, viewportWidth: 420) == 380,
                                  "clamps carousel offset at its maximum")

        var hover = HoverCardState()
        let firstCardGeneration = hover.transition(to: 1)
        SpacesOverlayTests.expect(firstCardGeneration != nil,
                                  "entering a card schedules its hover timer")
        _ = hover.transition(to: nil)
        SpacesOverlayTests.expect(hover.space == nil,
                                  "moving from a card to spacing clears the hovered card")
        SpacesOverlayTests.expect(!hover.isCurrent(firstCardGeneration!, space: 1),
                                  "card-to-spacing transitions invalidate the card timer")

        let secondCardGeneration = hover.transition(to: 2)
        _ = hover.transition(to: 3)
        SpacesOverlayTests.expect(!hover.isCurrent(secondCardGeneration!, space: 2),
                                  "stale hover timers cannot open an old card")

        let visibleGeneration = hover.transition(to: 4)
        hover.reset()
        SpacesOverlayTests.expect(hover.space == nil,
                                  "hiding the overlay clears the hovered card")
        SpacesOverlayTests.expect(!hover.isCurrent(visibleGeneration!, space: 4),
                                  "hiding the overlay invalidates pending hover timers")

        let preLayoutGeneration = hover.transition(to: 5)!
        let postLayoutGeneration = hover.invalidateAndTransition(to: 6)
        SpacesOverlayTests.expect(!hover.isCurrent(preLayoutGeneration, space: 5),
                                  "layout changes invalidate the pending hover timer")
        SpacesOverlayTests.expect(hover.isCurrent(postLayoutGeneration, space: 6),
                                  "layout changes re-evaluate the card beneath the pointer")

        var dismissal = HoverDismissalGeneration()
        let pendingDismissal = dismissal.schedule()
        dismissal.cancel()
        SpacesOverlayTests.expect(!dismissal.isCurrent(pendingDismissal),
                                  "entering the carousel keeps the preview open during the dismissal bridge")

        let capturedWindowIDs: [CGWindowID] = [101, 102]
        SpacesOverlayTests.expect(
            WindowCarouselModel.matchesWindowIDs(
                capturedWindowIDs,
                for: 1,
                in: [[101, 102], [201]]
            ),
            "an unchanged active-space window list keeps a capture current"
        )
        SpacesOverlayTests.expect(
            !WindowCarouselModel.matchesWindowIDs(
                capturedWindowIDs,
                for: 1,
                in: [[101, 103], [201]]
            ),
            "a changed active-space window list invalidates a capture"
        )
        SpacesOverlayTests.expect(
            WindowCarouselModel.canReconcileWindowRemoval(
                addedWindowIDs: [],
                removedWindowIDs: [101]
            )
                && !WindowCarouselModel.canReconcileWindowRemoval(
                    addedWindowIDs: [103],
                    removedWindowIDs: [101]
                ),
            "reconciles externally closed previews without accepting new windows"
        )

        let focusCommands = YabaiCommandModel.focusCommands(
            space: 3,
            windowID: 101
        )
        SpacesOverlayTests.expect(
            focusCommands == [
                [
                    "-m", "window", "--focus", "101",
                ],
            ],
            "lets yabai focus the exact window and switch to its space atomically"
        )

        let alreadySelectedSpaceCommands = YabaiCommandModel.focusCommands(
            space: 3,
            windowID: 101,
            selectedSpace: 3
        )
        SpacesOverlayTests.expect(
            alreadySelectedSpaceCommands == focusCommands,
            "uses the same direct window focus command when its space is already selected"
        )
    }
}
