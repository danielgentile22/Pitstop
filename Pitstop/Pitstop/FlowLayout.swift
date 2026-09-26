import SwiftUI

/// Lays subviews out left to right, wrapping to a new row when the next one won't fit.
struct FlowLayout: Layout {

    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    // MARK: - Cache

    /// Filled by `sizeThatFits` so `placeSubviews` can reuse the measurements.
    struct Cache {
        var sizes: [CGSize] = []           // parallel to `subviews`
        var rowAssignments: [Int] = []     // row index per subview
        var rowHeights: [CGFloat] = []
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
        if cache.sizes.count != subviews.count {
            compute(in: bounds.width, subviews: subviews, cache: &cache)
        }

        var rowOriginY = bounds.minY
        var currentRow = -1
        var x = bounds.minX

        for (i, subview) in subviews.enumerated() {
            let row = cache.rowAssignments[i]
            if row != currentRow {
                if currentRow >= 0 { rowOriginY += cache.rowHeights[currentRow] + spacing }
                currentRow = row
                x = bounds.minX
            }
            subview.place(at: CGPoint(x: x, y: rowOriginY), proposal: .unspecified)
            x += cache.sizes[i].width + spacing
        }
    }

    // MARK: - Private

    private func compute(in maxWidth: CGFloat, subviews: Subviews, cache: inout Cache) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.sizes = sizes

        var rowAssignments = [Int](repeating: 0, count: sizes.count)
        var rowHeights: [CGFloat] = []
        var usedWidth: CGFloat = 0
        var currentRow = 0

        for (i, size) in sizes.enumerated() {
            // `usedWidth > 0` lets a subview wider than the container sit alone on its row
            // instead of producing an empty row before it.
            if usedWidth + size.width > maxWidth, usedWidth > 0 {
                currentRow += 1
                usedWidth = 0
            }
            rowAssignments[i] = currentRow
            usedWidth += size.width + spacing

            if rowHeights.count <= currentRow {
                rowHeights.append(size.height)
            } else {
                rowHeights[currentRow] = max(rowHeights[currentRow], size.height)
            }
        }

        cache.rowAssignments = rowAssignments
        cache.rowHeights     = rowHeights

        let totalHeight = rowHeights.enumerated().reduce(CGFloat(0)) { acc, pair in
            acc + pair.element + (pair.offset < rowHeights.count - 1 ? spacing : 0)
        }
        let totalWidth = rowHeights.isEmpty ? 0 : sizes.indices.reduce(CGFloat(0)) { acc, i in
            let rowEnd = (i == sizes.count - 1) || (rowAssignments[i + 1] != rowAssignments[i])
            if rowEnd {
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
