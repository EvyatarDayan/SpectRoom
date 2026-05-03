//
//  AboutView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-11-16.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // About SpectRoom Title
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About SpectRoom")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.top, 70)
                            
                            Text("SpectRoom is a dating and connection app thoughtfully designed for autistic adults and the broader neurodivergent community.")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Text("We believe that everyone deserves a space where communication styles are understood, sensory needs are respected, and individuality is celebrated — without judgment, pressure, or misunderstanding.")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // SpectRoom Focus Section
                        sectionView(
                            title: "SpectRoom focuses on clarity, safety, and comfort.",
                            content: """
                            Our design considers the unique needs of neurodivergent users, such as reduced sensory overload, structured communication, clear boundaries, and personalized support settings. Whether you're seeking friendship, dating, or deeper relationships, SpectRoom offers a calm and supportive environment where you can express yourself at your own pace.
                            """
                        )
                        
                        // Mission Section
                        sectionView(
                            title: "Our mission is simple:",
                            content: """
                            Create a meaningful, inclusive space where neurodivergent people can connect authentically — and feel safe while doing so.
                            """
                        )
                        
                        // Core Values Section
                        sectionView(
                            title: "SpectRoom is built with respect, empathy, and accessibility at its core.",
                            content: """
                            You're welcome here.
                            """
                        )
                        
                        // Divider before Abashelari Productions section
                        Divider()
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        
                        // About Abashelari Productions Title
                        VStack(alignment: .leading, spacing: 12) {
                            Text("About Abashelari Productions")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text("Abashelari Productions is an independent technology and creative development studio based in Stockholm.")
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Text("We specialize in crafting thoughtful digital experiences with a focus on accessibility, education, and everyday empowerment. Our work spans mobile apps, interactive tools, and content designed to make life easier, more inclusive, and more enjoyable for users of all backgrounds.")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 20)
                        
                        // Philosophy Section
                        sectionView(
                            title: "Founded on a passion for innovation and human-centered design, Abashelari Productions develops products that combine technical reliability with emotional intelligence.",
                            content: """
                            We believe in building software that respects users, simplifies complex challenges, and brings real value to people's lives.
                            """
                        )
                        
                        // Closing Section
                        sectionView(
                            title: "",
                            content: """
                            From children's educational games to community-driven platforms like SpectRoom, our goal is to create meaningful digital products that leave a positive impact — one app at a time.
                            """
                        )
                        
                        Spacer().frame(height: 40)
                            .padding(.bottom, 70)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("About")
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func sectionView(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    AboutView()
}

