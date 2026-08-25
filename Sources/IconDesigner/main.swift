import AppKit
import SwiftUI

@MainActor
final class DesignerDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DesktopCasino Icon Designer"
        window.contentView = NSHostingView(rootView: DesignerView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared

// `IconDesigner --render <dir>` writes the default icon without opening the window, which keeps
// the artwork checkable from a script.
if let flag = CommandLine.arguments.firstIndex(of: "--render"),
   flag + 1 < CommandLine.arguments.count {
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    do {
        let config = IconConfig()
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failure: Error?
        Task { @MainActor in
            do {
                print(try await IconExport.write(config, to: directory))
                let tally = IconArtwork(config: config).symbolTally()
                print("symbols: " + tally.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
            } catch {
                failure = error
            }
            semaphore.signal()
        }
        // The render is async now, so pump the main runloop until it finishes.
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        if let failure {
            FileHandle.standardError.write(Data("render failed: \(failure)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

let delegate = DesignerDelegate()
app.delegate = delegate

// A real app, unlike the casino: it needs a menu bar and focus to drive the sliders.
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
