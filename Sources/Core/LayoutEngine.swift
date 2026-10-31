import CoreGraphics
import Foundation

/// A small, pure layout engine. Everything is expressed in the top-left-origin
/// coordinate space that the Accessibility API uses.
enum LayoutEngine {
    struct Input {
        var bounds: CGRect
        var count: Int
        var ratio: CGFloat
        var gap: CGFloat
        var isUltrawide: Bool
        var isVertical: Bool
    }

    private enum Axis { case horizontal, vertical }

    static func frames(for layout: LayoutKind, input: Input) -> [CGRect] {
        let count = max(1, input.count)
        let ratio = min(0.75, max(0.34, input.ratio))
        let gap = max(0, min(32, input.gap))
        let bounds = input.bounds.standardized
        guard bounds.width > 40, bounds.height > 40 else { return Array(repeating: bounds, count: count) }

        let content = bounds.insetBy(dx: gap, dy: gap)
        guard content.width > 20, content.height > 20 else { return Array(repeating: bounds, count: count) }

        switch layout {
        case .grid:
            return gridFrames(content, count: count, ratio: ratio, gap: gap, vertical: input.isVertical)
        case .columns:
            return columnsFrames(content, count: count, ratio: ratio, gap: gap)
        case .rows:
            return rowsFrames(content, count: count, ratio: ratio, gap: gap)
        case .side:
            return sideFrames(content, count: count, ratio: ratio, gap: gap,
                              ultrawide: input.isUltrawide, vertical: input.isVertical)
        case .bento:
            return bentoFrames(content, count: count, gap: gap)
        }
    }

    // MARK: - Grid

    private static func gridFrames(_ rect: CGRect, count: Int, ratio: CGFloat, gap: CGFloat, vertical: Bool) -> [CGRect] {
        if vertical {
            if count == 1 { return [rect] }
            if count == 2 { return split(rect, axis: .vertical, weights: [ratio, 1 - ratio], gap: gap) }
            if count == 3 {
                let rows = split(rect, axis: .vertical, weights: [ratio, 1 - ratio], gap: gap)
                return [rows[0]] + split(rows[1], axis: .horizontal, weights: [0.5, 0.5], gap: gap)
            }
            let rows = split(rect, axis: .vertical, weights: [ratio, 1 - ratio], gap: gap)
            let top = split(rows[0], axis: .horizontal, weights: [0.5, 0.5], gap: gap)
            let bottom = split(rows[1], axis: .horizontal, weights: [0.5, 0.5], gap: gap)
            return [top[0], top[1], bottom[1], bottom[0]]
        }

        switch count {
        case 1:
            return [rect]
        case 2:
            return split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
        case 3:
            let cols = split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
            let right = split(cols[1], axis: .vertical, weights: [0.5, 0.5], gap: gap)
            return [cols[0], right[0], right[1]]
        default:
            let cols = split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
            let left = split(cols[0], axis: .vertical, weights: [0.5, 0.5], gap: gap)
            let right = split(cols[1], axis: .vertical, weights: [0.5, 0.5], gap: gap)
            // Shoji's fold: 1 top-left, 2 top-right, 3 bottom-right, 4 bottom-left.
            return [left[0], right[0], right[1], left[1]]
        }
    }

    // MARK: - Columns and rows

    private static func columnsFrames(_ rect: CGRect, count: Int, ratio: CGFloat, gap: CGFloat) -> [CGRect] {
        if count == 1 { return [rect] }
        let first = min(ratio, 0.72)
        let rest = (1 - first) / CGFloat(count - 1)
        return split(rect, axis: .horizontal, weights: [first] + Array(repeating: rest, count: count - 1), gap: gap)
    }

    private static func rowsFrames(_ rect: CGRect, count: Int, ratio: CGFloat, gap: CGFloat) -> [CGRect] {
        if count == 1 { return [rect] }
        let first = min(ratio, 0.72)
        let rest = (1 - first) / CGFloat(count - 1)
        return split(rect, axis: .vertical, weights: [first] + Array(repeating: rest, count: count - 1), gap: gap)
    }

    // MARK: - Side

    private static func sideFrames(_ rect: CGRect, count: Int, ratio: CGFloat, gap: CGFloat,
                                   ultrawide: Bool, vertical: Bool) -> [CGRect] {
        if count == 1 { return [rect] }

        if vertical {
            let rows = split(rect, axis: .vertical, weights: [ratio, 1 - ratio], gap: gap)
            let bottom = split(rows[1], axis: .horizontal, weights: Array(repeating: 1, count: count - 1), gap: gap)
            return [rows[0]] + bottom
        }

        if ultrawide && count >= 3 {
            let railWidth = max(0.2, min(0.3, 1 - ratio))
            let cols = split(rect, axis: .horizontal, weights: [1 - railWidth, railWidth], gap: gap)
            let big = split(cols[0], axis: .horizontal, weights: [0.5, 0.5], gap: gap)
            let rail = split(cols[1], axis: .vertical, weights: Array(repeating: 1, count: count - 2), gap: gap)
            return [big[0], big[1]] + rail
        }

        let cols = split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
        let rail = split(cols[1], axis: .vertical, weights: Array(repeating: 1, count: count - 1), gap: gap)
        return [cols[0]] + rail
    }

    // MARK: - Bento

    private static func bentoFrames(_ rect: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        switch count {
        case 1:
            return [rect]
        case 2:
            return split(rect, axis: .horizontal, weights: [0.62, 0.38], gap: gap)
        case 3:
            let cols = split(rect, axis: .horizontal, weights: [0.62, 0.38], gap: gap)
            let rail = split(cols[1], axis: .vertical, weights: [0.5, 0.5], gap: gap)
            return [cols[0], rail[0], rail[1]]
        default:
            let bands = split(rect, axis: .vertical, weights: [0.62, 0.38], gap: gap)
            let top = split(bands[0], axis: .horizontal, weights: [0.62, 0.38], gap: gap)
            let bottom = split(bands[1], axis: .horizontal, weights: [0.28, 0.72], gap: gap)
            return [top[0], top[1], bottom[0], bottom[1]]
        }
    }

    // MARK: - Splitting

    private static func split(_ rect: CGRect, axis: Axis, weights: [CGFloat], gap: CGFloat) -> [CGRect] {
        guard !weights.isEmpty else { return [rect] }
        if weights.count == 1 { return [rect] }
        let total = axis == .horizontal ? rect.width : rect.height
        let spacing = gap * CGFloat(weights.count - 1)
        let available = max(1, total - spacing)
        let sum = max(0.0001, weights.reduce(0, +))

        var result: [CGRect] = []
        var offset: CGFloat = 0
        for (index, weight) in weights.enumerated() {
            let size = available * (weight / sum)
            if axis == .horizontal {
                result.append(CGRect(x: rect.minX + offset, y: rect.minY, width: size, height: rect.height))
            } else {
                result.append(CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: size))
            }
            offset += size + gap
            if index == weights.count - 1 { break }
        }
        return result
    }
}
