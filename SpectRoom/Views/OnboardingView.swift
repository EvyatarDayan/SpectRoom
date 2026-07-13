//
//  OnboardingView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

struct OnboardingView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "en"
    @State private var showingLanguageModal = false
    
    var pages: [OnboardingPage] {
        [
            OnboardingPage(
                title: "onboarding.welcome.title".localized,
                subtitle: "onboarding.welcome.subtitle".localized,
                image: "heart.fill",
                description: "onboarding.welcome.description".localized
            ),
            OnboardingPage(
                title: "onboarding.match.title".localized,
                subtitle: "onboarding.match.subtitle".localized,
                image: "person.2.fill",
                description: "onboarding.match.description".localized
            ),
            OnboardingPage(
                title: "onboarding.communication.title".localized,
                subtitle: "onboarding.communication.subtitle".localized,
                image: "message.fill",
                description: "onboarding.communication.description".localized
            ),
            OnboardingPage(
                title: "onboarding.settings.title".localized,
                subtitle: "onboarding.settings.subtitle".localized,
                image: "gearshape.fill",
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
                // Content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)
                
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
                            appState.completeOnboarding()
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

struct OnboardingPage {
    let title: String
    let subtitle: String
    let image: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Image
            Image(systemName: page.image)
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            // Text content
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
