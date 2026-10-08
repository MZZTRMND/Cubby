import SwiftUI
import SwiftData

@main
struct ShelfApp: App {
    private let container: ModelContainer
    @State private var store: ShelfStore

    init() {
        let config = ModelConfiguration(url: AppPaths.store)
        let container = try! ModelContainer(for: ShelfItem.self, configurations: config)
        self.container = container
        _store = State(initialValue: ShelfStore(context: container.mainContext))
    }

    var body: some Scene {
        MenuBarExtra("Shelf", systemImage: "tray") {
            PopoverView()
                .environment(store)
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
