import SwiftUI
import SwiftData

/// The Customize window: a live preview of the folder on the left, and its theme and size
/// on the right. Every change applies to the desktop folder right away.
struct CustomizeView: View {
    static let windowID = "customize"

    @FolderStyleBinding private var style
    @AppStorage(FolderIcon.folderScaleKey) private var folderScale = FolderIcon.defaultFolderScale
    @AppStorage(FolderIcon.itemScaleKey) private var itemScale = 1.0
    @Query(sort: \CubbyItem.addedAt, order: .reverse) private var items: [CubbyItem]
    @Environment(\.dismiss) private var dismiss

    @State private var tab = Tab.theme
    @State private var holdsOpen = false
    @State private var isPlaying = false
    @State private var previewScheme = PreviewScheme.system
    @State private var samples = Self.makeSamples()

    enum Tab: String, CaseIterable, Identifiable {
        case theme, size
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .theme: "paintpalette"
            case .size: "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            preview
                .frame(width: 400)
            Divider()
            inspector
                .frame(width: 380)
        }
        .frame(maxHeight: .infinity)
        // The traffic lights sit over the preview, so both sides use the title bar's room.
        // The frame comes after, so the window is just its content plus the title bar.
        .ignoresSafeArea(edges: .top)
        .frame(height: 572)
    }
}

// MARK: Preview

