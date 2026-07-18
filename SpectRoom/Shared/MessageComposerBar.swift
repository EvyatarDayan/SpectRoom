//
//  MessageComposerBar.swift
//  SpectRoom
//

import SwiftUI

struct MessageComposerBar: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    
    var placeholder: String
    var isDisabled: Bool
    var isSending: Bool
    var isRecording: Bool
    var onSend: () -> Void
    var onCamera: () -> Void
    var onRecordingPressChanged: (Bool) -> Void
    var onShortMicTap: () -> Void = {}
    
    @State private var didArmLongPressRecording = false
    
    /// Hold this long before recording starts (short taps show a tip instead).
    private let micLongPressDuration: Double = 1.0
    
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ComposerDismissKeyboardTextView(
                text: $text,
                isFocused: $isFocused,
                placeholder: placeholder,
                isDisabled: isDisabled
            )
            .padding(.horizontal, 6)
            .frame(minHeight: 42, maxHeight: 42)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            
            if hasText {
                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Color.green)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending || isDisabled)
            } else {
                Button(action: onCamera) {
                    Image(systemName: "folder")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 34, height: 34)
                }
                .disabled(isDisabled)
                
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isRecording ? .red : .primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                    .overlay(
                        Circle()
                            .stroke(isRecording ? Color.red.opacity(0.4) : Color.clear, lineWidth: 2)
                    )
                    .opacity(isDisabled ? 0.5 : 1)
                    .allowsHitTesting(!isDisabled)
                    .onLongPressGesture(
                        minimumDuration: micLongPressDuration,
                        maximumDistance: 60,
                        pressing: { pressing in
                            if pressing {
                                didArmLongPressRecording = false
                            } else if didArmLongPressRecording {
                                // Recording continues in the bottom sheet — stop from there.
                                didArmLongPressRecording = false
                            } else {
                                onShortMicTap()
                            }
                        },
                        perform: {
                            didArmLongPressRecording = true
                            onRecordingPressChanged(true)
                        }
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .opacity(isDisabled ? 0.5 : 1)
    }
}
