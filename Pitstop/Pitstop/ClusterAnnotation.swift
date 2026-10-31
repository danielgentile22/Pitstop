import SwiftUI

/// Map pin standing in for several nearby pins of one kind when zoomed out. Visited, unvisited and dismissed
/// places cluster separately, so a cluster of guesses never hides a bathroom the user has checked.
struct ClusterAnnotation: View {

    enum Kind: Hashable {
        case bathrooms
        /// Tinted by the most reliable brand in the cluster.
        case candidates(Reliability)
        /// Places marked "No public restroom here": gray with the X, like their pins.
        case dismissed
    }

    let kind: Kind
    /// A count bucket from `countBucket(for:)`. Counts from 10 up show as "10+", "25+" and so on.
    let count: Int

    private static let bucketFloors = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000]

    /// Exact below 10, then the largest bucket floor at or below `count`, so badges render a fixed set of images.
    static func countBucket(for count: Int) -> Int {
        guard count >= 10 else { return count }
        return bucketFloors.last(where: { $0 <= count }) ?? 10
    }

    private var countText: String {
        switch count {
        case ..<10:    return "\(count)"
        case ..<1000:  return "\(count)+"
        default:       return "\(count / 1000)k+"
        }
    }

    var body: some View {
        let size = CGFloat(34 + max(0, countText.count - 1) * 6)

        switch kind {
        case .bathrooms:
            Circle()
                .fill(Color.blue)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .frame(width: size, height: size)
                .shadow(color: .blue.opacity(0.45), radius: 5, y: 2)
                .overlay { countLabel }

        case .candidates(let reliability):
            let tint = reliability.tint
            Circle()
                .fill(tint.opacity(0.55))
                .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                .frame(width: size, height: size)
                .overlay { countLabel }

        case .dismissed:
            let tint = Color(.systemGray)
            let badgeSize: CGFloat = 15
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(tint.opacity(0.55))
                    .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                    .frame(width: size, height: size)
                    .overlay { countLabel }

                Image(systemName: "xmark")
                    .font(.system(size: badgeSize * 0.6, weight: .heavy))
                    .foregroundStyle(.red)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(Circle().fill(.white))
                    .overlay(Circle().strokeBorder(.red, lineWidth: 1))
                    .offset(x: badgeSize * 0.3, y: -badgeSize * 0.3)
            }
        }
    }

    private var countLabel: some View {
        Text(countText)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

#Preview("Clusters") {
    HStack(spacing: 20) {
        ClusterAnnotation(kind: .bathrooms, count: 4)
        ClusterAnnotation(kind: .candidates(.reliable), count: ClusterAnnotation.countBucket(for: 27))
        ClusterAnnotation(kind: .candidates(.likely), count: ClusterAnnotation.countBucket(for: 312))
        ClusterAnnotation(kind: .candidates(.uncertain), count: ClusterAnnotation.countBucket(for: 1204))
        ClusterAnnotation(kind: .dismissed, count: 3)
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
