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
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showingLanguageModal = false
    @StateObject private var slideshow = WelcomeSlideshowController()
    @State private var pinnedSlideshowY: CGFloat?
    @State private var dontShowWelcomeAgain = false
    
    var pages: [OnboardingPage] {
        [
            OnboardingPage(
                step: nil,
                title: "onboarding.intro.title".localized,
                subtitle: "onboarding.intro.subtitle".localized,
                description: "onboarding.intro.description".localized,
                notice: nil,
                noticeLead: "onboarding.intro.notice.lead".localized,
                noticeBody: "onboarding.intro.notice.body".localized,
                showsImage: false
            ),
            OnboardingPage(
                step: "onboarding.step.1".localized,
                title: "onboarding.welcome.title".localized,
                subtitle: "onboarding.welcome.subtitle".localized,
                description: "onboarding.welcome.description".localized,
                staticImageName: "ProfileScreen1"
            ),
            OnboardingPage(
                step: "onboarding.step.2".localized,
                title: "onboarding.match.title".localized,
                subtitle: "onboarding.match.subtitle".localized,
                description: "onboarding.match.description".localized,
                staticImageName: "Home"
            ),
            OnboardingPage(
                step: "onboarding.step.3".localized,
                title: "onboarding.communication.title".localized,
                subtitle: "onboarding.communication.subtitle".localized,
                description: "onboarding.communication.description".localized,
                staticImageName: "Chat1"
            )
        ]
    }
    
    var body: some View {
        ZStack {
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
                        let page = pages[currentPage]
                        let resolvedY = pinnedSlideshowY ?? anchor.map { geometry[$0].midY }
                        
                        if page.showsImage, page.staticImageName == nil, let resolvedY {
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
                
                // Always reserve space so nav/dots don't shift when this is hidden on later pages.
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
                .opacity(currentPage == pages.count - 1 ? 1 : 0)
                .allowsHitTesting(currentPage == pages.count - 1)
                
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
            
            HStack {
                Button(action: {
                    isDarkMode.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.headline)
                            .foregroundColor(isDarkMode ? .yellow : .orange)
                        Text(isDarkMode ? "settings.light.mode".localized : "settings.dark.mode".localized)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
                
                Spacer()
                
                Button(action: {
                    showingLanguageModal = true
                }) {
                    HStack(spacing: 6) {
                        Text(currentLanguageFlag)
                            .font(.headline)
                        Text(currentLanguageName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    let step: String?
    let title: String
    let subtitle: String
    let description: String
    var notice: String? = nil
    var noticeLead: String? = nil
    var noticeBody: String? = nil
    var showsImage: Bool = true
    /// When set, shows this asset as-is (no frame) instead of the welcome slideshow.
    var staticImageName: String? = nil
    
    var hasNotice: Bool {
        notice != nil || (noticeLead != nil && noticeBody != nil)
    }
}

/// Side-peek carousel for onboarding step images.
struct OnboardingImageCarousel: View {
    static let stepImageNames = ["ProfileScreen1", "Home", "Chat1"]
    
    let currentImageName: String
    let imageNames: [String]
    
    private var isLargeScreen: Bool {
        UIScreen.main.bounds.height >= 900
    }
    
    private var centerMaxHeight: CGFloat {
        isLargeScreen ? 220 : 260
    }
    
    private var sideMaxHeight: CGFloat {
        isLargeScreen ? 160 : 190
    }
    
    private let sideOpacity: Double = 0.35
    private let sideOverlap: CGFloat = -36
    
    var body: some View {
        let index = imageNames.firstIndex(of: currentImageName) ?? 0
        let leftName = imageNames[(index - 1 + imageNames.count) % imageNames.count]
        let rightName = imageNames[(index + 1) % imageNames.count]
        
        HStack(spacing: sideOverlap) {
            sideImage(named: leftName)
            Image(currentImageName)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: centerMaxHeight)
                .zIndex(1)
            sideImage(named: rightName)
        }
        .frame(maxWidth: .infinity)
        .frame(height: centerMaxHeight)
    }
    
    private func sideImage(named name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: sideMaxHeight)
            .opacity(sideOpacity)
            .zIndex(0)
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 30) {
            if page.hasNotice {
                Spacer()
                    .frame(height: 12)
            } else {
                Spacer(minLength: 12)
            }
            
            if page.showsImage {
                if let staticImageName = page.staticImageName {
                    OnboardingImageCarousel(
                        currentImageName: staticImageName,
                        imageNames: OnboardingImageCarousel.stepImageNames
                    )
                } else {
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
                }
            }
            
            // Text content — original sizes
            VStack(spacing: page.showsImage ? 40 : 50) {
                if let step = page.step {
                    Text(step)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if page.showsImage {
                    Text(page.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 4) {
                        Text("onboarding.intro.title.line1".localized)
                            .font(.system(size: 34, weight: .bold))
                        Text("onboarding.intro.title.line2".localized)
                            .font(.system(size: 48, weight: .bold))
                    }
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 80)
                }
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(4)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            
            if page.hasNotice {
                noticeCard
                    .frame(maxWidth: .infinity, maxHeight: noticeMaxHeight, alignment: .top)
                    .padding(.top, 20)
                Spacer(minLength: 12)
            } else {
                Spacer(minLength: 12)
            }
        }
        .padding(.horizontal, 20)
    }
    
    /// Taller notice on large phones (e.g. iPhone 15 Plus / Pro Max).
    private var noticeMaxHeight: CGFloat {
        UIScreen.main.bounds.height >= 900 ? 400 : 180
    }
    
    @ViewBuilder
    private var noticeCard: some View {
        ScrollView(showsIndicators: true) {
            Group {
                if let noticeLead = page.noticeLead, let noticeBody = page.noticeBody {
                    (
                        Text(noticeLead)
                            .font(.subheadline)
                            .fontWeight(.bold)
                        + Text(" ")
                            .font(.subheadline)
                        + Text(noticeBody)
                            .font(.subheadline)
                    )
                } else if let notice = page.notice {
                    Text(notice)
                        .font(.subheadline)
                }
            }
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
    }
}

#Preview {
    OnboardingView()
}
