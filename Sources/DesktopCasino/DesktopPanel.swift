import AppKit
import SwiftUI

/// A borderless, non-activating window that shows on every Space, in one of three placements:
/// an ordinary window, floating above everything, or pinned below everything as a widget.
///
/// **The constraint the whole class works around.** AppKit ties two things together that the
/// window server keeps separate: how low a window sits, and whether it receives mouse events.
/// Traced via `sendEvent` on macOS 26.5, an `NSWindow` at level `-1`, `-20`,
/// `desktopIconWindow + 1` or `-2147483000` receives *nothing*, while `0`, `3` and `25` behave
/// normally. The event mask is already permissive down there — the level itself is what refuses
/// input.
///
/// Widget mode therefore keeps `NSWindow.level` at `.normal`, which is what AppKit consults when
/// routing events, and pushes only the *window server* level down through `SLSSetWindowLevel`.
/// Event routing follows the declared level; compositing follows the server level. Keeping the
/// two disagreeing is the only way to be both below everything and clickable, and it has to be
/// re-asserted on every reorder because AppKit re-declares its own level each time.
///
/// Not visible inside a fullscreen Space — a fullscreen app owns its Space.
@MainActor
final class DesktopPanel: NSPanel {
    static let size = CGSize(width: 264, height: 372)

    private static let originKey = "panelOrigin"
    private static let modeKey = "windowMode"
    private static let margin: CGFloat = 32

