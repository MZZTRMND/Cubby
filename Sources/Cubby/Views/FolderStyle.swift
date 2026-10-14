import SwiftUI

/// How the desktop folder looks, set in the Customize window. Stored as JSON
/// under `key`; anything missing from the stored copy falls back to the default, so new
/// settings never wipe old ones.
struct FolderStyle: Codable, Equatable {
    static let key = "folderStyle"

    // MARK: Color

    /// The back's color; nil uses the system colors, which follow light and dark mode.
    var backColor: RGBA?
    /// The page standing behind the items; nil is white, or gray in dark mode.
    var pageColor: RGBA?
    var showsPage = true
    /// A wash of color over the glass front, and how strong it is.
    var glassTint: RGBA?
    var glassTintAmount = 0.3
    /// Regular glass instead of clear: blurrier, so the items show through less.
    var isFrosted = false

    // MARK: Items

    var itemCount = 8

    static let original = FolderStyle()
    static let maxItems = 10

}

extension FolderStyle {
    /// Ready-made color sets.
    struct Palette: Identifiable {
        let name: String
        let back: RGBA?
        let page: RGBA?
        let tint: RGBA?
        var tintAmount = 0.3
        var id: String { name }

        static let all: [Palette] = [
            Palette(name: "Original", back: nil, page: nil, tint: nil),
            Palette(name: "Ocean", back: RGBA(0.27, 0.58, 0.95), page: RGBA(1, 1, 1), tint: RGBA(0.40, 0.68, 0.98)),
            Palette(name: "Mint", back: RGBA(0.30, 0.76, 0.62), page: RGBA(1, 1, 1), tint: RGBA(0.52, 0.88, 0.76)),
            Palette(name: "Lavender", back: RGBA(0.58, 0.52, 0.93), page: RGBA(1, 1, 1), tint: RGBA(0.72, 0.68, 0.98)),
            Palette(name: "Blush", back: RGBA(0.95, 0.56, 0.64), page: RGBA(1, 1, 1), tint: RGBA(1, 0.74, 0.79)),
            Palette(name: "Sunset", back: RGBA(0.98, 0.60, 0.28), page: RGBA(1, 0.99, 0.96), tint: RGBA(1, 0.76, 0.48)),
            Palette(name: "Paper", back: RGBA(0.92, 0.89, 0.82), page: RGBA(1, 0.99, 0.96), tint: RGBA(0.98, 0.96, 0.90), tintAmount: 0.4),
            Palette(name: "Graphite", back: RGBA(0.22, 0.22, 0.24), page: RGBA(0.42, 0.42, 0.44), tint: RGBA(0, 0, 0), tintAmount: 0.35),
        ]
    }

    func uses(_ palette: Palette) -> Bool {
        backColor == palette.back && pageColor == palette.page && glassTint == palette.tint
            && (palette.tint == nil || glassTintAmount == palette.tintAmount)
    }

    mutating func apply(_ palette: Palette) {
        backColor = palette.back
        pageColor = palette.page
        glassTint = palette.tint
        glassTintAmount = palette.tintAmount
    }

    var paletteName: String { Palette.all.first(where: uses)?.name ?? "Custom" }

    mutating func resetColor() {
        apply(Palette.all[0])
        showsPage = Self.original.showsPage
        isFrosted = Self.original.isFrosted
    }


    var isOriginalColor: Bool { uses(Palette.all[0]) && showsPage && !isFrosted }
}

// MARK: Storage

extension FolderStyle {
    /// Reads the stored style, filling in defaults for anything it doesn't have.
    init(json: String) {
        guard let stored = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(FolderStyle())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: base.merging(stored) { $1 }),
              let style = try? JSONDecoder().decode(FolderStyle.self, from: merged)
        else { self.init(); return }
        self = style
    }

    var json: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

/// A color that can be saved: sRGB components.
struct RGBA: Codable, Equatable, Hashable {
    var red, green, blue: Double
    var alpha = 1.0

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

extension FolderStyle {
    /// The page: the chosen color, or white in light mode and gray in dark mode.
    var page: Color {
        pageColor?.color ?? Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.36, alpha: 1) : .white
        })
    }

    var frontGlass: Glass {
        let glass: Glass = isFrosted ? .regular : .clear
        guard let glassTint else { return glass }
        return glass.tint(glassTint.color.opacity(glassTintAmount))
    }
}

/// Reads and writes the stored style as a binding, for views that edit it.
@propertyWrapper
struct FolderStyleBinding: DynamicProperty {
    @AppStorage(FolderStyle.key) private var json = ""

    var wrappedValue: FolderStyle {
        get { FolderStyle(json: json) }
        nonmutating set { json = newValue == .original ? "" : newValue.json }
    }

    var projectedValue: Binding<FolderStyle> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
