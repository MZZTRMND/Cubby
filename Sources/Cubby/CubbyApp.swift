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
                .environment(app.panel)
        }
        Window("Customize Cubby", id: CustomizeView.windowID) {
            CustomizeView()
                .modelContainer(app.container)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        Window("About Cubby", id: AboutView.windowID) {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutButton() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let store: CubbyStore
    let panel: PanelController
    let screenshots = ScreenshotCatcher()

    override init() {
        let config = ModelConfiguration(url: AppPaths.store)
        container = try! ModelContainer(for: CubbyItem.self, configurations: config)
        store = CubbyStore(context: container.mainContext)
        panel = PanelController(store: store, container: container)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        DockIcon.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.showAtLaunch()
        screenshots.onCatch = { [store, panel] url in
            store.addScreenshot(url)
            panel.caught()
        }
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

/// Whether Cubby shows in the Dock and ⌘-Tab. Off by default: the folder and the menu bar
/// icon are the way in.
enum DockIcon {
    static let key = "showInDock"

    static var isShown: Bool { UserDefaults.standard.bool(forKey: key) }

    static func apply() {
        NSApp.setActivationPolicy(isShown ? .regular : .accessory)
        // Leaving the Dock deactivates the app, which would drop Settings behind other windows.
        NSApp.activate()
    }
}

private struct MenuContent: View {
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(panel.isShown ? "Hide Cubby" : "Show Cubby") { panel.isShown.toggle() }
        Divider()
        AboutButton()
        Button("Settings…") {
            // The menu bar menu doesn't activate the app, so bring it forward or the window opens behind.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Cubby") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
