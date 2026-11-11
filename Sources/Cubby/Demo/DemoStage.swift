import AppKit
import SwiftUI

/// Everything the demo's stage and pointer show, in screen points from the top left.
@MainActor @Observable
final class DemoState {
    struct DeskIcon: Identifiable {
        let id: String
        let name: String
        let url: URL
        let image: NSImage
        var center: CGPoint
        var isGone = false
    }

    enum CursorKind { case arrow, hand }

    var pointer = CGPoint(x: -100, y: -100)
    var isPressed = false
    var cursor: CursorKind = .arrow
    var showsPointer = true

    var icons: [DeskIcon] = []
    var selectedIcon: String?

    /// What's being dragged, under the pointer.
    var ghost: NSImage?
    var ghostSize = CGSize(width: 80, height: 80)
    var ghostOpacity = 0.85

    /// The screenshot thumbnail: where it is, how big and how faded.
    var shot: NSImage?
    var shotCenter = CGPoint.zero
    var shotScale = 1.0
    var shotOpacity = 1.0
    var flash = 0.0

    var selectsText = false
    var notesImage: NSImage?
}

// MARK: - Backdrop: the wallpaper and the files on the desktop

struct DemoBackdrop: View {
    @Environment(DemoState.self) private var state

    var body: some View {
        ZStack(alignment: .topLeading) {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                Color(red: 0.16, green: 0.32, blue: 0.86), Color(red: 0.42, green: 0.3, blue: 0.9), Color(red: 0.86, green: 0.36, blue: 0.7),
                Color(red: 0.26, green: 0.5, blue: 0.98), Color(red: 0.66, green: 0.56, blue: 0.98), Color(red: 1.0, green: 0.5, blue: 0.52),
                Color(red: 0.36, green: 0.26, blue: 0.78), Color(red: 0.9, green: 0.42, blue: 0.62), Color(red: 1.0, green: 0.64, blue: 0.36),
            ])
            .ignoresSafeArea()
            ForEach(state.icons) { icon in
                DeskIconView(icon: icon, isSelected: state.selectedIcon == icon.id)
                    .position(icon.center)
                    .opacity(icon.isGone ? 0 : 1)
                    .scaleEffect(icon.isGone ? 0.8 : 1)
                    .animation(.easeOut(duration: 0.2), value: icon.isGone)
            }
        }
    }
}

/// A file on the desktop, as Finder draws it: the icon and its name under it.
private struct DeskIconView: View {
    let icon: DemoState.DeskIcon
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon.image)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .padding(3)
                .background(isSelected ? Color.black.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
            Text(icon.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(isSelected ? 0 : 0.5), radius: 2, y: 1)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: 110)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Overlay: the pointer, what it carries, the screenshot

struct DemoOverlay: View {
    @Environment(DemoState.self) private var state

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let shot = state.shot {
                Image(nsImage: shot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
                    .scaleEffect(state.shotScale)
                    .opacity(state.shotOpacity)
                    .position(state.shotCenter)
            }
            if let ghost = state.ghost {
                Image(nsImage: ghost)
                    .resizable()
                    .scaledToFit()
                    .frame(width: state.ghostSize.width, height: state.ghostSize.height)
                    .opacity(state.ghostOpacity)
                    .position(x: state.pointer.x, y: state.pointer.y + 6)
            }
            if state.showsPointer {
                cursor
            }
            Color.white.opacity(state.flash).allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// The system's own pointer images, drawn where the demo's pointer is.
    private var cursor: some View {
        let system = state.cursor == .hand ? NSCursor.pointingHand : NSCursor.arrow
        let size = system.image.size
        return Image(nsImage: system.image)
            .frame(width: size.width, height: size.height)
            .scaleEffect(state.isPressed ? 0.88 : 1, anchor: UnitPoint(x: system.hotSpot.x / size.width, y: system.hotSpot.y / size.height))
            .animation(.easeOut(duration: 0.08), value: state.isPressed)
            .offset(x: state.pointer.x - system.hotSpot.x, y: state.pointer.y - system.hotSpot.y)
    }
}

// MARK: - The other apps' windows

/// A window's frame, drawn rather than real: macOS badges titled windows while they're
/// recorded.
struct DemoChrome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                        Circle().fill($0).frame(width: 13, height: 13)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 19)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
            .padding(40)
            .shadow(color: .black.opacity(0.28), radius: 30, y: 16)
    }
}

private struct ArtTile: View {
    let art: DemoArt
    var body: some View {
        art.view.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MoodboardContent: View {
    static let palette: [Color] = [
        Color(red: 1, green: 0.42, blue: 0.37), Color(red: 1, green: 0.7, blue: 0.4), Color(red: 0.48, green: 0.36, blue: 0.98), Color(red: 0.1, green: 0.62, blue: 0.78),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Moodboard").font(.system(size: 26, weight: .bold))
            HStack(spacing: 14) {
                ArtTile(art: .flowers)
                VStack(spacing: 14) {
                    ArtTile(art: .dunes)
                    ArtTile(art: .beach)
                }
            }
            HStack(spacing: 10) {
                ForEach(0..<Self.palette.count, id: \.self) { i in
                    Circle().fill(Self.palette[i]).frame(width: 34, height: 34)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 52)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
    }
}

struct BrowserContent: View {
    @Environment(DemoState.self) private var state
    static let link = "apple.com"
    static let quote = "Keep the things you're working with close at hand."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text(Self.link).font(.system(size: 14))
                }
                .foregroundStyle(.secondary)
                .frame(width: 420, height: 30)
                .background(.fill.tertiary, in: Capsule())
                Spacer()
            }
            .frame(height: 52)
            HStack(alignment: .top, spacing: 32) {
                ArtTile(art: .sunset)
                    .frame(width: 460, height: 345)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Slow mornings by the sea")
                        .font(.system(size: 30, weight: .bold))
                    Text(paragraph)
                    Text("Palette").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
                    HStack(spacing: 10) {
                        ForEach(0..<MoodboardContent.palette.count, id: \.self) { i in
                            Circle().fill(MoodboardContent.palette[i]).frame(width: 34, height: 34)
                        }
                    }
                }
                .font(.system(size: 18))
                .lineSpacing(5)
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .environment(\.colorScheme, .light)
    }

    /// The article's text, with the sentence picked to drag highlighted as selections are.
    private var paragraph: AttributedString {
        var before = AttributedString("A weekend of coffee, salt air and very little else. ")
        before.foregroundColor = .secondary
        var quote = AttributedString(Self.quote)
        if state.selectsText { quote.backgroundColor = Color.accentColor.opacity(0.28) }
        var after = AttributedString(" Then let the rest of the desk go quiet.")
        after.foregroundColor = .secondary
        return before + quote + after
    }
}

struct NotesContent: View {
    @Environment(DemoState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weekend trip").font(.system(size: 28, weight: .bold))
            Text("Leave Saturday, 8 am")
            Text("Pack boots, a warm jacket and snacks")
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)
                if let image = state.notesImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(height: 260)
            .padding(.top, 10)
            .animation(.spring(duration: 0.4, bounce: 0.25), value: state.notesImage != nil)
        }
        .font(.system(size: 18))
        .padding(.horizontal, 32)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 1, green: 0.99, blue: 0.95))
        .environment(\.colorScheme, .light)
    }
}