    /// Nothing here takes keyboard input, and refusing key status keeps a click on the machine
    /// from disturbing focus in whatever you were actually typing into. Clicks still land because
    /// `FirstMouseHostingView` accepts first mouse; mouse handling does not need key status.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Set `DESKTOPCASINO_NO_SKYLIGHT=1` to fall back to plain AppKit, losing widget mode and
    /// all-Spaces presence.
    static let usesSkyLight = SkyLight.isAvailable
        && ProcessInfo.processInfo.environment["DESKTOPCASINO_NO_SKYLIGHT"] == nil

    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Dragging is done explicitly in CasinoView: NSHostingView consumes the mouseDown
        // that `isMovableByWindowBackground` relies on, so it would never fire.
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let host = FirstMouseHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: Self.size)
        host.autoresizingMask = [.width, .height]
        contentView = host

        // The card sizes itself from its content so its padding reads as an equal margin on
        // every side; `Self.size.height` is only a starting guess.
        host.layoutSubtreeIfNeeded()
        let fitted = host.fittingSize
        if fitted.height > 0 {
            setContentSize(NSSize(width: Self.size.width, height: fitted.height))
        }

        applyMode()
    }

    // MARK: - Mode

    enum Mode: String, CaseIterable {
        /// Ordinary window: click it and it comes forward, like a Stickies note.
        case normal
        /// Above everything, on every Space.
        case floating
        /// Below every window, on every Space, and still clickable.
        case widget

        var next: Mode {
            let all = Mode.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }

        var symbolName: String {
            switch self {
            case .normal: "pin"
            case .floating: "pin.fill"
            case .widget: "square.3.layers.3d.down.right"
            }
        }

        /// Describes the current placement, then what clicking does next.
        var help: String {
            switch self {
            case .normal: "Normal window — click to float on top"
            case .floating: "Floating on top — click to pin below all windows"
            case .widget: "Pinned below all windows — click for a normal window"
            }
        }
    }

    /// Cached rather than read from `UserDefaults` on demand, because `sendEvent` and
    /// `order(_:relativeTo:)` consult it on every event.
    ///
    /// Escape hatch, if widget mode ever leaves the panel unreachable:
    ///
    ///     defaults write dev.timfedo.DesktopCasino windowMode normal
    ///
    /// or launch with `DESKTOPCASINO_MODE=normal`.
    private(set) var mode: Mode = {
        if let raw = ProcessInfo.processInfo.environment["DESKTOPCASINO_MODE"],
           let forced = Mode(rawValue: raw) { return forced }
        return Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .widget
    }()

    func setMode(_ newMode: Mode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        applyMode()
        joinEverySpace()
        if newMode == .floating { orderFront(nil) } else { orderBack(nil) }
    }

    func applyMode() {
        // `.normal` even in widget mode: AppKit routes events by the level it has been told, so
        // anything lower here is inert. Only the server level goes down — see `pinBelowWindows`.
        level = mode == .floating ? .floating : .normal

        // `.canJoinAllSpaces` makes a window an all-Spaces floater belonging to no Space's
        // z-order, so the window server composites it at the front of its level on every switch.
        // Only `floating` wants that, since arriving on top is correct there. The other modes get
        // real per-Space membership through SkyLight instead — see `joinEverySpace()`.
        collectionBehavior = mode == .floating
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle]
            : [.stationary, .ignoresCycle]

        pinBelowWindows()
        trace("mode=\(mode.rawValue) appKitLevel=\(level.rawValue)")
    }

    /// Shown at the back so launching does not throw the machine over whatever you are working in.
    func show() {
        orderBack(nil)
        joinEverySpace()
    }

    /// Pushes the *window server* level down without telling AppKit, so the panel composites
    /// below everything while AppKit keeps routing mouse events to it as a `.normal` window.
    ///
    /// Re-applied after every reorder: AppKit re-declares its own level whenever it orders the
    /// window, which otherwise raises the panel back above everything on the first click.
    private func pinBelowWindows() {
        guard Self.usesSkyLight, windowNumber > 0 else { return }

        let target = mode == .widget
            ? Int32(CGWindowLevelForKey(.desktopIconWindow)) + 1
            : Int32(level.rawValue)

        SkyLight.setLevel(target, forWindow: windowNumber)
        SkyLight.addEventMask(SkyLight.mouseEventMask, forWindow: windowNumber)
    }

    /// Correcting the level here, inside AppKit's own ordering call, keeps it in the same
    /// window-server round trip. Deferring it by even one runloop turn is visible as a blink.
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        if mode == .widget { pinBelowWindows() }
    }

    /// Makes the window a genuine member of every Space, rather than the all-Spaces floater
    /// `.canJoinAllSpaces` produces. A member has a z-order slot inside each Space, so switching
    /// Space is not an "arrival" and the window server has no reason to composite it on top.
    ///
    /// Idempotent, and re-run whenever the Space layout may have changed — Spaces can be created
    /// and destroyed at any time, and a brand new one will not contain the window.
    func joinEverySpace() {
        guard Self.usesSkyLight, mode != .floating, windowNumber > 0 else { return }

        // Ordinary Spaces only. A fullscreen app owns its Space, and `.canJoinAllSpaces` does not
        // put windows there either — matching that keeps behaviour unsurprising.
        let user = userSpaceIDs()
        SkyLight.add(window: windowNumber, to: user)
        joinedSpaces = Set(user)
        trace("joined \(SkyLight.spaces(forWindow: windowNumber).count) of \(user.count) spaces")
    }

    private func userSpaceIDs() -> [UInt64] {
        SkyLight.allSpaces().filter(\.isUserSpace).map(\.id)
    }

    /// The Spaces the window was last added to.
    private var joinedSpaces: Set<UInt64> = []

    /// Called after every Space switch.
    ///
    /// Membership is only re-asserted when the Space layout actually changed. Re-adding the
    /// window on every switch is needless churn, and `SLSAddWindowsToSpaces` appears to prompt
    /// the window server to re-composite — which showed up as an intermittent blink on top,
    /// intermittent because it raced whatever else was reordering during the transition.
    ///
    /// The widget level is re-asserted unconditionally: a Space transition is exactly when AppKit
    /// is most likely to have re-declared its own level behind our back.
    func spaceDidChange() {
        guard Self.usesSkyLight, windowNumber > 0 else { return }

        if mode != .floating, Set(userSpaceIDs()) != joinedSpaces {
            trace("space layout changed, rejoining")
            joinEverySpace()
        }
        if mode == .widget { pinBelowWindows() }
    }

    // MARK: - Diagnostics

    /// `DESKTOPCASINO_DEBUG=1` traces placement and which mouse events reach the panel. Worth
    /// keeping: a window silently losing clicks looks exactly like a broken button.
    private static let tracing = ProcessInfo.processInfo.environment["DESKTOPCASINO_DEBUG"] != nil

    private func trace(_ message: @autoclosure () -> String) {
        guard Self.tracing else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            trace("mouseDown at \(event.locationInWindow)")
        }
        super.sendEvent(event)

        // The click-raise does not always route through `order(_:relativeTo:)`, so re-assert the
        // server level at both ends of a click too. Cheap, and a no-op when nothing changed.
        if mode == .widget, event.type == .leftMouseDown || event.type == .leftMouseUp {
            pinBelowWindows()
        }
    }

    // MARK: - Placement

    func restorePosition() {
        if let stored = UserDefaults.standard.string(forKey: Self.originKey) {
            setFrameOrigin(NSPointFromString(stored))
        } else {
            setFrameOrigin(defaultOrigin())
        }
        moveOnScreenIfNeeded()
    }

    func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }

    /// A display can be unplugged or resized out from under us; `.canJoinAllSpaces`
    /// covers Spaces, not screens.
    func moveOnScreenIfNeeded() {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !visible { setFrameOrigin(defaultOrigin()) }
    }

    /// The app is never active, so without this the first click into the panel is swallowed
    /// as an activation click instead of reaching the button under the cursor.
    private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        required init(rootView: Content) { super.init(rootView: rootView) }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }
    }

    private func defaultOrigin() -> NSPoint {
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: area.maxX - Self.size.width - Self.margin,
            y: area.minY + Self.margin
        )
    }
}
