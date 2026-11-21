import SwiftUI

/// Lays its content out in a row when the row fits, and in a column when it doesn't.
///
/// Give wrapping text inside it a modest `idealWidth`, otherwise its one-line width
/// makes the row look too wide and the column is always chosen.
struct AdaptiveStack<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: spacing) { content }
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}
