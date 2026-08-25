//
//  LayoutInference.swift
//  PluckIt
//

import CoreGraphics

/// A block of recognized text and where it sits on the page.
///
/// Coordinates are normalized with a lower-left origin, matching Vision.
struct TextBlock: Equatable, Identifiable {
    /// Position in the document, used to tell apart blocks with identical text
    /// (repeated words are common in artwork captions).
    let id: Int
    let text: String
    let frame: CGRect
    /// Centred blocks span the page rather than belonging to a column.
    let isCentered: Bool

    init(id: Int, text: String, frame: CGRect, isCentered: Bool = false) {
        self.id = id
        self.text = text
        self.frame = frame
        self.isCentered = isCentered
    }
}

/// Recovers side-by-side comparison layouts that Vision does not report as
/// tables — the columns are aligned by eye, not by rules or shared baselines,
/// so the structure has to come from the geometry.
enum LayoutInference {
    /// Groups blocks into `columns` vertical bands, or nil when the page does
    /// not actually split into columns.
    static func columnBands(in blocks: [TextBlock], columns: Int = 2) -> [[TextBlock]]? {
        guard columns >= 2 else { return nil }

        // Banners, headings and footnotes run the full width and belong to no
        // single column; they are emitted around the table instead.
        let candidates = blocks.filter { !$0.isCentered && $0.frame.width < 0.95 / CGFloat(columns) }
        guard candidates.count >= 6 else { return nil }

        var bands = cluster(candidates, into: columns)
            .sorted { meanMidX(of: $0) < meanMidX(of: $1) }
        guard bands.allSatisfy({ $0.count >= minimumBandCount }) else { return nil }

        for index in 0 ..< (columns - 1) {
            guard let gutter = gutter(between: bands[index], and: bands[index + 1]),
                  crossingRatio(bands[index], bands[index + 1], gutter: gutter) <= maximumCrossingRatio
            else { return nil }

            // A block straddling the gutter belongs to neither column.
            bands[index] = bands[index].filter { $0.frame.maxX <= gutter + straddleTolerance }
            bands[index + 1] = bands[index + 1].filter { $0.frame.minX >= gutter - straddleTolerance }

            guard bands[index].count >= minimumBandCount,
                  bands[index + 1].count >= minimumBandCount,
                  verticalOverlap(bands[index], bands[index + 1]) >= minimumVerticalOverlap
            else { return nil }
        }

        return bands
    }

    /// An inferred table, plus the blocks trimmed from its ends.
    struct ColumnTable {
        let rows: [[String]]
        /// Blocks from partly-filled rows at the top and bottom: page furniture
        /// that happens to sit inside a column, not rows of the comparison.
        let excluded: [TextBlock]
    }

    /// Groups blocks across bands into table rows by vertical position.
    ///
    /// Rows are formed from the page down rather than by matching outward from
    /// one column, so a band with more entries than its neighbour does not slide
    /// the remaining rows out of alignment.
    static func table(pairing bands: [[TextBlock]]) -> ColumnTable {
        // Columns are seldom typeset at the same height, and the drift is
        // systematic rather than random, so correct for it before grouping.
        let offsets = bands.map { verticalOffset(of: $0, relativeTo: bands[0]) }
        let placed = bands.enumerated()
            .flatMap { column, band in
                band.map { (block: $0, column: column, midY: $0.frame.midY + offsets[column]) }
            }
            .sorted { $0.midY > $1.midY }

        var grouped: [[TextBlock?]] = []
        var row = [TextBlock?](repeating: nil, count: bands.count)
        var rowMidY: CGFloat?
        var rowHeight: CGFloat = 0

        for (block, column, midY) in placed {
            let sameRow = rowMidY.map { abs($0 - midY) <= max(rowHeight, block.frame.height) * rowTolerance } ?? false

            if !sameRow || row[column] != nil {
                if row.contains(where: { $0 != nil }) { grouped.append(row) }
                row = [TextBlock?](repeating: nil, count: bands.count)
                rowMidY = midY
                rowHeight = block.frame.height
            }

            row[column] = block
            rowHeight = max(rowHeight, block.frame.height)
            rowMidY = rowMidY ?? midY
        }

        if row.contains(where: { $0 != nil }) { grouped.append(row) }

        // A comparison starts and ends where both columns have something to say;
        // banners and calls to action bracket it with half-empty rows.
        let isComplete = { (row: [TextBlock?]) in row.allSatisfy { $0 != nil } }
        var body = Array(grouped.drop { !isComplete($0) })
        while let last = body.last, !isComplete(last) { body.removeLast() }

        let kept = Set(body.flatMap { $0 }.compactMap { $0?.id })
        return ColumnTable(
            rows: body.map { $0.map { $0?.text ?? "" } },
            excluded: grouped.flatMap { $0 }.compactMap { $0 }.filter { !kept.contains($0.id) }
        )
    }

