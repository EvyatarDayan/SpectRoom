//
//  ComposerDismissKeyboardTextView.swift
//  SpectRoom
//
//  Multiline chat field whose keyboard Return key is native "Done".
//  Tapping Done hides the keyboard (does not insert a newline).
//

import SwiftUI
import UIKit

struct ComposerDismissKeyboardTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    var placeholder: String
    var isDisabled: Bool = false
    var minHeight: CGFloat = 42
    var maxHeight: CGFloat = 42
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.returnKeyType = .done
        textView.enablesReturnKeyAutomatically = false
        textView.isScrollEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.accessibilityLabel = placeholder
        
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.tag = 9001
        textView.addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 6),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -6),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8)
        ])
        
        context.coordinator.placeholderLabel = placeholderLabel
        context.coordinator.updatePlaceholderVisibility(for: textView)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        
        if textView.text != text {
            textView.text = text
            context.coordinator.updatePlaceholderVisibility(for: textView)
            context.coordinator.recalculateHeight(for: textView)
        }
        
        textView.isEditable = !isDisabled
        textView.isUserInteractionEnabled = !isDisabled
        
        DispatchQueue.main.async {
            if isFocused, !textView.isFirstResponder {
                textView.becomeFirstResponder()
            } else if !isFocused, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }
    
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width.isFinite, width > 0 else {
            return CGSize(width: proposal.width ?? 0, height: context.coordinator.measuredHeight)
        }
        
        let fitting = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let height = min(max(fitting.height, minHeight), maxHeight)
        context.coordinator.measuredHeight = height
        uiView.isScrollEnabled = fitting.height > maxHeight
        return CGSize(width: width, height: height)
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerDismissKeyboardTextView
        weak var placeholderLabel: UILabel?
        var measuredHeight: CGFloat
        
        init(_ parent: ComposerDismissKeyboardTextView) {
            self.parent = parent
            self.measuredHeight = parent.minHeight
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updatePlaceholderVisibility(for: textView)
            recalculateHeight(for: textView)
        }
        
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // Native Done key sends "\n" - use it to hide the keyboard.
            if text == "\n" {
                parent.isFocused = false
                textView.resignFirstResponder()
                return false
            }
            return true
        }
        
        func updatePlaceholderVisibility(for textView: UITextView) {
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }
        
        func recalculateHeight(for textView: UITextView) {
            textView.invalidateIntrinsicContentSize()
            textView.setNeedsLayout()
            textView.layoutIfNeeded()
        }
    }
}
