import SwiftUI

/// Cubby's settings: what it catches, when it comes forward, how it looks, whether it's in
/// the Dock, and a way into the Customize window for the folder's look.
struct SettingsView: View {
    @Environment(PanelController.self) private var panel
    @FolderStyleBinding private var style
    @AppStorage(ScreenshotCatcher.enabledKey) private var catchScreenshots = false
    @AppStorage(DragSummon.key) private var dragSummon = DragSummon.shake
    @AppStorage(DockIcon.key) private var showInDock = false

    var body: some View {
        @Bindable var panel = panel
        Form {
            Section {
                Toggle("Catch new screenshots", isOn: $catchScreenshots)
                Picker("Come forward while dragging", selection: $dragSummon) {
                    ForEach(DragSummon.allCases) { Text($0.title) }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("New screenshots move into Cubby instead of landing in \(screenshotFolderName).")
                    Text(dragSummon == .shake
                         ? "Give something you're dragging in another app a quick shake, and Cubby pops up right next to it so you can drop it in."
                         : "When you start dragging something in another app, Cubby pops up right next to it so you can drop it in.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Picker("Appearance", selection: $panel.theme) {
                    ForEach(PanelController.Theme.allCases) { Text($0.title) }
                }
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { DockIcon.apply() }
            } footer: {
                Text("Cubby is always in the menu bar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack(spacing: 14) {
                    MiniFolder(style: style, width: 46)
                        .frame(width: 58, height: 50)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Folder Style")
                        Text(style.theme.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    CustomizeButton()
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Theme and size.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension SettingsView {
    /// "the Desktop", or the folder picked in the Screenshot app.
    var screenshotFolderName: String {
        let folder = ScreenshotCatcher.screenshotFolder()
        if folder.standardizedFileURL == URL.desktopDirectory.standardizedFileURL { return "the Desktop" }
        return FileManager.default.displayName(atPath: folder.path)
    }
}
