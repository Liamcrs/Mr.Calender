import SwiftUI

enum AppTheme {
    static let card = Color(.secondarySystemBackground)
    static let mint = Color.green.opacity(0.14)
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); content }.padding().background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) }
}
