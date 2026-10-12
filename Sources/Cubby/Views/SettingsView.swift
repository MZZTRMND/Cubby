import SwiftUI

/// Cubby's settings: what it catches, when it comes forward, and how big the folder and
/// its items are.
struct SettingsView: View {
    @AppStorage(FolderIcon.folderScaleKey) private var folderScale = FolderIcon.defaultFolderScale
    @AppStorage(FolderIcon.itemScaleKey) private var itemScale = 1.0
    @AppStorage(ScreenshotCatcher.enabledKey) private var catchScreenshots = false
    @AppStorage(DragSummon.key) private var dragSummon = DragSummon.shake

    var body: some View {
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
                         ? "Give something you're dragging in another app a quick shake, and Cubby comes to the middle of the screen so you can drop it in."
                         : "When you start dragging something in another app, Cubby comes to the middle of the screen so you can drop it in.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                SizeSlider(title: "Folder", symbol: "folder", range: FolderIcon.folderScaleRange, value: $folderScale)
                SizeSlider(title: "Items", symbol: "doc", range: FolderIcon.itemScaleRange, value: $itemScale)
            } header: {
                Text("Size")
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset") {
                        folderScale = FolderIcon.defaultFolderScale
                        itemScale = 1
                    }
                    .disabled(folderScale == FolderIcon.defaultFolderScale && itemScale == 1)
                }
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

private struct SizeSlider: View {
    let title: String
    let symbol: String
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                Slider(value: $value, in: range) {
                    Text(title)
                } minimumValueLabel: {
                    Image(systemName: symbol).imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: symbol).imageScale(.large)
                }
                .labelsHidden()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
