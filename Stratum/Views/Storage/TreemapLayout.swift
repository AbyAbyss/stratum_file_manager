import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing, van Wijk).
/// Pure geometry: no SwiftUI, no state, so it can be unit-tested.
enum TreemapLayout {
    /// Returns one rect per weight, in input order. Weights must be sorted
    /// descending for the best aspect ratios; non-positive weights get `.zero`.
    static func rects(for weights: [Double], in bounds: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: weights.count)
        let total = weights.filter { $0 > 0 }.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return result }

        let scale = Double(bounds.width * bounds.height) / total
        let areas = weights.map { max(0, $0) * scale }
        let count = areas.firstIndex(where: { $0 <= 0 }) ?? areas.count

        var remaining = bounds
        var start = 0
        while start < count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var best = worstRatio(areas[start..<end], side: side)
            while end < count {
                let candidate = worstRatio(areas[start...end], side: side)
                if candidate > best { break }
                best = candidate
                end += 1
            }
            remaining = place(areas[start..<end], offset: start, in: remaining, into: &result)
            start = end
        }
        return result
    }

    private static func worstRatio(_ row: ArraySlice<Double>, side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0, let lo = row.min(), let hi = row.max(), lo > 0 else { return .infinity }
        return max(side * side * hi / (sum * sum), sum * sum / (side * side * lo))
    }

    /// Lays one row along the shorter side of `rect` and returns the leftover rect.
    private static func place(
        _ row: ArraySlice<Double>,
        offset: Int,
        in rect: CGRect,
        into result: inout [CGRect]
    ) -> CGRect {
        let sum = row.reduce(0, +)
        var cursor: CGFloat = 0

        if rect.width >= rect.height {
            let thickness = CGFloat(sum) / rect.height
            for (i, area) in row.enumerated() {
                let length = CGFloat(area) / thickness
                result[offset + i] = CGRect(x: rect.minX, y: rect.minY + cursor, width: thickness, height: length)
                cursor += length
            }
            return CGRect(x: rect.minX + thickness, y: rect.minY, width: max(0, rect.width - thickness), height: rect.height)
        } else {
            let thickness = CGFloat(sum) / rect.width
            for (i, area) in row.enumerated() {
                let length = CGFloat(area) / thickness
                result[offset + i] = CGRect(x: rect.minX + cursor, y: rect.minY, width: length, height: thickness)
                cursor += length
            }
            return CGRect(x: rect.minX, y: rect.minY + thickness, width: rect.width, height: max(0, rect.height - thickness))
        }
    }
}
