import AppKit
import SwiftUI

// Entry point — launches as a menu bar app (no Dock icon)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // hide from Dock

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.and.mic", accessibilityDescription: "WhisKey")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // TODO: initialize HotkeyManager, AudioCapturePipeline, permissions check
    }

    @objc private func togglePopover() {
        // TODO: show/hide SwiftUI popover panel
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
