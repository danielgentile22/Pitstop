import SwiftUI

/// A titled section of a detail sheet, with a divider above it.
struct DetailSection<Content: View>: View {

    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

/// An icon and a line of text in a detail sheet.
struct MetaRow: View {

    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Open 24 hours, not open 24 hours, or unknown when `isOpen24Hours` is nil.
struct HoursRow: View {

    let isOpen24Hours: Bool?
    let notOpenText: String

    var body: some View {
        switch isOpen24Hours {
        case true?:  MetaRow(icon: "clock.fill", color: .blue, text: "Open 24 hours")
        case false?: MetaRow(icon: "clock", color: Color(.systemGray3), text: notOpenText)
        case nil:    MetaRow(icon: "questionmark.circle", color: Color(.systemGray3), text: "Hours unknown")
        }
    }
}
