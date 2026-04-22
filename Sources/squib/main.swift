import AppKit
import Foundation

// Single-instance guard — acquire an exclusive file lock before starting.
// A second launch silently exits if the first instance still holds the lock.
let lockDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".squib")
try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
let lockPath = lockDir.appendingPathComponent("squib.lock").path
let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o666)
guard lockFd >= 0, flock(lockFd, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

let app = NSApplication.shared
// Set accessory policy before run() so NSStatusItem is visible even when
// launched without a proper .app bundle (e.g. `swift run squib`).
// When Info.plist carries LSUIElement=true, this call is a no-op.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
