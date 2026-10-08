import Testing
@testable import Shelf

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
