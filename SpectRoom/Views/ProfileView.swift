import SwiftUI
import Foundation

// MARK: - Energy Level Option Enum (shared with ProfileEditView)
private enum EnergyLevelOption: Int, CaseIterable {
    case quietAndCalm = 0
    case softAndSteady = 1
    case balancedEnergy = 2
    case readyToChat = 3
    case fullySocialMode = 4
    
    var title: String {
        switch self {
        case .quietAndCalm:
            return "profile.edit.energy.quiet.calm".localized
        case .softAndSteady:
            return "profile.edit.energy.soft.steady".localized
        case .balancedEnergy:
            return "profile.edit.energy.balanced".localized
        case .readyToChat:
            return "profile.edit.energy.ready.chat".localized
        case .fullySocialMode:
            return "profile.edit.energy.fully.social".localized
        }
    }
    
    var color: Color {
        switch self {
        case .quietAndCalm:
            return Color(hex: "#950404")
        case .softAndSteady:
            return Color(hex: "#da0808")
        case .balancedEnergy:
            return Color(hex: "#ff9323")
        case .readyToChat:
            return Color(hex: "#C9A000")
        case .fullySocialMode:
            return Color(hex: "#69c440")
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showingEditView = false
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Header Section
                    profileHeaderSection
                    
                    // My Photos Section (moved right after profile photo)
                    myPhotosSection
                    
                    // Age Section
                    ageSection
                    
                    // Location Section
                    locationSection
                    
                    // Energy Level Section
                    energyLevelSection
                    
                    // Gender & Preferences Section
                    genderPreferencesSection
                    
                    // About Me Section
                    aboutMeSection
                    
                    // My Interests Section
                    myInterestsSection
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 100) // Increased bottom padding
            }
            .background(
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
            .navigationTitle(profileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 16)
                        Text(profileTitle)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("profile.edit".localized) {
                        showingEditView = true
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // Refresh user data from Firebase to get the latest information
            Task {
                await FirebaseAuthService.shared.forceRefreshUserData()
                // Debug: Check what interests are loaded
                if let user = appState.currentUser {
                    print("🔍 ProfileView - User interests: \(user.interests)")
                    print("🔍 ProfileView - User interests count: \(user.interests.count)")
                } else {
                    print("🔍 ProfileView - No current user found")
                }
            }
        }
        .sheet(isPresented: $showingEditView) {
            ProfileEditView(isMandatoryCompletion: false)
                .environmentObject(appState)
        }
        .onChange(of: showingEditView) { _, isPresented in
            // Refresh user data when edit sheet is dismissed
            if !isPresented {
                Task {
                    await FirebaseAuthService.shared.forceRefreshUserData()
                }
            }
        }
        .sheet(isPresented: $showingPhotoViewer) {
            if let user = appState.currentUser {
                // Combine profile photo and gallery photos, with profile photo first
                let allPhotos: [String] = {
                    var photos = user.photos
                    if let profilePhotoURL = user.profilePhotoURL, !profilePhotoURL.isEmpty {
                        photos.insert(profilePhotoURL, at: 0)
                    }
                    return photos
                }()
                
                if !allPhotos.isEmpty {
                    PhotoViewerModal(
                        photos: allPhotos,
                        selectedIndex: $selectedPhotoIndex
                    )
                    .presentationBackground(.clear)
                }
            }
        }
    }
    
    // MARK: - Helpers
    private var profileTitle: String {
        return "profile.my.title".localized
    }
    
    // MARK: - Profile Header Section
    private var profileHeaderSection: some View {
        ProfileMainPhotoCard(
            imageURL: appState.currentUser?.profilePhotoURL,
            onTap: {
                guard let user = appState.currentUser else { return }
                let hasProfilePhoto = user.profilePhotoURL != nil && !(user.profilePhotoURL?.isEmpty ?? true)
                let hasGalleryPhotos = !user.photos.isEmpty
                if hasProfilePhoto || hasGalleryPhotos {
                    selectedPhotoIndex = 0
                    showingPhotoViewer = true
                }
            }
        )
    }
    
    // MARK: - Age Section
    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.age".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            if let user = appState.currentUser {
                Text("\(user.age) " + "profile.years.old".localized)
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.location".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text(appState.currentUser?.location.displayString.isEmpty == false ? appState.currentUser?.location.displayString ?? "" : "profile.location.not.specified".localized)
                .font(.subheadline)
                .foregroundColor(appState.currentUser?.location.displayString.isEmpty == false ? .primary : .secondary)
            
