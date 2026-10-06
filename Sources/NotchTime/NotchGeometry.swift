import AppKit

/// Where the notch is and how big the island may grow. All coordinates are screen coordinates.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var notchMidX: CGFloat
    var screenTop: CGFloat
    var hasNotch: Bool

    /// Width of the text area on each side of the notch when the compact timer is showing.
    var sideWidth: CGFloat { 118 }
    var expandedWidth: CGFloat { 440 }
    /// Row holding the client chip and the ⋯ menu; level with the notch, chips start 10 pt from the top.
    var controlsRowHeight: CGFloat { max(notchHeight, 38) }
    /// Everything below that row: timer, task field, buttons.
    var expandedBodyHeight: CGFloat { 138 }

    var collapsedIdleWidth: CGFloat { notchWidth }
    var collapsedRunningWidth: CGFloat { notchWidth + sideWidth * 2 }
    var expandedHeight: CGFloat { controlsRowHeight + expandedBodyHeight }

    static func measure(screen: NSScreen) -> NotchMetrics {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = max(120, right.minX - left.maxX)
            return NotchMetrics(notchWidth: width,
                                notchHeight: inset,
                                notchMidX: (left.maxX + right.minX) / 2,
                                screenTop: screen.frame.maxY,
                                hasNotch: true)
        }
        // No notch: pretend there is one, centred, as tall as the menu bar.
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return NotchMetrics(notchWidth: 196,
                            notchHeight: menuBar,
                            notchMidX: screen.frame.midX,
                            screenTop: screen.frame.maxY,
                            hasNotch: false)
    }

    /// The screen that owns the notch (the built-in display), falling back to the main one.
    static func targetScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
