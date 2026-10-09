import SwiftUI

/// Cubby's settings: how big the folder and its items are.
struct SettingsView: View {
    @AppStorage(FolderIcon.folderScaleKey) private var folderScale = 1.0
    @AppStorage(FolderIcon.itemScaleKey) private var itemScale = 1.0

    var body: some View {
        Form {
            Section {
                SizeSlider(title: "Folder", symbol: "folder", range: FolderIcon.folderScaleRange, value: $folderScale)
                SizeSlider(title: "Items", symbol: "doc", range: FolderIcon.itemScaleRange, value: $itemScale)
            } header: {
                Text("Size")
            } footer: {
                HStack {
                    Spacer()
                    Button("Reset") {
                        folderScale = 1
                        itemScale = 1
                    }
                    .disabled(folderScale == 1 && itemScale == 1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
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