            Text("profile.location.privacy.notice".localized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Energy Level Section
    private var energyLevelSection: some View {
        let energyOption = EnergyLevelOption(rawValue: appState.currentUser?.energyLevel ?? 4) ?? .fullySocialMode
        let levelColor = energyOption.color
        let levelBinding = Binding<Int>(
            get: { appState.currentUser?.energyLevel ?? 4 },
            set: { _ in }
        )
        
        return VStack(alignment: .leading, spacing: 14) {
            Text("profile.edit.energy.level".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text(energyOption.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(levelColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
                )
                .multilineTextAlignment(.center)
            
            EnergyLevelSlider(
                energyLevel: levelBinding,
                levelColor: levelColor,
                isEnabled: false
            )
            .frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - About Me Section
    private var aboutMeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.about.me".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            if let user = appState.currentUser, !user.bio.isEmpty {
                Text(user.bio)
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                Text("profile.no.bio".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            if let user = appState.currentUser, user.shareLifestyle {
                Text("profile.lifestyle.title".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(formattedLifestyle(user.lifestyle))
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            if let user = appState.currentUser, user.shareBodyType, !user.bodyType.isEmpty {
                Text("profile.body.type".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(formattedBodyType(user.bodyType))
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            if let user = appState.currentUser, user.shareIdealFirstDate, !user.idealFirstDate.isEmpty {
                Text("profile.ideal.first.date".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(formattedIdealFirstDate(user.idealFirstDate))
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            if let user = appState.currentUser, user.shareSensoryPreferences, !user.sensoryPreferences.isEmpty {
                Text("profile.sensory.preferences".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(SensoryPreferenceOption.formattedTitles(user.sensoryPreferences))
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Interests Section
    private var myInterestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.interests".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            if let user = appState.currentUser, !user.interests.isEmpty {
                let _ = print("🔍 myInterestsSection - Displaying \(user.interests.count) interests: \(user.interests)")
                Text(user.interests.map { localizedInterest($0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                // Debug: Log why no interests are showing
                let _ = print("🔍 myInterestsSection - No interests to display. User: \(appState.currentUser != nil), Interests count: \(appState.currentUser?.interests.count ?? 0)")
                Text("profile.no.interests".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Gender & Preferences Section
    private var genderPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.preferences".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            if let user = appState.currentUser {
                VStack(alignment: .leading, spacing: 8) {
                    // Combined display if both are available
                    if !user.gender.isEmpty && !user.interestedIn.isEmpty {
                        Text("profile.im.a".localized + " \(formatGender(user.gender)), " + "profile.interested.in".localized + " \(formatInterestedIn(user.interestedIn))")
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                    } else if !user.gender.isEmpty {
                        // Show only gender if no preferences set
                        Text("profile.im.a".localized + " \(formatGender(user.gender))")
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                    } else if !user.interestedIn.isEmpty {
                        // Show only preferences if no gender set
                        Text("profile.interested.in".localized.capitalized + " \(formatInterestedIn(user.interestedIn))")
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                    }
                    
                    let hasGenderOrInterestedIn = !user.gender.isEmpty || !user.interestedIn.isEmpty
                    let hasLookingFor = !user.lookingFor.isEmpty
                    
                    // Divider between gender/interested in and looking for
                    if hasGenderOrInterestedIn && hasLookingFor {
                        Divider()
                            .frame(height: 2)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 4)
                    }
                    
                    // Looking for display (including "Not sure yet")
                    if hasLookingFor {
                        Text("profile.looking.for".localized + " \(formatLookingFor(user.lookingFor))")
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    
                    // Divider between looking for and preferred age
                    let userAge = user.age
                    let defaultMin = userAge
                    let defaultMax = min(userAge + 5, 70)
                    let hasCustomPreferredAge = user.preferredAgeMin != defaultMin || user.preferredAgeMax != defaultMax
                    if hasLookingFor && hasCustomPreferredAge {
                        Divider()
                            .frame(height: 2)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 4)
                    }
                    
                    // Preferred age display (only show if different from default range)
                    if hasCustomPreferredAge {
                        Text(String(format: "profile.preferred.age".localized, "\(user.preferredAgeMin)", "\(user.preferredAgeMax)"))
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                    }
                }
            } else {
                Text("profile.no.preferences".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Helper function to format interested in preferences
    private func formatInterestedIn(_ preferences: [String]) -> String {
        if preferences.contains("Anyone") {
            return "profile.interested.anyone".localized
        } else if preferences.isEmpty {
            return "profile.no.one".localized
        } else {
            let formatted = preferences.map { formatPreference($0) }
            return formatted.joined(separator: " / ")
        }
    }
    
    // MARK: - Helper function to format gender
    private func formattedLifestyle(_ lifestyle: String) -> String {
        switch lifestyle {
        case "independent":
            return "profile.edit.lifestyle.independent".localized
        case "familySupport":
            return "profile.edit.lifestyle.family".localized
        case "assistedSetting":
            return "profile.edit.lifestyle.assisted".localized
        case "preferNot":
            // Migration: handle old "preferNot" value gracefully
            return ""
        default:
            return lifestyle.isEmpty ? "" : "profile.lifestyle.placeholder".localized
        }
    }
    
    private func formattedBodyType(_ bodyType: String) -> String {
        switch bodyType {
        case "slim":
            return "profile.edit.body.type.slim".localized
        case "average":
            return "profile.edit.body.type.average".localized
        case "athletic":
            return "profile.edit.body.type.athletic".localized
        case "fullBodied":
            return "profile.edit.body.type.full.bodied".localized
        case "preferNot":
            // Migration: handle old "preferNot" value gracefully
            return ""
        default:
            return bodyType
        }
    }
    
    // MARK: - Helper function to localize interest names
    private func localizedInterest(_ interest: String) -> String {
        let key = "profile.edit.interest.\(interest.lowercased())"
        let localized = key.localized
        // If localization key doesn't exist, return original
        return localized == key ? interest : localized
    }
    
    // MARK: - Helper function to format ideal first date
    private func formattedIdealFirstDate(_ idealFirstDate: [String]) -> String {
        let formatted = idealFirstDate.map { option in
            switch option {
            case "relaxingParkWalk":
                return "profile.edit.ideal.date.relaxing.park.walk".localized
            case "cozyCafeMeet":
                return "profile.edit.ideal.date.cozy.cafe.meet".localized
            case "museumGalleryStroll":
                return "profile.edit.ideal.date.museum.gallery.stroll".localized
            case "cinemaMovieNight":
                return "profile.edit.ideal.date.cinema.movie.night".localized
            case "friendlyVideoChat":
                return "profile.edit.ideal.date.friendly.video.chat".localized
            default:
                return option
            }
        }
        return formatted.joined(separator: ", ")
    }
    
    private func formatGender(_ gender: String) -> String {
        // If gender is "Other", we need to get the custom text from the user data
        // For now, we'll assume the custom text is stored in the gender field itself
        // This will be updated when we fix the ProfileEditView logic
        return gender.lowercased()
    }
    
    // MARK: - Helper function to format individual preference
    private func formatPreference(_ preference: String) -> String {
        if preference == "Not sure yet" {
            return "profile.edit.looking.not.sure".localized
        }
        return preference
    }
    
    // MARK: - Helper function to format looking for
    private func formatLookingFor(_ lookingFor: [String]) -> String {
        if lookingFor.isEmpty {
            return "profile.nothing.specific".localized
        } else {
            let formatted = lookingFor.map { formatPreference($0) }
            return formatted.joined(separator: " / ")
        }
    }
    
    // MARK: - My Photos Section
    private var myPhotosSection: some View {
        ProfileGalleryPhotosCard(
            photoURLs: appState.currentUser?.photos ?? [],
            onSelectRemote: { index in
                selectedPhotoIndex = index + 1
                showingPhotoViewer = true
            }
        )
    }
}

// MARK: - FlowLayout for Interests
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: ProposedViewSize(result.sizes[index]))
        }
    }
}

struct FlowResult {
    var size: CGSize
    var positions: [CGPoint]
    var sizes: [CGSize]
    
    init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let subviewSize = subview.sizeThatFits(.unspecified)
            
            // Check if we need to wrap to next line
            if currentX + subviewSize.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            sizes.append(subviewSize)
            
            currentX += subviewSize.width + spacing
            lineHeight = max(lineHeight, subviewSize.height)
        }
        
        self.positions = positions
        self.sizes = sizes
        self.size = CGSize(
            width: maxWidth,
            height: currentY + lineHeight
        )
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppStateManager.shared)
}
