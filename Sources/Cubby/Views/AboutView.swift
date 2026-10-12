import SwiftUI

/// The About Cubby window: icon, name, version and a link to the project.
struct AboutView: View {
    static let windowID = "about"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 12)
            Text("Cubby")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text("A little folder that lives on your desktop.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Link("github.com/MZZTRMND/Cubby", destination: URL(string: "https://github.com/MZZTRMND/Cubby")!)
                .font(.callout)
                .padding(.top, 10)
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .frame(width: 300)
        .fixedSize()
    }
}

/// Opens the About window. The menu bar menu doesn't activate the app, so it comes forward
/// first or the window would open behind.
struct AboutButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Cubby") {
            NSApp.activate()
            openWindow(id: AboutView.windowID)
        }
    }
}
