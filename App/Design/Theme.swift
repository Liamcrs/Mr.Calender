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
    /// Dismisses the keyboard without consuming taps intended for form controls.
    func dismissKeyboardOnTap() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(KeyboardDismissInstaller())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { Keyboard.dismiss() }
                }
            }
    }
}

private enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissView { KeyboardDismissView() }
    func updateUIView(_ uiView: KeyboardDismissView, context: Context) {}
    static func dismantleUIView(_ uiView: KeyboardDismissView, coordinator: ()) {
        uiView.uninstall()
    }
}

private final class KeyboardDismissView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var recognizer: UITapGestureRecognizer = {
        let value = UITapGestureRecognizer(target: self, action: #selector(didTapOutsideInput))
        value.cancelsTouchesInView = false
        value.delegate = self
        return value
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window !== installedWindow else { return }
        installedWindow?.removeGestureRecognizer(recognizer)
        window?.addGestureRecognizer(recognizer)
        installedWindow = window
    }

    deinit { installedWindow?.removeGestureRecognizer(recognizer) }

    func uninstall() {
        installedWindow?.removeGestureRecognizer(recognizer)
        installedWindow = nil
    }

    @objc private func didTapOutsideInput() { Keyboard.dismiss() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }
}
