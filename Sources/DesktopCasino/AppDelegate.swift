import AppKit
import CasinoKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let machine = SlotMachine()
    private var panel: DesktopPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelRef = PanelRef()
        let panel = DesktopPanel(content: CasinoView(machine: machine, panelRef: panelRef))
        panelRef.panel = panel
        panel.restorePosition()
        panel.show()
        self.panel = panel

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panel?.moveOnScreenIfNeeded() }
        }

        // Handled synchronously rather than through a `Task` hop: this notification already
        // arrives late, after the transition has finished, so every extra runloop turn widens
        // the window in which the panel can be seen on top.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.spaceDidChange() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panel?.savePosition()
        // Credits are debited when a spin starts and only credited back when it resolves ~2.3s
        // later. Quitting inside that window would otherwise persist the debit with no payout.
        machine.refundUnresolvedSpin()
        machine.save()
    }
}
