//
//  KeyboardStickyComposerVisualTest.swift
//  SpectRoom
//
//  Launch with argument: -KeyboardComposerVisualTest
//  Posts synthetic keyboard frames so we can verify layout without Simulator soft-keyboard quirks.
//

import SwiftUI
import UIKit

struct KeyboardStickyComposerVisualTest: View {
    @State private var text = ""
    @State private var showSheet = true
    @State private var phaseLabel = "KB Closed"
    @FocusState private var focused: Bool
    
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        Color.blue.opacity(0.15)
            .ignoresSafeArea()
            .sheet(isPresented: $showSheet) {
                sheetContent
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .interactiveDismissDisabled()
            }
            .onAppear {
                // 0.0s–1.2s: closed keyboard for screenshot
                // 1.4s+: synthesize a realistic keyboard frame for open screenshot
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    phaseLabel = "KB Open (synthetic)"
                    postSyntheticKeyboard(height: 336)
                }
            }
    }
    
    private var sheetContent: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.55, green: 0.75, blue: 0.95),
                        Color(red: 0.70, green: 0.88, blue: 0.70),
                        Color(red: 0.98, green: 0.85, blue: 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                KeyboardStickyChatLayout {
                    HStack {
                        Text("Visual Test")
                            .font(.headline)
                        Spacer()
                        Text(phaseLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                } messages: {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(0..<8, id: \.self) { index in
                                HStack {
                                    Spacer()
                                    Text("Sample message \(index + 1)")
                                        .padding(12)
                                        .background(Color.blue.opacity(0.25))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }
                        .padding()
                    }
                } composer: {
                    composer
                }
                
                // Visual stand-in for the keyboard area so screenshots show where it would sit.
                if phaseLabel.contains("Open") {
                    VStack {
                        Spacer()
                        ZStack {
                            Color(UIColor.systemGray4)
                            Text("Synthetic Keyboard \(Int(336))pt")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 336)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 34, height: 34)
            
            TextField("Type something...", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 38)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            
            if hasText {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.green)
                    .clipShape(Circle())
            } else {
                Image(systemName: "camera")
                    .frame(width: 34, height: 34)
                Image(systemName: "mic")
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
    
    private func postSyntheticKeyboard(height: CGFloat) {
        let screen = UIScreen.main.bounds
        let frame = CGRect(x: 0, y: screen.height - height, width: screen.width, height: height)
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.25,
                UIResponder.keyboardAnimationCurveUserInfoKey: 7
            ]
        )
    }
}
