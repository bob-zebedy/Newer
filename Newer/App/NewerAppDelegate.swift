import AppKit

final class NewerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _: NSApplication
    ) -> Bool {
        true
    }
}
