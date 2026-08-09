import CoreGraphics

struct HoverCardState {
    private(set) var space: Int?
    private var generation = 0

    mutating func transition(to nextSpace: Int?) -> Int? {
        guard nextSpace != space else { return nil }
        space = nextSpace
        generation &+= 1
        return generation
    }

    mutating func reset() {
        space = nil
        generation &+= 1
    }

    mutating func invalidateAndTransition(to nextSpace: Int?) -> Int {
        space = nextSpace
        generation &+= 1
        return generation
    }

    func isCurrent(_ scheduledGeneration: Int, space scheduledSpace: Int) -> Bool {
        generation == scheduledGeneration && space == scheduledSpace
    }
}

struct HoverDismissalGeneration {
    private var value = 0

    mutating func schedule() -> Int {
        value &+= 1
        return value
    }

    mutating func cancel() {
        value &+= 1
    }

    func isCurrent(_ scheduled: Int) -> Bool {
        scheduled == value
    }
}

enum YabaiCommandModel {
    static func focusCommands(space: Int,
                              windowID: CGWindowID,
                              selectedSpace: Int? = nil) -> [[String]] {
        [["-m", "window", "--focus", String(windowID)]]
    }

    static func closeCommand(windowID: CGWindowID) -> [String] {
        ["-m", "window", String(windowID), "--close"]
    }
}

enum SpaceCardClickModel {
    static func shouldOpenCarousel(afterDrag: Bool) -> Bool {
        !afterDrag
    }
}

enum WindowCarouselModel {
    static let cardWidth: CGFloat = 220
    static let cardHeight: CGFloat = 174
    static let imageRect = CGRect(x: 10, y: 30, width: 200, height: 132)
    static let cardSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let fitTolerance: CGFloat = 3
    static let titleRowIconSize: CGFloat = 16
    static let titleRowIconGap: CGFloat = 8
    static let closeButtonSize: CGFloat = 20
    static let closeButtonInset: CGFloat = 6

    static func titleRowLayout(in row: CGRect) -> (icon: CGRect, title: CGRect) {
        let icon = CGRect(
            x: row.minX,
            y: row.midY - titleRowIconSize / 2,
            width: titleRowIconSize,
            height: titleRowIconSize
        )
        let title = CGRect(
            x: icon.maxX + titleRowIconGap,
            y: row.minY,
            width: max(0, row.maxX - icon.maxX - titleRowIconGap),
            height: row.height
        )
        return (icon, title)
    }

    static func closeButtonRect(in card: CGRect) -> CGRect {
        CGRect(
            x: card.maxX - closeButtonInset - closeButtonSize,
            y: card.maxY - closeButtonInset - closeButtonSize,
            width: closeButtonSize,
            height: closeButtonSize
        )
    }

    static func carouselWidth(entryCount: Int) -> CGFloat {
        let count = max(1, min(entryCount, 3))
        return horizontalPadding * 2
            + CGFloat(count) * cardWidth
            + CGFloat(count - 1) * cardSpacing
    }

    static func shouldPreserveCarouselOnLayoutChange(requestedSpace: Int?) -> Bool {
        requestedSpace != nil
    }

    static func shouldDrawCloseButton(windowID: CGWindowID,
                                      hoveredID: CGWindowID?) -> Bool {
        hoveredID == windowID
    }

    static func matchesWindowIDs(_ requestedWindowIDs: [CGWindowID],
                                 for space: Int,
                                 in currentWindowIDs: [[CGWindowID]]) -> Bool {
        guard space > 0, space <= currentWindowIDs.count else { return false }
        return currentWindowIDs[space - 1] == requestedWindowIDs
    }

    static func aspectFit(source: CGSize, in rect: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0,
              rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / source.width, rect.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: rect.midX - size.width / 2,
                      y: rect.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    static func clampOffset(_ offset: CGFloat,
                            contentWidth: CGFloat,
                            viewportWidth: CGFloat) -> CGFloat {
        let overflow = contentWidth - viewportWidth
        if overflow <= fitTolerance { return 0 }
        return min(max(0, offset), overflow)
    }
}
