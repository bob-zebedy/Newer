import SwiftUI

@main
struct NewerApp: App {
    @NSApplicationDelegateAdaptor(NewerAppDelegate.self) private var appDelegate
    @StateObject private var model = TemplateSettingsModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 680, idealWidth: 720, minHeight: 500, idealHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 540)
    }
}