    static func rows(pairing bands: [[TextBlock]]) -> [[String]] {
        table(pairing: bands).rows
    }

    // MARK: - Tuning
    //
    // These thresholds were chosen against rendered two-column fixtures; the
    // gutter and overlap gates are what stop an ordinary page of prose from
    // being mistaken for a comparison table.

    private static let minimumBandCount = 3
    /// Columns are rarely typeset on a shared baseline, so a row admits blocks
    /// within a little over one line height of each other.
    private static let rowTolerance: CGFloat = 1.2
    private static let maximumCrossingRatio = 0.35
    private static let straddleTolerance: CGFloat = 0.04
    private static let minimumVerticalOverlap: CGFloat = 0.15

    // MARK: - Clustering

    /// 1-D k-means over block centres, seeded at evenly spaced columns.
    private static func cluster(_ blocks: [TextBlock], into columns: Int) -> [[TextBlock]] {
        var centres = (0 ..< columns).map { CGFloat($0 + 1) / CGFloat(columns + 1) }
        var groups: [[TextBlock]] = []

        for _ in 0 ..< 25 {
            groups = Array(repeating: [], count: columns)
            for block in blocks {
                let nearest = centres.enumerated()
                    .min { abs($0.element - block.frame.midX) < abs($1.element - block.frame.midX) }?
                    .offset ?? 0
                groups[nearest].append(block)
            }

            let updated = groups.map { $0.isEmpty ? CGFloat(0.5) : meanMidX(of: $0) }
            let settled = zip(centres, updated).allSatisfy { abs($0 - $1) < 0.001 }
            centres = updated
            if settled { break }
        }

        return groups
    }

    /// The median distance between a band's blocks and the nearest block in the
    /// reference band — the amount this column sits above or below it.
    private static func verticalOffset(of band: [TextBlock], relativeTo reference: [TextBlock]) -> CGFloat {
        guard !reference.isEmpty else { return 0 }
        let differences = band.compactMap { block -> CGFloat? in
            reference
                .map { $0.frame.midY - block.frame.midY }
                .min { abs($0) < abs($1) }
        }.sorted()
        return differences.isEmpty ? 0 : differences[differences.count / 2]
    }

    private static func gutter(between left: [TextBlock], and right: [TextBlock]) -> CGFloat? {
        guard let leftEdge = left.map(\.frame.maxX).max(),
              let rightEdge = right.map(\.frame.minX).min() else { return nil }
        return (leftEdge + rightEdge) / 2
    }

    /// The share of blocks reaching across the gutter. A real column split
    /// leaves it almost empty.
    private static func crossingRatio(_ left: [TextBlock], _ right: [TextBlock], gutter: CGFloat) -> Double {
        let crossers = left.filter { $0.frame.maxX > gutter + 0.02 }.count
            + right.filter { $0.frame.minX < gutter - 0.02 }.count
        return Double(crossers) / Double(left.count + right.count)
    }

    /// How much of the page height the two bands share; side-by-side content
    /// overlaps, stacked sections do not.
    private static func verticalOverlap(_ left: [TextBlock], _ right: [TextBlock]) -> CGFloat {
        let leftMids = left.map(\.frame.midY)
        let rightMids = right.map(\.frame.midY)
        guard let leftTop = leftMids.max(), let leftBottom = leftMids.min(),
              let rightTop = rightMids.max(), let rightBottom = rightMids.min() else { return 0 }
        return min(leftTop, rightTop) - max(leftBottom, rightBottom)
    }

    private static func meanMidX(of blocks: [TextBlock]) -> CGFloat {
        blocks.isEmpty ? 0.5 : blocks.map(\.frame.midX).reduce(0, +) / CGFloat(blocks.count)
    }
}
