import AppKit
import CasinoKit
import SwiftUI

/// The stats screen, in an ordinary titled window.
///
/// Deliberately *not* another `DesktopPanel`. The machine is a widget you leave lying on the
/// desktop; the ledger is something you open, read and close, and it should behave like every
/// other window while it is up — key, movable, resizable, closable, above whatever is behind it.
///
/// The titlebar is transparent and untitled, so the felt runs to the top of the window and the
/// traffic lights sit on it. The window background is set to the same felt the content starts
/// with, since the strip behind the titlebar is drawn by the window, not by the content view.
@MainActor
@Observable
final class StatsWindowController {
    private let machine: SlotMachine

    /// Run after the window is shown, as insurance rather than a fix for anything observed.
    ///
    /// Widget mode holds `NSWindow.level` at `.normal` and pushes only the *server* level down,
    /// and AppKit re-declares its own level whenever it orders the window — which is why the panel
    /// re-pins itself inside `order(_:relativeTo:)` and on every mouse event. Showing this window
    /// activates the app, which is another way into that same re-declaration.
    ///
    /// Measured on macOS 26.5, it does not appear to be: activating the app moved neither the
    /// panel's server level nor its front-to-back position, sampled every 20ms for three seconds.
    /// The modern `NSApp.activate()` is more conservative than the deprecated
    /// `activate(ignoringOtherApps:)` it replaced. Kept anyway — it is idempotent, runs once per
    /// window open, and the panel demonstrably does need re-pinning on the other AppKit paths.
    private let didActivate: () -> Void

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var closeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var keyMonitor: Any?

    /// Read by the widget's stats button, which stays lit while the window is up.
    private(set) var isOpen = false

    init(machine: SlotMachine, didActivate: @escaping () -> Void) {
        self.machine = machine
        self.didActivate = didActivate
    }

    /// Closing on a second click is only right when the window is the one you are looking at.
    /// If it is open but buried, the click meant "show me" — so bring it forward instead.
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.close()
        } else {
            open()
        }
    }

    func open() {
        let window = self.window ?? makeWindow()
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        installKeyMonitor()

        // After AppKit has finished its own ordering for this activation, not during it.
        Task { didActivate() }
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DesktopCasino Statistics"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Self.felt
        window.isReleasedWhenClosed = false
        // The window outlives being closed, and a Space assignment outlives it too: opened on one
        // Space and reopened from another, it would otherwise come back on the Space it was first
        // opened on, dragging you there. The panel sidesteps this by joining every Space; an
        // ordinary window should follow you to the one you are on instead.
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentMinSize = NSSize(width: 340, height: 380)
        window.contentView = NSHostingView(rootView: StatsScreen(machine: machine))
        window.setFrameAutosaveName("statsWindow")
        // Only when the autosave had nothing to restore, which leaves the frame at the origin.
        if window.frame.origin == .zero { window.center() }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isOpen = false
                self?.removeKeyMonitor()
            }
        }

        return window
    }

    /// The app runs as an accessory, so it has no menu bar and nothing routes ⌘W. Without this
    /// the only way out of the window is the close button, which is a surprise on macOS.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "w",
                  let window = self?.window, window.isKeyWindow
            else { return event }
            window.close()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Wide enough for the 14 chart bars to stay legible, and tall enough to open on the
    /// headline, the tiles and the chart without a scroll. The rest is below the fold.
    private static let contentSize = CGSize(width: 400, height: 680)

    /// `Palette.cardTop` at the opacity `Palette.card()` uses, flattened over black — the exact
    /// colour the content's own gradient starts at, so the titlebar strip is seamless.
    private static let felt = NSColor(srgbRed: 0.04 * 0.85, green: 0.20 * 0.85,
                                      blue: 0.12 * 0.85, alpha: 1)
}
