//
//  FlowLayout.swift
//  GeoPoop
//
//  Custom Layout that wraps children into rows — like CSS `flex-wrap: wrap`.
//  Used wherever tag chips need to reflow across multiple lines.
//
//  Conforms to the `Layout` protocol (iOS 16+). No UIKit bridging needed.
//
//  Cache:
//    The Layout protocol provides a `cache` parameter that is shared between
//    `sizeThatFits` and `placeSubviews`. The cache stores pre-computed subview
//    sizes and row assignments so the layout math runs once per layout pass
//    instead of twice.
//

import SwiftUI

/// Arranges subviews in rows, wrapping to a new row when the next child
/// would exceed the available width.
struct FlowLayout: Layout {

    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    // MARK: - Cache

    struct Cache {
        /// Measured size of each subview. Indexed parallel to `Subviews`.
        var sizes: [CGSize] = []
        /// Which row each subview belongs to (index into `rowHeights`).
        var rowAssignments: [Int] = []
        /// Max height of each row.
        var rowHeights: [CGFloat] = []
        /// Total computed size of the layout.
        var totalSize: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    // MARK: - Layout Protocol

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        compute(in: proposal.width ?? .infinity, subviews: subviews, cache: &cache)
        return cache.totalSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        // Recompute if the available width has changed since sizeThatFits.
        if cache.sizes.count != subviews.count {
            compute(in: bounds.width, subviews: subviews, cache: &cache)
        }

        var rowOriginY = bounds.minY
        // Track current x and the row we're in while iterating
        var currentRow = -1
        var x = bounds.minX

        for (i, subview) in subviews.enumerated() {
            let row = cache.rowAssignments[i]
            if row != currentRow {
                // Starting a new row
                if currentRow >= 0 { rowOriginY += cache.rowHeights[currentRow] + spacing }
                currentRow = row
                x = bounds.minX
            }
            subview.place(at: CGPoint(x: x, y: rowOriginY), proposal: .unspecified)
            x += cache.sizes[i].width + spacing
        }
    }

    // MARK: - Private

    /// Measures all subviews and computes row structure, storing results in `cache`.
    private func compute(in maxWidth: CGFloat, subviews: Subviews, cache: inout Cache) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.sizes = sizes

        var rowAssignments = [Int](repeating: 0, count: sizes.count)
        var rowHeights: [CGFloat] = []
        var usedWidth: CGFloat = 0
        var currentRow = 0

        for (i, size) in sizes.enumerated() {
            if usedWidth + size.width > maxWidth, usedWidth > 0 {
                // Overflow — start a new row
                currentRow += 1
                usedWidth = 0
            }
            rowAssignments[i] = currentRow
            usedWidth += size.width + spacing

            // Update row height
            if rowHeights.count <= currentRow {
                rowHeights.append(size.height)
            } else {
                rowHeights[currentRow] = max(rowHeights[currentRow], size.height)
            }
        }

        cache.rowAssignments = rowAssignments
        cache.rowHeights     = rowHeights

        // Total size
        let totalHeight = rowHeights.enumerated().reduce(CGFloat(0)) { acc, pair in
            acc + pair.element + (pair.offset < rowHeights.count - 1 ? spacing : 0)
        }
        let totalWidth = rowHeights.isEmpty ? 0 : sizes.indices.reduce(CGFloat(0)) { acc, i in
            let rowEnd = (i == sizes.count - 1) || (rowAssignments[i + 1] != rowAssignments[i])
            if rowEnd {
                // Compute width of this completed row
                let rowIndex = rowAssignments[i]
                let rowItems = sizes.indices.filter { rowAssignments[$0] == rowIndex }
                let w = rowItems.reduce(CGFloat(0)) { $0 + sizes[$1].width }
                       + CGFloat(max(rowItems.count - 1, 0)) * spacing
                return max(acc, w)
            }
            return acc
        }

        cache.totalSize = CGSize(width: totalWidth, height: totalHeight)
    }
}
