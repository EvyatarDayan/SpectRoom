//
//  KeyboardStickyBottomBar.swift
//  SpectRoom
//
//  Chat composer layout that works in both keyboard states inside sheets:
//  1) `.ignoresSafeArea(.keyboard)` prevents SwiftUI from double-lifting the sheet.
//  2) Bottom padding uses the real keyboard↔view overlap from keyboard frame notifications.
//  3) When the keyboard is closed, the composer keeps home-indicator-safe padding.
//

import SwiftUI
import UIKit

/// WhatsApp-style conversation chrome: messages scroll; composer docks above the home
/// indicator when the keyboard is closed, and flush above the keyboard when open.
struct KeyboardStickyChatLayout<Header: View, Messages: View, Composer: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var messages: () -> Messages
    @ViewBuilder var composer: () -> Composer
    
    @State private var keyboardOverlap: CGFloat = 0
    @State private var viewGlobalFrame: CGRect = .zero
    
    private var isKeyboardVisible: Bool { keyboardOverlap > 1 }
    
    private var closedKeyboardBottomPadding: CGFloat {
        max(keyWindowSafeAreaBottom, 20) + 20
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header()
            messages()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            composer()
                .padding(.bottom, isKeyboardVisible ? 8 : closedKeyboardBottomPadding)
                .background(
                    Color(.systemGray5)
                        .ignoresSafeArea(edges: isKeyboardVisible ? [] : .bottom)
                )
        }
        .padding(.bottom, keyboardOverlap)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewGlobalFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        viewGlobalFrame = frame
                    }
            }
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateOverlap(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            animate(notification) { keyboardOverlap = 0 }
        }
    }
    
    private var keyWindowSafeAreaBottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.safeAreaInsets.bottom ?? 34
    }
    
    private func updateOverlap(from notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        
        let screenHeight = UIScreen.main.bounds.height
        let isOffScreen = endFrame.minY >= screenHeight - 1
        let overlap = isOffScreen ? 0 : max(0, viewGlobalFrame.maxY - endFrame.minY)
        
        animate(notification) {
            keyboardOverlap = overlap
        }
    }
    
    private func animate(_ notification: Notification, _ updates: @escaping () -> Void) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: duration), updates)
    }
}
