import Foundation

/// The light map style (specs/osm-map R33). OpenStreetMap's standard tiles are recoloured on the phone into a quiet,
/// near-white map: pale grey land, white roads with grey edges, light blue water, light green parks and dark slate
/// labels. Pure colour maths on sRGB values in 0...1; `TileImages` applies it to each tile through a colour cube.
enum TilePalette {
    /// Edge length of the colour cube: 32³ entries, interpolated between.
    static let cubeSize = 32

    /// OSM's land colour, recoloured: what a tile shows before it or any coarser tile has loaded (R13).
    static let land = recolor(SIMD3<Double>(0xF2, 0xEF, 0xE9) / 255)

    static func recolor(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let (hue, saturation, lightness) = hsl(rgb)
        // Only clearly coloured pixels count as water or park; greys of any hue stay neutral.
        let colourful = smoothstep(0.08, 0.25, saturation)
        let water = band(hue, centre: 200, halfWidth: 35, feather: 15) * colourful
        let park = band(hue, centre: 115, halfWidth: 32, feather: 12) * colourful
        let neutral = max(0, 1 - water - park)
        return neutral * neutralColour(hue: hue, saturation: saturation, lightness: lightness)
            + water * waterColour(hue: hue, saturation: saturation, lightness: lightness)
            + park * parkColour(hue: hue, saturation: saturation, lightness: lightness)
    }

    /// Motorways, trunk and primary roads.
    static let majorRoad = rgb(hue: 42, saturation: 0.9, lightness: 0.85)

    /// RGBA floats for `CIColorCubeWithColorSpace`: red changes fastest, then green, then blue.
    static func cube(size: Int = cubeSize) -> [Float] {
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 4)
        let step = 1 / Double(size - 1)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    let colour = recolor(SIMD3(Double(red), Double(green), Double(blue)) * step)
                    values += [Float(colour.x), Float(colour.y), Float(colour.z), 1]
                }
            }
        }
        return values
    }

    // MARK: Families

    /// Land, buildings, roads, labels and everything warm or grey: slate greys, lifted towards white. Light, strongly
    /// coloured road fills turn white, or pale amber for OSM's pink to orange major roads; their darker edges stay
    /// grey. Labels stay dark.
    private static func neutralColour(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Double> {
        let lift = 0.30 * smoothstep(0.22, 0.50, lightness) + 0.15 * smoothstep(0.55, 0.92, lightness)
        let lifted = lightness + (1 - lightness) * lift
        let roadFill = smoothstep(0.35, 0.75, saturation) * smoothstep(0.62, 0.78, lightness)
        let slate = rgb(hue: 220, saturation: 0.10, lightness: lifted + (1 - lifted) * roadFill)
        // Pale pink and peach areas (shops, offices) are lighter than the major-road fills and stay slate.
        let major = roadFill * band(hue, centre: 10, halfWidth: 28, feather: 10) * (1 - smoothstep(0.86, 0.89, lightness))
        return slate + (majorRoad - slate) * major
    }

    private static func waterColour(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Double> {
        rgb(hue: hue + (205 - hue) * 0.8, saturation: min(saturation * 1.25, 0.62), lightness: lightness + (1 - lightness) * 0.2)
    }

    private static func parkColour(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Double> {
        rgb(hue: hue + (115 - hue) * 0.5, saturation: min(0.22 + saturation * 0.25, 0.45), lightness: lightness + (1 - lightness) * 0.28)
    }

    // MARK: Colour maths

    /// 1 within `halfWidth` degrees of `centre`, fading to 0 over `feather` more degrees.
    private static func band(_ hue: Double, centre: Double, halfWidth: Double, feather: Double) -> Double {
        let distance = abs((hue - centre + 540).truncatingRemainder(dividingBy: 360) - 180)
        return 1 - smoothstep(halfWidth, halfWidth + feather, distance)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func hsl(_ rgb: SIMD3<Double>) -> (hue: Double, saturation: Double, lightness: Double) {
        let high = rgb.max(), low = rgb.min()
        let lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 1e-9 else { return (0, 0, lightness) }
        let saturation = chroma / (1 - abs(2 * lightness - 1))
        let hue: Double
        switch high {
        case rgb.x: hue = 60 * ((rgb.y - rgb.z) / chroma).truncatingRemainder(dividingBy: 6)
        case rgb.y: hue = 60 * ((rgb.z - rgb.x) / chroma + 2)
        default: hue = 60 * ((rgb.x - rgb.y) / chroma + 4)
        }
        return ((hue + 360).truncatingRemainder(dividingBy: 360), min(saturation, 1), lightness)
    }

    static func rgb(hue: Double, saturation: Double, lightness: Double) -> SIMD3<Double> {
        let lightness = min(max(lightness, 0), 1)
        let chroma = (1 - abs(2 * lightness - 1)) * min(max(saturation, 0), 1)
        let sector = ((hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base: SIMD3<Double>
        switch sector {
        case ..<1: base = SIMD3(chroma, second, 0)
        case ..<2: base = SIMD3(second, chroma, 0)
        case ..<3: base = SIMD3(0, chroma, second)
        case ..<4: base = SIMD3(0, second, chroma)
        case ..<5: base = SIMD3(second, 0, chroma)
        default: base = SIMD3(chroma, 0, second)
        }
        return base + SIMD3(repeating: lightness - chroma / 2)
    }
}
