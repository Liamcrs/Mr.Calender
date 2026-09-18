import SwiftUI
import UIKit

enum AppTheme {
    static let card = Color(.secondarySystemBackground)
    static let mint = Color.green.opacity(0.14)
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); content }.padding().background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18)) }
}

extension View {
    /// Lets users dismiss the keyboard by tapping the surrounding form/page.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
