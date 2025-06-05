import Cocoa

// 1) Grab the shared NSApplication instance
let app = NSApplication.shared

// 2) Instantiate and assign your AppDelegate
let delegate = AppDelegate()
app.delegate = delegate

// 3) Start the run loop
app.run()
