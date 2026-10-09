import SwiftUI
import SwiftData

@main
struct CubbyApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(app.store)
                .environment(app.panel)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("Cubby")
        }
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let store: CubbyStore
    let panel: PanelController

    override init() {
        let config = ModelConfiguration(url: AppPaths.store)
        container = try! ModelContainer(for: CubbyItem.self, configurations: config)
        store = CubbyStore(context: container.mainContext)
        panel = PanelController(store: store, container: container)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.showAtLaunch()
    }

    /// Clicking the Dock icon brings Cubby back if it was hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel.isShown = true
        return false
    }

    /// Right-clicking the Dock icon; macOS adds Quit and the rest below.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let pin = ActionMenuItem("Pin on Top") { [panel] in panel.isPinnedOnTop.toggle() }
        pin.state = panel.isPinnedOnTop ? .on : .off
        menu.addItem(pin)
        return menu
    }
}

private struct MenuContent: View {
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var panel = panel
        Button(panel.isShown ? "Hide Cubby" : "Show Cubby") { panel.isShown.toggle() }
        Picker("Appearance", selection: $panel.theme) {
            ForEach(PanelController.Theme.allCases) { Text($0.title) }
        }
        Divider()
        Button("Settings…") {
            // The menu bar menu doesn't activate the app, so bring it forward or the window opens behind.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Cubby") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
