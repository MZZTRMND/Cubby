import Foundation
import Testing
@testable import Cubby

struct ColorParserTests {
    private func rgba(_ s: String) -> [Double]? {
        ColorParser.parse(s).map { [$0.r, $0.g, $0.b, $0.a].map { ($0 * 1000).rounded() / 1000 } }
    }

    @Test func hex() {
        #expect(rgba("#f00") == [1, 0, 0, 1])
        #expect(rgba("#FF000080") == [1, 0, 0, 0.502])
        #expect(rgba("#00ff00") == [0, 1, 0, 1])
        #expect(rgba("#ggg") == nil)
        #expect(rgba("#12345") == nil)
        #expect(rgba("ff0000") == nil)
    }

    @Test func rgb() {
        #expect(rgba("rgb(255, 0, 0)") == [1, 0, 0, 1])
        #expect(rgba("rgba(0,0,255,0.5)") == [0, 0, 1, 0.5])
        #expect(rgba("rgb(0 100% 0 / 50%)") == [0, 1, 0, 0.5])
        #expect(rgba("rgb(1, 2)") == nil)
    }

    @Test func hsl() {
        #expect(rgba("hsl(0, 100%, 50%)") == [1, 0, 0, 1])
        #expect(rgba("hsl(120deg 100% 50%)") == [0, 1, 0, 1])
        #expect(rgba("hsla(240, 100%, 50%, 0.25)") == [0, 0, 1, 0.25])
    }

    @Test func oklch() throws {
        let red = try #require(ColorParser.parse("oklch(0.628 0.2577 29.23)"))
        #expect(abs(red.r - 1) < 0.01 && red.g < 0.01 && red.b < 0.01)
        let white = try #require(ColorParser.parse("oklch(100% 0 0)"))
        #expect(abs(white.r - 1) < 0.001 && abs(white.g - 1) < 0.001 && abs(white.b - 1) < 0.001)
    }
}

struct ClassifyTests {
    @Test func kinds() {
        #expect(ItemImporter.kind(of: "#fff") == .color)
        #expect(ItemImporter.kind(of: "oklch(0.7 0.1 200)") == .color)
        #expect(ItemImporter.kind(of: "https://apple.com/mac") == .link)
        #expect(ItemImporter.kind(of: "apple.com") == .text)
        #expect(ItemImporter.kind(of: "see https://apple.com") == .text)
        #expect(ItemImporter.kind(of: "rgb is a color model") == .text)
    }
}

struct ColorFormatTests {
    @Test func copiesEachWay() throws {
        let blue = try #require(ColorParser.parse("#3366ff"))
        #expect(ColorFormat.hex.string(for: blue) == "#3366FF")
        #expect(ColorFormat.rgb.string(for: blue) == "rgb(51, 102, 255)")
        #expect(ColorFormat.hsl.string(for: blue) == "hsl(225, 100%, 60%)")
        #expect(ColorFormat.swiftUI.string(for: blue) == "Color(red: 0.2, green: 0.4, blue: 1)")
    }

    @Test func keepsTransparency() throws {
        let red = try #require(ColorParser.parse("rgba(255, 0, 0, 0.5)"))
        #expect(ColorFormat.hex.string(for: red) == "#FF000080")
        #expect(ColorFormat.rgb.string(for: red) == "rgba(255, 0, 0, 0.5)")
        #expect(ColorFormat.hsl.string(for: red) == "hsla(0, 100%, 50%, 0.5)")
        #expect(ColorFormat.swiftUI.string(for: red) == "Color(red: 1, green: 0, blue: 0, opacity: 0.5)")
    }

    @Test func roundTrips() throws {
        for input in ["#7a3e9d", "#00c8a0", "#808080"] {
            let color = try #require(ColorParser.parse(input))
            // HSL is written in whole percents, which can be a shade off.
            for format in [ColorFormat.hex, .rgb] {
                let back = try #require(ColorParser.parse(format.string(for: color)))
                #expect(ColorFormat.hex.string(for: back) == input.uppercased(), "\(format) \(input)")
            }
        }
    }
}

struct ShakeDetectorTests {
    /// Feeds positions 20 ms apart; true if a shake was seen.
    private func shaken(_ xs: [CGFloat], step: TimeInterval = 0.02) -> Bool {
        var detector = ShakeDetector()
        return xs.enumerated().contains { detector.add(x: $1, at: Double($0) * step) }
    }

    /// Back and forth `swings` times by `width` points, in `samples` steps each way.
    private func swings(_ count: Int, width: CGFloat, samples: Int = 4) -> [CGFloat] {
        var xs: [CGFloat] = [0]
        for swing in 0..<count {
            let target: CGFloat = swing.isMultiple(of: 2) ? width : 0
            let from = xs.last!
            xs += (1...samples).map { from + (target - from) * CGFloat($0) / CGFloat(samples) }
        }
        return xs
    }

    @Test func aQuickShakeCounts() {
        #expect(shaken(swings(4, width: 80)))
    }

    @Test func aStraightDragDoesNot() {
        #expect(!shaken(Array(stride(from: 0, through: 800, by: 15))))
    }

    @Test func smallWobblesDoNot() {
        #expect(!shaken(swings(10, width: 12)))
    }

    @Test func slowBackAndForthDoesNot() {
        #expect(!shaken(swings(4, width: 80), step: 0.2))
    }
}
