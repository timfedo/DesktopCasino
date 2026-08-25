import AppKit

let app = NSApplication.shared

if Snapshot.writeIfRequested() { exit(0) }

let delegate = AppDelegate()
app.delegate = delegate

// Accessory: no Dock tile, no menu bar. The panel is the entire UI.
app.setActivationPolicy(.accessory)
app.run()
