//
//  OnboardingView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation
import UIKit

struct OnboardingView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "en"
    @State private var showingLanguageModal = false
    @StateObject private var slideshow = WelcomeSlideshowController()
    @State private var pinnedSlideshowY: CGFloat?
    @State private var dontShowWelcomeAgain = false
    
    var pages: [OnboardingPage] {
        [
            OnboardingPage(
                title: "onboarding.welcome.title".localized,
                subtitle: "onboarding.welcome.subtitle".localized,
                description: "onboarding.welcome.description".localized
            ),
            OnboardingPage(
                title: "onboarding.match.title".localized,
                subtitle: "onboarding.match.subtitle".localized,
                description: "onboarding.match.description".localized
            ),
            OnboardingPage(
                title: "onboarding.communication.title".localized,
                subtitle: "onboarding.communication.subtitle".localized,
                description: "onboarding.communication.description".localized
            ),
            OnboardingPage(
                title: "onboarding.settings.title".localized,
                subtitle: "onboarding.settings.subtitle".localized,
                description: "onboarding.settings.description".localized
            )
        ]
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Same centered layout as before; photo is overlaid so it doesn't slide with text
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                .overlayPreferenceValue(WelcomeSlideshowAnchorKey.self) { anchor in
                    GeometryReader { geometry in
                        let resolvedY = pinnedSlideshowY ?? anchor.map { geometry[$0].midY }
                        
                        if let resolvedY {
                            WelcomeImageSlideshow(slideshow: slideshow)
                                .position(x: geometry.size.width / 2, y: resolvedY)
                                .allowsHitTesting(false)
                                .onAppear {
                                    if pinnedSlideshowY == nil {
                                        pinnedSlideshowY = resolvedY
                                    }
                                }
                        }
                    }
                }
                
                Button(action: {
                    dontShowWelcomeAgain.toggle()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: dontShowWelcomeAgain ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                        Text("onboarding.dont.show.again".localized)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 30)
                .padding(.bottom, 16)
                
                // Navigation buttons
                HStack {
                    if currentPage > 0 {
                        Button("onboarding.previous".localized) {
                            withAnimation {
                                currentPage -= 1
                            }
                        }
                        .foregroundColor(.blue)
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    if currentPage < pages.count - 1 {
                        Button("onboarding.next".localized) {
                            withAnimation {
                                currentPage += 1
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                    } else {
                        Button("onboarding.get.started".localized) {
                            appState.completeOnboarding(dontShowAgain: dontShowWelcomeAgain)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 50)

                // Page indicator at bottom
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentPage)
                    }
                }
                .padding(.bottom, 24)
            }
            
            Button(action: {
                showingLanguageModal = true
            }) {
                HStack(spacing: 6) {
                    Text(currentLanguageFlag)
                        .font(.headline)
                    Text(currentLanguageName)
                        .font(.subheadline)
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
            }
            .padding(.trailing, 20)
            .padding(.top, 50)
        }
        .sheet(isPresented: $showingLanguageModal) {
            LanguageSelectionModal()
        }
    }
    
    private var currentLanguageFlag: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.flag ?? "🇺🇸"
    }
    
    private var currentLanguageName: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.name ?? "English"
    }
}

/// Shared slideshow state so every welcome page shows the same image and timing.
/// Any asset named `Welcome1`, `Welcome2`, … in Assets.xcassets is included automatically.
final class WelcomeSlideshowController: ObservableObject {
    static let imageSize: CGFloat = 140
    /// A photo cannot repeat until this many other photos have been shown.
    private static let cooldownCount = 3
    
    let imageNames: [String]
    
    @Published var currentIndex = 0
    
    /// Indices of recently shown photos (most recent last). Kept at most `cooldownCount` long.
    private var recentlyShown: [Int] = []
    private var timer: Timer?
    
    init() {
        imageNames = Self.discoverWelcomeImageNames()
        if !imageNames.isEmpty {
            currentIndex = Int.random(in: 0..<imageNames.count)
            recentlyShown = [currentIndex]
        }
        
        guard imageNames.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.4)) {
                    self.currentIndex = self.nextRandomIndex()
                }
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    /// Finds every asset catalog image named Welcome1, Welcome2, … (gaps allowed).
    private static func discoverWelcomeImageNames() -> [String] {
        var names: [String] = []
        // Scan a generous range so newly added WelcomeN assets are picked up automatically
        for index in 1...100 {
            let name = "Welcome\(index)"
            if UIImage(named: name) != nil {
                names.append(name)
            }
        }
        return names
    }
    
    private func nextRandomIndex() -> Int {
        guard !imageNames.isEmpty else { return currentIndex }
        
        // Exclude photos shown in the last `cooldownCount` slots (when enough alternatives exist)
        let cooldown = Set(recentlyShown.suffix(Self.cooldownCount))
        var candidates = Array(0..<imageNames.count).filter { !cooldown.contains($0) }
        
        // If the catalog is smaller than cooldown + 1, fall back to "anything except current"
        if candidates.isEmpty {
            candidates = Array(0..<imageNames.count).filter { $0 != currentIndex }
        }
        if candidates.isEmpty {
            return currentIndex
        }
        
        let next = candidates.randomElement() ?? currentIndex
        recentlyShown.append(next)
        if recentlyShown.count > Self.cooldownCount {
            recentlyShown.removeFirst(recentlyShown.count - Self.cooldownCount)
        }
        return next
    }
}

private struct WelcomeSlideshowAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct WelcomeImageSlideshow: View {
    @ObservedObject var slideshow: WelcomeSlideshowController
    
    private let imageOpacity: Double = 0.8
    private let cornerRadius: CGFloat = 16
    private let frameWidth: CGFloat = 3
    
    private var imageSize: CGFloat { WelcomeSlideshowController.imageSize }
    
    var body: some View {
        ZStack {
            ForEach(Array(slideshow.imageNames.enumerated()), id: \.offset) { index, name in
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: imageSize, height: imageSize)
                    .clipped()
                    .opacity(index == slideshow.currentIndex ? imageOpacity : 0)
            }
        }
        .frame(width: imageSize, height: imageSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black, lineWidth: frameWidth)
        )
    }
}

struct OnboardingPage {
    let title: String
    let subtitle: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Reserves the same space as the photo so layout/text sizing stay unchanged
            Color.clear
                .frame(
                    width: WelcomeSlideshowController.imageSize,
                    height: WelcomeSlideshowController.imageSize
                )
                .anchorPreference(
                    key: WelcomeSlideshowAnchorKey.self,
                    value: .bounds
                ) { $0 }
            
            // Text content — original sizes
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    OnboardingView()
}
