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

    /// The draggable split between the primary tile and the rest of a layout.
    struct Divider {
        enum Axis: Equatable { case vertical, horizontal }

        let axis: Axis
        let hitRect: CGRect
        /// Usable span along the divider's axis, excluding gaps.
        let availableSpan: CGFloat
        /// The primary tile's share when the drag began.
        let startShare: CGFloat
        /// Limits for the primary tile's share.
        let shareRange: ClosedRange<CGFloat>
    }

    private enum Axis { case horizontal, vertical }

    static func frames(for layout: LayoutKind, input: Input) -> [CGRect] {
        let count = max(1, input.count)
        let ratio = primaryShare(for: layout, input: input)
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
            return bentoFrames(content, count: count, ratio: ratio, gap: gap)
        }
    }

    // MARK: - Primary share

    /// The share of the screen used by the primary tile. Most layouts use the
    /// stored ratio directly, but Bento starts asymmetric and Side reserves a
    /// narrow rail on ultrawide screens. Keeping this mapping in one place
    /// means a shortcut or drag always changes something visible.
    static func primaryShare(for layout: LayoutKind, input: Input) -> CGFloat {
        let rawRatio = min(0.75, max(0.34, input.ratio))
        return primaryShare(for: layout, ratio: rawRatio, input: input)
    }

    static func primaryShareRange(for layout: LayoutKind, input: Input) -> ClosedRange<CGFloat> {
        switch layout {
        case .columns, .rows:
            return 0.34...0.72
        case .bento:
            return 0.46...0.75
        case .side where input.isUltrawide && input.count >= 3:
            return 0.70...0.80
        default:
            return 0.34...0.75
        }
    }

    /// Converts a primary-tile share back to the value stored in settings.
    static func storedRatio(forPrimaryShare share: CGFloat, layout: LayoutKind, input: Input) -> CGFloat {
        let range = primaryShareRange(for: layout, input: input)
        let clamped = min(range.upperBound, max(range.lowerBound, share))
        switch layout {
        case .bento:
            return min(0.75, max(0.34, clamped - 0.12))
        case .side where input.isUltrawide && input.count >= 3:
            let fraction = (clamped - 0.70) / 0.10
            return min(0.75, max(0.34, 0.34 + fraction * 0.41))
        case .columns, .rows:
            return min(0.72, max(0.34, clamped))
        default:
            return min(0.75, max(0.34, clamped))
        }
    }

    /// Finds the primary split's draggable gap. Returns nil when there is only
    /// one tile, no gap, or the display is too small.
    static func mainDivider(for layout: LayoutKind, input: Input) -> Divider? {
        let count = max(1, input.count)
        guard count > 1 else { return nil }

        let gap = max(0, min(32, input.gap))
        guard gap >= 2 else { return nil }

        let bounds = input.bounds.standardized
        guard bounds.width > 40, bounds.height > 40 else { return nil }
        let content = bounds.insetBy(dx: gap, dy: gap)
        guard content.width > 20, content.height > 20 else { return nil }

        let axis: Divider.Axis
        switch layout {
        case .grid:
            axis = input.isVertical ? .horizontal : .vertical
        case .columns:
            axis = .vertical
        case .rows:
            axis = .horizontal
        case .side:
            axis = input.isVertical ? .horizontal : .vertical
        case .bento:
            axis = count >= 4 ? .horizontal : .vertical
        }

        let available: CGFloat
        if axis == .vertical {
            if layout == .columns {
                available = content.width - CGFloat(count - 1) * gap
            } else {
                available = content.width - gap
            }
        } else if layout == .rows {
            available = content.height - CGFloat(count - 1) * gap
        } else {
            available = content.height - gap
        }
        guard available > 1 else { return nil }

        let share = primaryShare(for: layout, input: input)
        let range = primaryShareRange(for: layout, input: input)
        let coordinate = (axis == .vertical ? content.minX : content.minY) + available * share + gap / 2
        let thickness = max(4, min(14, gap))

        let hitRect: CGRect
        if axis == .vertical {
            hitRect = CGRect(x: coordinate - thickness / 2,
                             y: content.minY,
                             width: thickness,
                             height: content.height)
        } else {
            hitRect = CGRect(x: content.minX,
                             y: coordinate - thickness / 2,
                             width: content.width,
                             height: thickness)
        }

        return Divider(axis: axis, hitRect: hitRect, availableSpan: available,
                       startShare: share, shareRange: range)
    }

    private static func primaryShare(for layout: LayoutKind, ratio: CGFloat, input: Input) -> CGFloat {
        switch layout {
        case .bento:
            // Bento is intentionally asymmetric. A half setting still gives
            // the hero 62% of the screen, and every step remains visible.
            return min(0.75, max(0.46, ratio + 0.12))
        case .side where input.isUltrawide && input.count >= 3:
            // Map the normal 34–75% setting range onto the rail's 70–80%
            // hero range so every shortcut press changes the rail width.
            let fraction = min(1, max(0, (ratio - 0.34) / (0.75 - 0.34)))
            return 0.70 + fraction * 0.10
        case .columns, .rows:
            return min(0.72, ratio)
        default:
            return ratio
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
            let cols = split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
            let big = split(cols[0], axis: .horizontal, weights: [0.5, 0.5], gap: gap)
            let rail = split(cols[1], axis: .vertical, weights: Array(repeating: 1, count: count - 2), gap: gap)
            return [big[0], big[1]] + rail
        }

        let cols = split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
        let rail = split(cols[1], axis: .vertical, weights: Array(repeating: 1, count: count - 1), gap: gap)
        return [cols[0]] + rail
    }

    // MARK: - Bento

    private static func bentoFrames(_ rect: CGRect, count: Int, ratio: CGFloat, gap: CGFloat) -> [CGRect] {
        switch count {
        case 1:
            return [rect]
        case 2:
            return split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
        case 3:
            let cols = split(rect, axis: .horizontal, weights: [ratio, 1 - ratio], gap: gap)
            let rail = split(cols[1], axis: .vertical, weights: [0.5, 0.5], gap: gap)
            return [cols[0], rail[0], rail[1]]
        default:
            let bands = split(rect, axis: .vertical, weights: [ratio, 1 - ratio], gap: gap)
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
