import SwiftUI

/// Parses CSS-style hex, rgb(), hsl() and oklch() strings into sRGB.
enum ColorParser {
    struct RGBA: Equatable {
        var r, g, b, a: Double
        var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    }

    static func color(_ string: String) -> Color? { parse(string)?.color }

    static func parse(_ string: String) -> RGBA? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") { return hex(s.dropFirst()) }

        guard s.hasSuffix(")"), let open = s.firstIndex(of: "(") else { return nil }
        let function = s[..<open]
        let tokens = s[s.index(after: open)..<s.index(before: s.endIndex)]
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "/" })
            .map(String.init)
        guard tokens.count == 3 || tokens.count == 4 else { return nil }

        var alpha = 1.0
        if tokens.count == 4 {
            guard let a = number(tokens[3], percentOf: 1) else { return nil }
            alpha = a
        }
        // How a percentage maps onto each channel's plain-number range.
        let scales: [Double]
        switch function {
        case "rgb", "rgba": scales = [255, 255, 255]
        case "hsl", "hsla": scales = [1, 100, 100]
        case "oklch": scales = [1, 0.4, 1]
        default: return nil
        }
        let values = zip(tokens, scales).compactMap { number($0, percentOf: $1) }
        guard values.count == 3 else { return nil }
        let (x, y, z) = (values[0], values[1], values[2])

        let rgb: (Double, Double, Double)
        switch function {
        case "rgb", "rgba": rgb = (x / 255, y / 255, z / 255)
        case "hsl", "hsla": rgb = hsl(x, y / 100, z / 100)
        default: rgb = oklch(x, y, z)
        }
        return RGBA(r: clamp(rgb.0), g: clamp(rgb.1), b: clamp(rgb.2), a: clamp(alpha))
    }

    private static func hex(_ digits: Substring) -> RGBA? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        let full = digits.count <= 4 ? String(digits.flatMap { [$0, $0] }) : String(digits)
        guard let value = UInt64(full, radix: 16) else { return nil }
        let hasAlpha = full.count == 8
        let v = hasAlpha ? value : value << 8 | 0xFF
        func channel(_ shift: UInt64) -> Double { Double((v >> shift) & 0xFF) / 255 }
        return RGBA(r: channel(24), g: channel(16), b: channel(8), a: channel(0))
    }

    /// A plain number, a percentage of `percentOf`, or an angle in degrees. `none` is 0.
    private static func number(_ token: String, percentOf scale: Double) -> Double? {
        if token == "none" { return 0 }
        if token.hasSuffix("%") { return Double(token.dropLast()).map { $0 / 100 * scale } }
        if token.hasSuffix("deg") { return Double(token.dropLast(3)) }
        return Double(token)
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let h = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        func f(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        return (f(0), f(8), f(4))
    }

    private static func oklch(_ l: Double, _ c: Double, _ h: Double) -> (Double, Double, Double) {
        let a = c * cos(h * .pi / 180), b = c * sin(h * .pi / 180)
        let l_ = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m_ = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s_ = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
        func gamma(_ x: Double) -> Double { x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
        return (
            gamma(4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_),
            gamma(-1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_),
            gamma(-0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)
        )
    }

    private static func clamp(_ x: Double) -> Double { x.isNaN ? 0 : min(max(x, 0), 1) }
}
