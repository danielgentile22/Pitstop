import SwiftUI

/// Map pin standing in for several nearby pins of one kind when zoomed out. Visited and unvisited
/// places cluster separately, so a cluster of guesses never hides a bathroom the user has checked.
struct ClusterAnnotation: View {

    enum Kind: Hashable {
        case bathrooms
        /// Tinted by the most reliable brand in the cluster.
        case candidates(Reliability)
    }

    let kind: Kind
    let count: Int

    var body: some View {
        let digits = String(count).count
        let size = CGFloat(34 + max(0, digits - 1) * 6)

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
        }
    }

    private var countLabel: some View {
        Text("\(count)")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

#Preview("Clusters") {
    HStack(spacing: 20) {
        ClusterAnnotation(kind: .bathrooms, count: 4)
        ClusterAnnotation(kind: .candidates(.reliable), count: 27)
        ClusterAnnotation(kind: .candidates(.likely), count: 312)
        ClusterAnnotation(kind: .candidates(.uncertain), count: 1204)
    }
    .padding(24)
    .background(Color(.systemGroupedBackground))
}
