import SwiftUI

/// How the desktop folder looks, set in the Customize window. Stored as JSON
/// under `key`; anything missing from the stored copy falls back to the default, so new
/// settings never wipe old ones.
struct FolderStyle: Codable, Equatable {
    static let key = "folderStyle"

    var theme = Theme.original
    /// How many of the newest items stand in the folder.
    var itemCount = 8

    static let original = FolderStyle()
    static let maxItems = 10
}

extension FolderStyle {
    /// The folder's colors. Every theme has a light and a dark version, so it follows the
    /// system appearance.
    enum Theme: String, Codable, CaseIterable, Identifiable {
        case original, ocean, mint, lavender, blush, sunset, paper, graphite
        var id: Self { self }

        var name: String { rawValue.capitalized }

        /// The back's color; nil uses the system fills.
        var back: Color? {
            switch self {
            case .original: nil
            case .ocean: .adaptive(light: (0.27, 0.58, 0.95), dark: (0.16, 0.38, 0.72))
            case .mint: .adaptive(light: (0.30, 0.76, 0.62), dark: (0.15, 0.50, 0.40))
            case .lavender: .adaptive(light: (0.58, 0.52, 0.93), dark: (0.36, 0.31, 0.68))
            case .blush: .adaptive(light: (0.95, 0.56, 0.64), dark: (0.68, 0.30, 0.39))
            case .sunset: .adaptive(light: (0.98, 0.60, 0.28), dark: (0.74, 0.38, 0.14))
            case .paper: .adaptive(light: (0.92, 0.89, 0.82), dark: (0.36, 0.34, 0.31))
            case .graphite: .adaptive(light: (0.22, 0.22, 0.24), dark: (0.12, 0.12, 0.13))
            }
        }

        /// The page standing behind the items: light in light mode, a muted shade of the
        /// back in dark mode.
        var page: Color {
            switch self {
            case .original: .adaptive(light: (1, 1, 1), dark: (0.36, 0.36, 0.36))
            case .ocean: .adaptive(light: (1, 1, 1), dark: (0.32, 0.43, 0.58))
            case .mint: .adaptive(light: (1, 1, 1), dark: (0.30, 0.47, 0.42))
            case .lavender: .adaptive(light: (1, 1, 1), dark: (0.42, 0.40, 0.57))
            case .blush: .adaptive(light: (1, 1, 1), dark: (0.55, 0.40, 0.44))
            case .sunset: .adaptive(light: (1, 0.99, 0.96), dark: (0.56, 0.44, 0.35))
            case .paper: .adaptive(light: (1, 0.99, 0.96), dark: (0.50, 0.48, 0.44))
            case .graphite: .adaptive(light: (0.42, 0.42, 0.44), dark: (0.26, 0.26, 0.27))
            }
        }

        /// A wash of color over the glass front; nil leaves it clear.
        var tint: Color? {
            switch self {
            case .original: nil
            case .ocean: .adaptive(light: (0.40, 0.68, 0.98), dark: (0.18, 0.40, 0.74))
            case .mint: .adaptive(light: (0.52, 0.88, 0.76), dark: (0.16, 0.46, 0.38))
            case .lavender: .adaptive(light: (0.72, 0.68, 0.98), dark: (0.34, 0.30, 0.64))
            case .blush: .adaptive(light: (1, 0.74, 0.79), dark: (0.62, 0.30, 0.38))
            case .sunset: .adaptive(light: (1, 0.76, 0.48), dark: (0.68, 0.38, 0.16))
            case .paper: .adaptive(light: (0.98, 0.96, 0.90), dark: (0.40, 0.38, 0.34))
            case .graphite: .black
            }
        }

        var tintAmount: Double {
            switch self {
            case .paper: 0.4
            case .graphite: 0.35
            default: 0.3
            }
        }
    }

    var page: Color { theme.page }

    /// Clear glass, so the items and page show through, washed with the theme's tint.
    var frontGlass: Glass {
        guard let tint = theme.tint else { return .clear }
        return .clear.tint(tint.opacity(theme.tintAmount))
    }
}

private extension Color {
    /// One color in light mode and another in dark mode, as sRGB.
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
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
