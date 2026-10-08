import SwiftUI

struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Label("Drop or paste", systemImage: "arrow.down")
            .font(.callout)
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isTargeted ? AnyShapeStyle(.tint.opacity(0.1)) : AnyShapeStyle(.clear), in: shape)
            .overlay {
                shape.strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
            .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
