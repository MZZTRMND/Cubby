import SwiftUI
import SwiftData

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        MenuBarExtra("Shelf", systemImage: "tray") {
            MenuContent()
                .environment(app.store)
                .environment(app.panel)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let store: ShelfStore
    let panel: PanelController

    override init() {
        let config = ModelConfiguration(url: AppPaths.store)
        container = try! ModelContainer(for: ShelfItem.self, configurations: config)
        store = ShelfStore(context: container.mainContext)
        panel = PanelController(store: store, container: container)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.showAtLaunch()
    }
}

private struct MenuContent: View {
    @Environment(ShelfStore.self) private var store
    @Environment(PanelController.self) private var panel

    var body: some View {
        @Bindable var panel = panel
        Button(panel.isShown ? "Hide Shelf" : "Show Shelf") { panel.isShown.toggle() }
        Toggle("Keep on Top", isOn: $panel.keepOnTop)
        Divider()
        if store.canUndoClear {
            Button("Undo Clear") { store.undoClear() }
        } else {
            Button("Clear") { store.clear() }
        }
        Divider()
        Button("Quit Shelf") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