private extension CustomizeView {
    enum PreviewScheme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var symbol: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }
        var help: String {
            switch self {
            case .system: "Match the system"
            case .light: "Preview in light mode"
            case .dark: "Preview in dark mode"
            }
        }
    }

    var preview: some View {
        PreviewStage(scheme: previewScheme) {
            FolderIcon(items: items.isEmpty ? samples : items, isDropTarget: holdsOpen)
        } controls: {
            HStack(spacing: 10) {
                Picker("State", selection: $holdsOpen) {
                    Text("Resting").tag(false)
                    Text("Open").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .disabled(isPlaying)
                Button {
                    play()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .help("Open and close the folder once")
                .disabled(isPlaying)
                Divider().frame(height: 16)
                Picker("Appearance", selection: $previewScheme) {
                    ForEach(PreviewScheme.allCases) { scheme in
                        Image(systemName: scheme.symbol).help(scheme.help).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
            }
            .controlSize(.small)
        } caption: {
            Text(items.isEmpty ? "Hover the folder to try it. Showing sample items." : "Hover the folder to try it.")
        }
    }

    /// Opens the folder, holds it a moment, and closes it again.
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        Task {
            if holdsOpen {
                holdsOpen = false
                try? await Task.sleep(for: .seconds(0.6))
            }
            holdsOpen = true
            try? await Task.sleep(for: .seconds(1.35))
            holdsOpen = false
            try? await Task.sleep(for: .seconds(0.45))
            isPlaying = false
        }
    }

    /// Stand-ins while the cubby is empty: colors, notes and links, which need no files.
    static func makeSamples() -> [CubbyItem] {
        [(ItemKind.color, "#FF7A59"), (.text, "Weekend\n• farmers market\n• call Sam\n• new plants"),
         (.color, "#4D96FF"), (.link, "https://apple.com"), (.color, "#6BCB77"),
         (.text, "Ideas: a tiny folder that lives on the desktop"), (.color, "#FFD93D"), (.color, "#B983FF"),
         (.text, "Call the dentist on Tuesday"), (.color, "#FF9EC7")]
            .map { CubbyItem(kind: $0.0, text: $0.1) }
    }
}

/// A soft wallpaper with the folder on it and a floating glass bar of controls.
private struct PreviewStage<Content: View, Controls: View, Caption: View>: View {
    let scheme: CustomizeView.PreviewScheme
    @ViewBuilder let content: Content
    @ViewBuilder let controls: Controls
    @ViewBuilder let caption: Caption
    @Environment(\.colorScheme) private var systemScheme

    private var resolved: ColorScheme {
        switch scheme {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        ZStack {
            Wallpaper(isDark: resolved == .dark)
            content
                .environment(\.colorScheme, resolved)
                .offset(y: -16)
            VStack(spacing: 10) {
                Spacer()
                controls
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: Capsule())
                caption
                    .font(.caption)
                    .foregroundStyle(resolved == .dark ? .white.opacity(0.7) : .black.opacity(0.55))
            }
            .padding(.bottom, 18)
        }
        .ignoresSafeArea()
    }
}

/// A pastel mesh in light mode and a deep one in dark mode, so the glass has something
/// to show through.
private struct Wallpaper: View {
    let isDark: Bool

    var body: some View {
        let colors: [Color] = isDark
            ? [.init(red: 0.10, green: 0.11, blue: 0.22), .init(red: 0.16, green: 0.12, blue: 0.30), .init(red: 0.08, green: 0.16, blue: 0.26),
               .init(red: 0.12, green: 0.20, blue: 0.34), .init(red: 0.22, green: 0.16, blue: 0.36), .init(red: 0.10, green: 0.24, blue: 0.30),
               .init(red: 0.07, green: 0.09, blue: 0.18), .init(red: 0.14, green: 0.10, blue: 0.24), .init(red: 0.06, green: 0.12, blue: 0.20)]
            : [.init(red: 0.80, green: 0.88, blue: 1.00), .init(red: 0.93, green: 0.87, blue: 1.00), .init(red: 1.00, green: 0.88, blue: 0.84),
               .init(red: 0.84, green: 0.93, blue: 1.00), .init(red: 0.97, green: 0.93, blue: 0.98), .init(red: 1.00, green: 0.92, blue: 0.86),
               .init(red: 0.86, green: 0.96, blue: 0.95), .init(red: 0.90, green: 0.92, blue: 1.00), .init(red: 0.99, green: 0.95, blue: 0.90)]
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                     colors: colors)
            .animation(.easeInOut(duration: 0.3), value: isDark)
    }
}

// MARK: Inspector

private extension CustomizeView {
    var inspector: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Cubby")
                        .font(.title3.weight(.semibold))
                    Text(style.theme.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: style.theme)
                }
                TabBar(selection: $tab)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 4)

            Group {
                switch tab {
                case .theme: ThemeTab(style: $style)
                case .size: SizeTab(style: $style, folderScale: $folderScale, itemScale: $itemScale)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
            HStack {
                Button("Reset All", role: .destructive) {
                    withAnimation(.snappy) {
                        style = .original
                        folderScale = FolderIcon.defaultFolderScale
                        itemScale = 1
                    }
                }
                .disabled(style == .original && folderScale == FolderIcon.defaultFolderScale && itemScale == 1)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(.background)
    }
}

/// Four equal tabs with an icon over the title, like a toolbar.
private struct TabBar: View {
    @Binding var selection: CustomizeView.Tab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CustomizeView.Tab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(height: 18)
                        Text(tab.title)
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.tint.opacity(0.12))
                                .matchedGeometryEffect(id: "tab", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

// MARK: Theme

private struct ThemeTab: View {
    @Binding var style: FolderStyle

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: Self.columns, spacing: 12) {
                    ForEach(FolderStyle.Theme.allCases) { theme in
                        ThemeCard(theme: theme, style: style, isSelected: style.theme == theme) {
                            withAnimation(.snappy) { style.theme = theme }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            } footer: {
                Text("Every theme follows light and dark mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A theme as a little folder with its name.
private struct ThemeCard: View {
    let theme: FolderStyle.Theme
    let style: FolderStyle
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                MiniFolder(style: { var s = style; s.theme = theme; return s }(), width: 44)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(.fill.quaternary.opacity(isHovered ? 1.6 : 1),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
                    }
                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// A small, static drawing of the folder in a style, for themes and Settings.
struct MiniFolder: View {
    let style: FolderStyle
    var width: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let s = width / 144
        let front = FolderFrontShape(topRadius: 6 * s, bottomRadius: 11 * s, taper: 5.5 * s)
        ZStack(alignment: .bottom) {
            FolderBack(style: style, scale: s)
                .frame(width: 132 * s, height: 104 * s)
                .padding(.bottom, 4 * s)
            RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                .fill(style.page)
                .frame(width: 105 * s, height: 77 * s)
                .padding(.bottom, 11 * s)
            front
                .fill(.ultraThinMaterial)
                .overlay {
                    front.fill(style.theme.tint.map { $0.opacity(style.theme.tintAmount + 0.2) }
                               ?? .white.opacity(colorScheme == .dark ? 0.08 : 0.3))
                }
                .overlay { front.stroke(.white.opacity(0.5), lineWidth: 0.5) }
                .frame(width: width, height: 78 * s)
        }
        .frame(width: width, height: 108 * s, alignment: .bottom)
    }
}

// MARK: Size

private struct SizeTab: View {
    @Binding var style: FolderStyle
    @Binding var folderScale: Double
    @Binding var itemScale: Double

    var body: some View {
        Form {
            Section("Size") {
                StyleSlider(title: "Folder", value: $folderScale, in: FolderIcon.folderScaleRange, format: .percent)
                StyleSlider(title: "Items", value: $itemScale, in: FolderIcon.itemScaleRange, format: .percent)
            }
            Section {
                StyleSlider(title: "Items shown", value: Binding(
                    get: { Double(style.itemCount) },
                    set: { style.itemCount = Int($0.rounded()) }
                ), in: 1...Double(FolderStyle.maxItems), step: 1, format: .count)
            } header: {
                Text("Pile")
            } footer: {
                ResetFooter(note: "How many of the newest items peek out of the folder.",
                            isDisabled: folderScale == FolderIcon.defaultFolderScale && itemScale == 1
                                && style.itemCount == FolderStyle.original.itemCount) {
                    folderScale = FolderIcon.defaultFolderScale
                    itemScale = 1
                    style.itemCount = FolderStyle.original.itemCount
                }
            }
        }
    }
}

// MARK: Controls

/// A title and value over a full-width slider.
private struct StyleSlider: View {
    enum Format { case percent, count }

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: Format

    init(title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil,
         format: Format) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step) { Text(title) }
                } else {
                    Slider(value: $value, in: range) { Text(title) }
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var formatted: String {
        switch format {
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .count: "\(Int(value.rounded()))"
        }
    }
}

/// A short note and a Reset button under a tab's last section.
private struct ResetFooter: View {
    let note: String
    let isDisabled: Bool
    let reset: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset") { withAnimation(.snappy) { reset() } }
                .controlSize(.small)
                .disabled(isDisabled)
        }
    }
}

/// Opens the Customize window, bringing the app forward first.
struct CustomizeButton: View {
    var title = "Customize…"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            NSApp.activate()
            openWindow(id: CustomizeView.windowID)
        }
    }
}
