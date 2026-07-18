import SwiftUI
import PhotosUI
import MapKit
import Foundation

struct ProfileEditView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Parameters
    let isMandatoryCompletion: Bool
    
    init(isMandatoryCompletion: Bool = false) {
        self.isMandatoryCompletion = isMandatoryCompletion
    }
    
    // MARK: - State Variables
    @State private var name: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var location: String = ""
    @State private var locationLatitude: Double? = nil
    @State private var locationLongitude: Double? = nil
    @State private var bio: String = ""
    @State private var existingPhotos: [String] = []
    @State private var newPhotos: [UIImage] = []
    @State private var photosToDelete: Set<String> = []
    @State private var selectedInterests: Set<String> = []
    @State private var customInterest: String = ""
    @State private var gender: String = ""
    @State private var customGender: String = ""
    @State private var selectedInterestedIn: Set<String> = []
    @State private var customInterestedIn: String = ""
    @State private var selectedLookingFor: Set<String> = []
    @State private var customLookingFor: String = ""
    @State private var preferredAgeMin: Double = 18
    @State private var preferredAgeMax: Double = 80
    @State private var energyLevel: Int = 4 // Default to "Fully Social Mode" (index 4, locked to 0-4)
    
    // MARK: - Suggested Interests
    private let suggestedInterests = [
        "Photography", "Music", "Art", "Reading", "Cooking", "Travel", "Sports", "Gaming",
        "Movies", "Nature", "Technology", "Fitness", "Dancing", "Writing", "Gardening",
        "Animals", "Science", "History", "Languages", "Volunteering"
    ]
    private let lifestyleColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
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
                return Color(hex: "#f1dc32")
            case .fullySocialMode:
                return Color(hex: "#69c440")
            }
        }
    }
    
    private enum LifestyleOption: String, CaseIterable {
        case independent
        case familySupport
        case assistedSetting
        
        var title: String {
            switch self {
            case .independent:
                return "profile.edit.lifestyle.independent".localized
            case .familySupport:
                return "profile.edit.lifestyle.family".localized
            case .assistedSetting:
                return "profile.edit.lifestyle.assisted".localized
            }
        }
    }
    
    private enum BodyTypeOption: String, CaseIterable {
        case slim
        case average
        case athletic
        case fullBodied
        
        var title: String {
            switch self {
            case .slim:
                return "profile.edit.body.type.slim".localized
            case .average:
                return "profile.edit.body.type.average".localized
            case .athletic:
                return "profile.edit.body.type.athletic".localized
            case .fullBodied:
                return "profile.edit.body.type.full.bodied".localized
            }
        }
    }
    
    private enum IdealFirstDateOption: String, CaseIterable {
        case relaxingParkWalk
        case cozyCafeMeet
        case museumGalleryStroll
        case cinemaMovieNight
        case friendlyVideoChat
        
        var title: String {
            switch self {
            case .relaxingParkWalk:
                return "profile.edit.ideal.date.relaxing.park.walk".localized
            case .cozyCafeMeet:
                return "profile.edit.ideal.date.cozy.cafe.meet".localized
            case .museumGalleryStroll:
                return "profile.edit.ideal.date.museum.gallery.stroll".localized
            case .cinemaMovieNight:
                return "profile.edit.ideal.date.cinema.movie.night".localized
            case .friendlyVideoChat:
                return "profile.edit.ideal.date.friendly.video.chat".localized
            }
        }
    }

// MARK: - UI State
    @State private var showingImagePicker = false
    @State private var showingGalleryPicker = false
    @State private var isEditingProfilePhoto = false
    @State private var profilePhoto: UIImage? = nil
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingAddressSearch = false
    @State private var selectedLifestyle = ""
    @State private var isDataLoaded = false // Track when profile data is loaded
    @State private var shareLifestyle = false
    @State private var shareBodyType = false
    @State private var selectedBodyType: String = ""
    @State private var shareIdealFirstDate = false
    @State private var selectedIdealFirstDate: [String] = []
    @State private var shareSensoryPreferences = false
    @State private var selectedSensoryPreferences: [String] = []
    
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile Photo Section
                        profilePhotoSection
                        
                        // My Photos Section
                        myPhotosSection
                        
                        // Name Section
                        nameSection
                        
                        // Date of Birth Section
                        dateOfBirthSection
                        
                        // Location Section
                        locationSection
                        
                        // Energy Level Section
                        energyLevelSection
                        
                        // About Me Section
                        aboutMeSection
                        
                        // My Interests Section
                        myInterestsSection
                        
                        // Gender & Preferences Section
                        genderPreferencesSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .background(
                    Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                )
                .opacity(isDataLoaded ? 1.0 : 0.3) // Gray out when loading
                .disabled(!isDataLoaded) // Disable interaction when loading
                
                // Loading overlay
                if !isDataLoaded {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.blue)
                        Text("profile.edit.loading".localized)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground).opacity(0.8))
                }
            }
            .navigationTitle(isMandatoryCompletion ? "profile.edit.complete.title".localized : "profile.edit.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("profile.edit.cancel".localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("profile.edit.save".localized) {
                        if isFormValid() {
                            saveProfile()
                        } else {
                            // Show validation errors with bullet points
                            alertMessage = getFormattedValidationErrors()
                            showingAlert = true
                        }
                    }
                    .disabled(isLoading || !isDataLoaded)
                }
            }
        }
        .onAppear {
            // Reset loading state
            isDataLoaded = false
            
            // Force refresh user data from Firebase first, then load profile
            Task {
                // Force refresh user data from Firebase to get latest data
                await FirebaseAuthService.shared.forceRefreshUserData()
                
                await MainActor.run {
                    // Load profile data with fresh data from Firebase
                    loadCurrentProfile()
                    
                    // Mark data as loaded
                    isDataLoaded = true
                }
                
                // Sync photos from Firebase Storage (in background)
                Task {
                    await FirebaseAuthService.shared.syncPhotosFromStorage()
                    
                    // Clean up any orphaned profile photos (in background)
                    if let userID = FirebaseAuthService.shared.auth.currentUser?.uid {
                        await PhotoStorageService.shared.cleanupOrphanedProfilePhotos(
                            for: userID,
                            currentProfilePhotoURL: appState.currentUser?.profilePhotoURL
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $profilePhoto, isEditingProfilePhoto: isEditingProfilePhoto)
        }
        .sheet(isPresented: $showingGalleryPicker) {
            GalleryImagePicker(images: $newPhotos)
        }
        .sheet(isPresented: $showingAddressSearch) {
            AddressSearchView(
                selectedAddress: $location,
                selectedLatitude: $locationLatitude,
                selectedLongitude: $locationLongitude
            )
        }
        .alert("profile.edit.profile.incomplete".localized, isPresented: $showingAlert) {
            Button("common.ok".localized) { }
        } message: {
            Text(alertMessage)
        }
        .overlay {
            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Text("profile.edit.saving".localized)
                        .font(.headline)
                        .foregroundColor(.white)
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
                .frame(width: 200, height: 120)
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Profile Photo Section
    private var profilePhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.profile.photo".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            ProfileMainPhotoCard(
                imageURL: profilePhoto == nil ? appState.currentUser?.profilePhotoURL : nil,
                localImage: profilePhoto,
                placeholderSystemName: "camera",
                showsCameraBadge: true,
                onTap: {
                    isEditingProfilePhoto = true
                    showingImagePicker = true
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Name Section
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("profile.edit.name".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                validationCheckmark(isValid: isNameValid)
            }
            
            TextField("profile.edit.name.placeholder".localized, text: $name)
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Date of Birth Section
    private var dateOfBirthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("profile.edit.date.of.birth".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                validationCheckmark(isValid: isAgeValid)
            }
            
            HStack {
                DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                    .labelsHidden()
                    .padding()
                    .background(Color(.systemGroupedBackground))
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                Spacer()
                
                Text(String(format: "profile.edit.my.age".localized, "\(calculateAge(from: dateOfBirth))"))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
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
            HStack {
                Text("profile.my.location".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                validationCheckmark(isValid: isLocationValid)
            }
            
            HStack {
                Text(location.isEmpty ? "profile.edit.location.placeholder".localized : location)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                Button(action: {
                    showingAddressSearch = true
                }) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Energy Level Section
    private var energyLevelSection: some View {
        let currentOption = EnergyLevelOption(rawValue: energyLevel) ?? .fullySocialMode
        let levelColor = currentOption.color
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.energy.level".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Energy level display
                HStack {
                    Text(currentOption.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(levelColor)
                    
                    Spacer()
                }
                
                // Single slider with discrete steps (locked to 5 levels: 0, 1, 2, 3, 4)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        // Active track (from start to current position)
                        Rectangle()
                            .fill(levelColor)
                            .frame(height: 6)
                            .cornerRadius(3)
                            .frame(width: CGFloat(energyLevel) / 4.0 * geometry.size.width)
                        
                        // Thumb
                        Circle()
                            .fill(levelColor)
                            .frame(width: 20, height: 20)
                            .shadow(radius: 2)
                            .offset(x: CGFloat(energyLevel) / 4.0 * geometry.size.width - 10)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Calculate which discrete level the drag is closest to
                                        // Snap to one of 5 positions: 0, 1, 2, 3, 4
                                        let position = value.location.x / geometry.size.width
                                        let newLevel = Int(round(position * 4.0))
                                        let clampedLevel = max(0, min(newLevel, 4))
                                        energyLevel = clampedLevel
                                    }
                            )
                    }
                }
                .frame(height: 20)
            }
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("profile.edit.about.me".localized)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    validationCheckmark(isValid: isBioValid)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: bioTextBinding)
                        .frame(height: 200)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    // Character counter
                    HStack {
                        Spacer()
                        Text(characterCounterText)
                            .font(.caption)
                            .foregroundColor(bio.count >= 500 ? .red : .secondary)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("profile.edit.share.lifestyle".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $shareLifestyle)
                        .labelsHidden()
                }
                
                if shareLifestyle {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(LifestyleOption.allCases, id: \.self) { option in
                            Button(action: {
                                selectedLifestyle = option.rawValue
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedLifestyle == option.rawValue ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                    Text(option.title)
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(LifestyleOption.allCases, id: \.self) { option in
                            HStack(spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text(option.title)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Share Body Type Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("profile.edit.share.body.type".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $shareBodyType)
                        .labelsHidden()
                }
                
                if shareBodyType {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(BodyTypeOption.allCases, id: \.self) { option in
                            Button(action: {
                                selectedBodyType = option.rawValue
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedBodyType == option.rawValue ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                    Text(option.title)
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(BodyTypeOption.allCases, id: \.self) { option in
                            HStack(spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text(option.title)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Ideal First Date Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("profile.edit.ideal.first.date".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $shareIdealFirstDate)
                        .labelsHidden()
                }
                
                if shareIdealFirstDate {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(IdealFirstDateOption.allCases, id: \.self) { option in
                            Button(action: {
                                if selectedIdealFirstDate.contains(option.rawValue) {
                                    selectedIdealFirstDate.removeAll { $0 == option.rawValue }
                                } else {
                                    selectedIdealFirstDate.append(option.rawValue)
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedIdealFirstDate.contains(option.rawValue) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                    Text(option.title)
                                        .foregroundColor(.primary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(IdealFirstDateOption.allCases, id: \.self) { option in
                            HStack(spacing: 12) {
                                Image(systemName: "square")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text(option.title)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Sensory Preferences Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("profile.edit.sensory.preferences".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Toggle("", isOn: $shareSensoryPreferences)
                        .labelsHidden()
                }
                
                if shareSensoryPreferences {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(SensoryPreferenceOption.allCases, id: \.self) { option in
                            Button(action: {
                                if selectedSensoryPreferences.contains(option.rawValue) {
                                    selectedSensoryPreferences.removeAll { $0 == option.rawValue }
                                } else {
                                    selectedSensoryPreferences.append(option.rawValue)
                                }
                            }) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: selectedSensoryPreferences.contains(option.rawValue) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.title)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(option.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(SensoryPreferenceOption.allCases, id: \.self) { option in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "square")
                                    .font(.system(size: 18))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .foregroundColor(.gray.opacity(0.5))
                                        .multilineTextAlignment(.leading)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.4))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("profile.preferences".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                validationCheckmark(isValid: isGenderValid)
            }
            
            // I am section
            VStack(alignment: .leading, spacing: 8) {
                Text("profile.edit.i.am".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 12) {
                    // Man button
                    Button(action: {
                        gender = "Man"
                        customGender = ""
                    }) {
                        Text("profile.edit.gender.man".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(gender == "Man" ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(gender == "Man" ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Woman button
                    Button(action: {
                        gender = "Woman"
                        customGender = ""
                    }) {
                        Text("profile.edit.gender.woman".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(gender == "Woman" ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(gender == "Woman" ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Non-binary button
                    Button(action: {
                        gender = "Non-binary"
                        customGender = ""
                    }) {
                        Text("profile.edit.gender.nonbinary".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(gender == "Non-binary" ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(gender == "Non-binary" ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Interested in section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("profile.edit.interested.in".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    validationCheckmark(isValid: isInterestedInValid)
                }
                
                HStack(spacing: 12) {
                    // Man button
                    Button(action: {
                        if selectedInterestedIn.contains("Man") {
                            selectedInterestedIn.remove("Man")
                        } else {
                            selectedInterestedIn.insert("Man")
                        }
                    }) {
                        Text("profile.edit.gender.man".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedInterestedIn.contains("Man") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedInterestedIn.contains("Man") ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Woman button
                    Button(action: {
                        if selectedInterestedIn.contains("Woman") {
                            selectedInterestedIn.remove("Woman")
                        } else {
                            selectedInterestedIn.insert("Woman")
                        }
                    }) {
                        Text("profile.edit.gender.woman".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedInterestedIn.contains("Woman") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedInterestedIn.contains("Woman") ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Non-binary button
                    Button(action: {
                        if selectedInterestedIn.contains("Non-binary") {
                            selectedInterestedIn.remove("Non-binary")
                        } else {
                            selectedInterestedIn.insert("Non-binary")
                        }
                    }) {
                        Text("profile.edit.gender.nonbinary".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedInterestedIn.contains("Non-binary") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedInterestedIn.contains("Non-binary") ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Anyone button
                    Button(action: {
                        if selectedInterestedIn.contains("Anyone") {
                            selectedInterestedIn.remove("Anyone")
                        } else {
                            selectedInterestedIn.insert("Anyone")
                        }
                    }) {
                        Text("profile.edit.interested.anyone".localized)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedInterestedIn.contains("Anyone") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedInterestedIn.contains("Anyone") ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                
                // Show selected custom preferences (only for old custom text entries)
                if !selectedInterestedIn.isEmpty {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100))
                    ], spacing: 8) {
                        ForEach(Array(selectedInterestedIn), id: \.self) { preference in
                            if preference != "Man" && preference != "Woman" && preference != "Non-binary" && preference != "Anyone" {
                                HStack {
                                    Text(preference)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                    
                                    Button(action: {
                                        selectedInterestedIn.remove(preference)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Looking for section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("profile.edit.looking.for".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    validationCheckmark(isValid: isLookingForValid)
                }
                
                HStack(spacing: 12) {
                    // Friendship button
                    Button(action: {
                        if selectedLookingFor.contains("Friendship") {
                            selectedLookingFor.remove("Friendship")
                        } else {
                            selectedLookingFor.insert("Friendship")
                        }
                    }) {
                        Text("profile.edit.looking.friendship".localized)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedLookingFor.contains("Friendship") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedLookingFor.contains("Friendship") ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Relationship button
                    Button(action: {
                        if selectedLookingFor.contains("Relationship") {
                            selectedLookingFor.remove("Relationship")
                        } else {
                            selectedLookingFor.insert("Relationship")
                        }
                    }) {
                        Text("profile.edit.looking.relationship".localized)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedLookingFor.contains("Relationship") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedLookingFor.contains("Relationship") ? .white : .primary)
                            .cornerRadius(20)
                    }
                    
                    // Not sure yet button
                    Button(action: {
                        if selectedLookingFor.contains("Not sure yet") {
                            selectedLookingFor.remove("Not sure yet")
                        } else {
                            selectedLookingFor.insert("Not sure yet")
                        }
                    }) {
                        Text("profile.edit.looking.not.sure".localized)
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedLookingFor.contains("Not sure yet") ? Color.blue : Color.gray.opacity(0.1))
                            .foregroundColor(selectedLookingFor.contains("Not sure yet") ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 8)
            
            // Preferred Age section
            VStack(alignment: .leading, spacing: 8) {
                Text("profile.edit.preferred.age".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(spacing: 12) {
                    // Age range display
                    HStack {
                        Text("\(Int(preferredAgeMin))-\(Int(preferredAgeMax))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.blue)
                        
                        Spacer()
                    }
                    
                    // Dual range slider
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 6)
                                .cornerRadius(3)
                            
                            // Active range track
                            Rectangle()
                                .fill(Color.blue)
                                .frame(height: 6)
                                .cornerRadius(3)
                                .offset(x: CGFloat(preferredAgeMin - 18) / CGFloat(80 - 18) * geometry.size.width)
                                .frame(width: CGFloat(preferredAgeMax - preferredAgeMin) / CGFloat(80 - 18) * geometry.size.width)
                            
                            // Min thumb
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                                .shadow(radius: 2)
                                .offset(x: CGFloat(preferredAgeMin - 18) / CGFloat(80 - 18) * geometry.size.width - 10)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let newValue = Double(value.location.x / geometry.size.width * CGFloat(80 - 18) + 18)
                                            let clampedValue = max(18, min(newValue, preferredAgeMax))
                                            preferredAgeMin = clampedValue
                                        }
                                )
                            
                            // Max thumb
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                                .shadow(radius: 2)
                                .offset(x: CGFloat(preferredAgeMax - 18) / CGFloat(80 - 18) * geometry.size.width - 10)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            let newValue = Double(value.location.x / geometry.size.width * CGFloat(80 - 18) + 18)
                                            let clampedValue = max(preferredAgeMin, min(newValue, 80))
                                            preferredAgeMax = clampedValue
                                        }
                                )
                        }
                    }
                    .frame(height: 20)
                }
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
            HStack {
                Text("profile.my.interests".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                validationCheckmark(isValid: isInterestsValid)
            }
            
            // Suggested Interests
            VStack(alignment: .leading, spacing: 8) {
//                Text("Select your interests")
//                    .font(.subheadline)
//                    .fontWeight(.medium)
//                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 120))
                ], spacing: 8) {
                    ForEach(suggestedInterests, id: \.self) { interest in
                        Button(action: {
                            if selectedInterests.contains(interest) {
                                selectedInterests.remove(interest)
                            } else {
                                selectedInterests.insert(interest)
                            }
                        }) {
                            Text(localizedInterest(interest))
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(selectedInterests.contains(interest) ? Color.blue : Color.gray.opacity(0.1))
                                .foregroundColor(selectedInterests.contains(interest) ? .white : .primary)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedInterests.contains(interest) ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Photos Section
    private var myPhotosSection: some View {
        ProfileGalleryPhotosCard(
            photoURLs: existingPhotos,
            localImages: newPhotos,
            allowsPaging: false,
            onDeleteRemote: { photoURL in
                deletePhoto(photoURL)
            },
            onDeleteLocal: { index in
                removeNewPhoto(at: index)
            },
            onAdd: {
                showingGalleryPicker = true
            },
            maxRemoteVisible: 5,
            showValidation: isPhotosValid
        )
    }
    
    
    // MARK: - Validation Computed Properties
    private var isNameValid: Bool {
        let nameComponents = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        return nameComponents.count >= 2 && nameComponents.allSatisfy { !$0.isEmpty }
    }
    
    private var isAgeValid: Bool {
        return calculateAge(from: dateOfBirth) >= 18
    }
    
    private var isLocationValid: Bool {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else { return false }
        
        if let latitude = locationLatitude, let longitude = locationLongitude {
            return SwedenLocation.contains(latitude: latitude, longitude: longitude)
        }
        
        return true
    }
    
    private var isBioValid: Bool {
        return bio.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30
    }
    
    private var isPhotosValid: Bool {
        return (existingPhotos.count + newPhotos.count) >= 3
    }
    
    private var isInterestsValid: Bool {
        return selectedInterests.count >= 3
    }
    
    private var isGenderValid: Bool {
        return !gender.isEmpty
    }
    
    private var isLookingForValid: Bool {
        return !selectedLookingFor.isEmpty
    }
    
    private var isInterestedInValid: Bool {
        return !selectedInterestedIn.isEmpty
    }
    
    // MARK: - Character Counter Text
    private var characterCounterText: String {
        let currentCount = bio.count
        
        if currentCount < 30 {
            return String(format: "profile.edit.character.counter.min".localized, "\(30 - currentCount)")
        } else if currentCount >= 500 {
            return String(format: "profile.edit.character.counter.max".localized, "500")
        } else {
            return String(format: "profile.edit.character.counter.max".localized, "\(500 - currentCount)")
        }
    }
    
    // MARK: - Bio Text Binding with Character Limit
    private var bioTextBinding: Binding<String> {
        Binding(
            get: { bio },
            set: { newValue in
                if newValue.count <= 500 {
                    bio = newValue
                }
            }
        )
    }
    
    // MARK: - Validation Checkmark View
    private func validationCheckmark(isValid: Bool) -> some View {
        Image(systemName: "checkmark")
            .foregroundColor(isValid ? .green : .gray)
            .font(.system(size: 20, weight: .bold))
    }
    
    // MARK: - Helper Methods
    private func loadCurrentProfile() {
        // Clear any local photo cache first
        profilePhoto = nil
        newPhotos = []
        photosToDelete = []
        
        if let user = appState.currentUser {
            name = user.name
            // Load actual date of birth from database if available, otherwise calculate from age
            if let savedDateOfBirth = user.dateOfBirth {
                dateOfBirth = savedDateOfBirth
            } else {
                // Fallback: Convert age to date of birth (approximate)
                let calendar = Calendar.current
                dateOfBirth = calendar.date(byAdding: .year, value: -user.age, to: Date()) ?? Date()
            }
            location = user.location.displayString
            locationLatitude = user.location.latitude
            locationLongitude = user.location.longitude
            bio = user.bio
            // Handle migration from "preferNot" to empty string
            if user.lifestyle == "preferNot" || user.lifestyle.isEmpty {
                selectedLifestyle = ""
            } else {
                selectedLifestyle = user.lifestyle
            }
            shareLifestyle = user.shareLifestyle
            selectedBodyType = user.bodyType
            shareBodyType = user.shareBodyType
            selectedIdealFirstDate = user.idealFirstDate
            shareIdealFirstDate = user.shareIdealFirstDate
            selectedSensoryPreferences = user.sensoryPreferences
            shareSensoryPreferences = user.shareSensoryPreferences
            
            print("🔍 ProfileEditView - Loaded lifestyle: \(selectedLifestyle), shareLifestyle: \(shareLifestyle)")
            print("🔍 ProfileEditView - Loaded bodyType: \(selectedBodyType), shareBodyType: \(shareBodyType)")
            print("🔍 ProfileEditView - Loaded idealFirstDate: \(selectedIdealFirstDate), shareIdealFirstDate: \(shareIdealFirstDate)")
            print("🔍 ProfileEditView - Loaded sensoryPreferences: \(selectedSensoryPreferences), shareSensoryPreferences: \(shareSensoryPreferences)")
            
            // Load interests from database
            let previousInterests = selectedInterests
            selectedInterests = Set(user.interests)
            
            // Load gender and preferences (handle migration from "Other" to "Non-binary")
            if user.gender == "Man" || user.gender == "Woman" {
                gender = user.gender
                customGender = ""
            } else if user.gender == "Non-binary" {
                gender = "Non-binary"
                customGender = ""
            } else if user.gender == "Other" || !user.gender.isEmpty {
                // Migrate old "Other" or custom gender text to "Non-binary"
                gender = "Non-binary"
                customGender = ""
            } else {
                gender = ""
                customGender = ""
            }
            // Load interested in preferences (handle migration from "Other" to new options)
            var loadedInterestedIn = Set(user.interestedIn)
            customInterestedIn = ""
            
            // Migrate old "Other" values to "Non-binary" (or remove custom text)
            let standardOptions = ["Man", "Woman", "Non-binary", "Anyone"]
            var migratedInterestedIn = Set<String>()
            for preference in loadedInterestedIn {
                if standardOptions.contains(preference) {
                    migratedInterestedIn.insert(preference)
                } else if preference == "Other" {
                    // Migrate old "Other" to "Non-binary"
                    migratedInterestedIn.insert("Non-binary")
                }
                // Old custom text entries are simply removed (not migrated)
            }
            
            selectedInterestedIn = migratedInterestedIn
            
            // Load looking for data (handle migration from "Other" to "Not sure yet")
            var loadedLookingFor = Set(user.lookingFor)
            customLookingFor = ""
            
            // Check if any of the looking for items are custom text or old "Other" option
            let lookingForStandardOptions = ["Friendship", "Relationship", "Not sure yet"]
            for lookingForItem in user.lookingFor {
                if lookingForItem == "Other" {
                    // Migrate old "Other" to "Not sure yet"
                    loadedLookingFor.remove("Other")
                    loadedLookingFor.insert("Not sure yet")
                } else if !lookingForStandardOptions.contains(lookingForItem) {
                    // This is old custom text, convert to "Not sure yet"
                    loadedLookingFor.remove(lookingForItem)
                    loadedLookingFor.insert("Not sure yet")
                }
            }
            
            selectedLookingFor = loadedLookingFor
            
            // Load preferred age range - always use saved values
            // Ensure values are within valid range (18-80)
            let savedMin = max(18, min(user.preferredAgeMin, 80))
            let savedMax = max(18, min(user.preferredAgeMax, 80))
            
            // Ensure min <= max
            if savedMin <= savedMax {
                preferredAgeMin = Double(savedMin)
                preferredAgeMax = Double(savedMax)
            } else {
                // Fallback to defaults if saved values are invalid
                preferredAgeMin = Double(user.age)
                preferredAgeMax = Double(min(user.age + 5, 80))
            }
            
            print("🔍 ProfileEditView - Loaded preferred age from user: \(user.preferredAgeMin)-\(user.preferredAgeMax)")
            print("🔍 ProfileEditView - Loaded preferred age (validated): \(Int(preferredAgeMin))-\(Int(preferredAgeMax))")
            
            // Load energy level
            energyLevel = user.energyLevel
            
            // Load photos from app state (app state is source of truth)
            existingPhotos = user.photos
            
            print("🔍 ProfileEditView - loadCurrentProfile() called")
            print("🔍 ProfileEditView - User from DB has \(user.interests.count) interests: \(user.interests)")
            print("🔍 ProfileEditView - Previous selectedInterests: \(previousInterests)")
            print("🔍 ProfileEditView - New selectedInterests: \(selectedInterests)")
            print("🔍 ProfileEditView - About me from DB: '\(user.bio)'")
            print("🔍 ProfileEditView - Bio length: \(user.bio.count) characters")
            print("🔍 ProfileEditView - Date of birth from DB: \(user.dateOfBirth?.description ?? "nil")")
            print("🔍 ProfileEditView - Loaded dateOfBirth: \(dateOfBirth)")
            print("🔍 ProfileEditView - Loaded gender: '\(user.gender)', UI gender: '\(gender)', customGender: '\(customGender)'")
            print("🔍 ProfileEditView - Loaded interestedIn: \(user.interestedIn), UI selectedInterestedIn: \(selectedInterestedIn), customInterestedIn: '\(customInterestedIn)'")
            print("📸 Loaded \(existingPhotos.count) photos from app state")
        } else {
            // Reset all fields if no user data or use sign up name for mandatory completion
            if isMandatoryCompletion && !appState.signUpName.isEmpty {
                name = appState.signUpName
                print("📝 Using sign up name for mandatory completion: \(appState.signUpName)")
            } else {
                name = ""
            }
            dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
            location = ""
            locationLatitude = nil
            locationLongitude = nil
            bio = ""
            gender = ""
            selectedInterestedIn = []
            existingPhotos = []
            selectedLifestyle = ""
        }
    }
    
    // MARK: - Validation Functions
    private func isFormValid() -> Bool {
        return isNameValid && isAgeValid && isLocationValid && isBioValid && isPhotosValid && isInterestsValid && isGenderValid && isInterestedInValid && isLookingForValid
    }
    
    private func getValidationErrors() -> [String] {
        var errors: [String] = []
        
        if !isNameValid {
            errors.append("profile.edit.validation.full.name".localized)
        }
        
        if !isAgeValid {
            errors.append("profile.edit.validation.age".localized)
        }
        
        if !isLocationValid {
            errors.append("profile.edit.validation.location".localized)
        }
        
        if !isBioValid {
            errors.append("profile.edit.validation.bio".localized)
        }
        
        if !isPhotosValid {
            errors.append("profile.edit.validation.photos".localized)
        }
        
        if !isInterestsValid {
            errors.append("profile.edit.validation.interests".localized)
        }
        
        if !isGenderValid {
            errors.append("profile.edit.validation.gender".localized)
        }
        
        if !isInterestedInValid {
            errors.append("profile.edit.validation.interested.in".localized)
        }
        
        if !isLookingForValid {
            errors.append("profile.edit.validation.looking.for".localized)
        }
        
        return errors
    }
    
    private func getFormattedValidationErrors() -> String {
        let errors = getValidationErrors()
        if errors.count == 1 {
            return errors[0]
        } else {
            return errors.map { "• \($0)" }.joined(separator: "\n")
        }
    }
    
    private func calculateAge(from dateOfBirth: Date) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: now)
        return ageComponents.year ?? 0
    }
    
    
    private func deletePhoto(_ photoURL: String) {
        photosToDelete.insert(photoURL)
        existingPhotos.removeAll { $0 == photoURL }
    }
    
    private func removeNewPhoto(at index: Int) {
        newPhotos.remove(at: index)
    }
    
    private func saveProfile() {
        let ageInt = calculateAge(from: dateOfBirth)
        
        isLoading = true
        
        Task {
            await performSave(ageInt: ageInt)
        }
    }
    
    @MainActor
    private func performSave(ageInt: Int) async {
        do {
                // Handle photo uploads
                var galleryPhotoURLs: [String] = []
                var newProfilePhotoURL: String? = nil
                
                // Upload profile photo if selected
                if let profilePhoto = profilePhoto {
                    // Delete old profile photo if it exists
                    if let user = appState.currentUser,
                       let existingProfilePhotoURL = user.profilePhotoURL {
                        do {
                            try await PhotoStorageService.shared.deletePhoto(url: existingProfilePhotoURL)
                            print("🗑️ Deleted old profile photo: \(existingProfilePhotoURL)")
                        } catch {
                            print("⚠️ Failed to delete old profile photo (may not exist): \(existingProfilePhotoURL)")
                            // Continue with upload even if deletion fails
                        }
                    }
                    
                    // Upload new profile photo
                    let userID = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                    newProfilePhotoURL = try await PhotoStorageService.shared.uploadProfilePhoto(profilePhoto, for: userID)
                    print("📸 Uploaded new profile photo: \(newProfilePhotoURL ?? "nil")")
                }
                
                // Upload new gallery photos
                if !newPhotos.isEmpty {
                    let userID = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                    let uploadedGalleryPhotos = try await PhotoStorageService.shared.uploadMultipleGalleryPhotos(newPhotos, for: userID)
                    galleryPhotoURLs.append(contentsOf: uploadedGalleryPhotos)
                }
                
                // Delete photos from storage
                for photoURL in photosToDelete {
                    try await PhotoStorageService.shared.deletePhoto(url: photoURL)
                }
                
                // Update user data
                if var user = appState.currentUser {
                    user.name = name
                    user.age = ageInt
                    user.bio = bio
                    user.interests = Array(selectedInterests)
                    // Save gender (directly use selected value, no custom text)
                    user.gender = gender
                    // Save interested in preferences (directly use selected values, no custom text)
                    var finalInterestedIn = Array(selectedInterestedIn)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalInterestedIn.removeAll { $0 == "Other" }
                    user.interestedIn = finalInterestedIn
                    
                    // Save looking for preferences (directly use selected values, no custom text)
                    var finalLookingFor = Array(selectedLookingFor)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalLookingFor.removeAll { $0 == "Other" }
                    user.lookingFor = finalLookingFor
                    
                    // Update preferred age range
                    user.preferredAgeMin = Int(preferredAgeMin)
                    user.preferredAgeMax = Int(preferredAgeMax)
                    
                    // Update energy level
                    user.energyLevel = energyLevel
                    
                    // Update location with coordinates
                    user.location = Location(
                        displayString: location,
                        city: appState.currentUser?.location.city ?? "",
                        state: appState.currentUser?.location.state ?? "",
                        country: SwedenLocation.countryName,
                        latitude: locationLatitude,
                        longitude: locationLongitude
                    )
                    user.lifestyle = selectedLifestyle
                    user.shareLifestyle = shareLifestyle
                    user.bodyType = selectedBodyType
                    user.shareBodyType = shareBodyType
                    user.idealFirstDate = selectedIdealFirstDate
                    user.shareIdealFirstDate = shareIdealFirstDate
                    user.sensoryPreferences = selectedSensoryPreferences
                    user.shareSensoryPreferences = shareSensoryPreferences
                    
                    // Update profile photo URL only if a new one was selected
                    if let newProfilePhotoURL = newProfilePhotoURL {
                        user.profilePhotoURL = newProfilePhotoURL
                    }
                    // If no new profile photo was selected, keep the existing one unchanged
                    
                    // Update gallery photos array
                    user.photos.removeAll { photosToDelete.contains($0) }
                    user.photos.append(contentsOf: galleryPhotoURLs)
                    
                    // Update both AppStateManager and FirebaseAuthService to ensure sync
                    appState.currentUser = user
                    FirebaseAuthService.shared.currentUser = user
                } else {
                    // Create new user
                    // Handle gender for new user (directly use selected value, no custom text)
                    let finalGender = gender
                    
                    // Handle interested in preferences for new user (directly use selected values, no custom text)
                    var finalInterestedIn = Array(selectedInterestedIn)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalInterestedIn.removeAll { $0 == "Other" }
                    
                    // Handle looking for for new user (directly use selected values, no custom text)
                    var finalLookingFor = Array(selectedLookingFor)
                    // Remove any old "Other" entries if they exist (migration cleanup)
                    finalLookingFor.removeAll { $0 == "Other" }
                    
                    var newUser = SpectRoomUser(
                        name: name,
                        age: ageInt,
                        email: FirebaseAuthService.shared.auth.currentUser?.email ?? "",
                        bio: bio,
                        interests: Array(selectedInterests),
                        location: Location(
                            displayString: location,
                            country: SwedenLocation.countryName,
                            latitude: locationLatitude,
                            longitude: locationLongitude
                        ),
                        gender: finalGender,
                        interestedIn: finalInterestedIn,
                        lookingFor: finalLookingFor,
                        preferredAgeMin: Int(preferredAgeMin),
                        preferredAgeMax: Int(preferredAgeMax),
                        lifestyle: selectedLifestyle,
                        shareLifestyle: shareLifestyle,
                        bodyType: selectedBodyType,
                        shareBodyType: shareBodyType,
                        idealFirstDate: selectedIdealFirstDate,
                        shareIdealFirstDate: shareIdealFirstDate,
                        sensoryPreferences: selectedSensoryPreferences,
                        shareSensoryPreferences: shareSensoryPreferences,
                        energyLevel: energyLevel
                    )
                    newUser.profilePhotoURL = newProfilePhotoURL
                    newUser.photos = galleryPhotoURLs
                    // Update both AppStateManager and FirebaseAuthService to ensure sync
                    appState.currentUser = newUser
                    FirebaseAuthService.shared.currentUser = newUser
                }
                
                // Save to Firebase
                let interestsArray = Array(selectedInterests)
                // Handle gender (directly use selected value, no custom text)
                let finalGender = gender
                let finalLifestyleValue = selectedLifestyle
                print("🔍 ProfileEditView - Saving interests to Firebase: \(interestsArray)")
                print("🔍 ProfileEditView - Interests count: \(interestsArray.count)")
                print("🔍 ProfileEditView - Saving gender: \(finalGender)")
                
                // Handle interested in preferences for Firebase (directly use selected values, no custom text)
                var finalInterestedIn = Array(selectedInterestedIn)
                // Remove any old "Other" entries if they exist (migration cleanup)
                finalInterestedIn.removeAll { $0 == "Other" }
                
                // Handle looking for for Firebase
                var finalLookingFor = Array(selectedLookingFor)
                if selectedLookingFor.contains("Other") && !customLookingFor.isEmpty {
                    // Replace "Other" with custom text
                    finalLookingFor.removeAll { $0 == "Other" }
                    finalLookingFor.append(customLookingFor)
                }
                
                print("🔍 ProfileEditView - Saving preferred age to Firebase: \(Int(preferredAgeMin))-\(Int(preferredAgeMax))")
                
                let userData: Dictionary<String, Any> = [
                    "name": name,
                    "age": ageInt,
                    "dateOfBirth": dateOfBirth.timeIntervalSince1970, // Save actual date of birth
                    "bio": bio,
                    "interests": interestsArray,
                    "gender": finalGender,
                    "interestedIn": finalInterestedIn,
                    "lookingFor": finalLookingFor,
                    "preferredAgeMin": Int(preferredAgeMin),
                    "preferredAgeMax": Int(preferredAgeMax),
                    "lifestyle": finalLifestyleValue,
                    "shareLifestyle": shareLifestyle,
                    "bodyType": selectedBodyType,
                    "shareBodyType": shareBodyType,
                    "idealFirstDate": selectedIdealFirstDate,
                    "shareIdealFirstDate": shareIdealFirstDate,
                    "sensoryPreferences": selectedSensoryPreferences,
                    "shareSensoryPreferences": shareSensoryPreferences,
                    "energyLevel": energyLevel,
                    "location": [
                        "displayString": location,
                        "city": appState.currentUser?.location.city ?? "",
                        "state": appState.currentUser?.location.state ?? "",
                        "country": SwedenLocation.countryName,
                        "latitude": (locationLatitude ?? NSNull()) as Any,
                        "longitude": (locationLongitude ?? NSNull()) as Any
                    ] as [String: Any],
                    "profilePhotoURL": appState.currentUser?.profilePhotoURL ?? NSNull(),
                    "photos": appState.currentUser?.photos ?? []
                ]
                
                try await FirebaseAuthService.shared.updateUserData(userData)
                
                appState.saveAppState()
                
                // Refresh user data from Firebase to ensure ProfileView shows latest data
                // This will update FirebaseAuthService.currentUser, which will propagate to AppStateManager
                await FirebaseAuthService.shared.forceRefreshUserData()
                
                isLoading = false
                
                if isMandatoryCompletion {
                    // Complete the initial profile setup
                    appState.completeInitialProfile()
                } else {
                    // Regular edit - just dismiss
                    dismiss()
                }
                
            } catch {
                isLoading = false
                alertMessage = String(format: "profile.edit.error.updating".localized, error.localizedDescription)
                showingAlert = true
            }
    }
    
    // MARK: - Helper function to localize interest names
    private func localizedInterest(_ interest: String) -> String {
        let key = "profile.edit.interest.\(interest.lowercased())"
        let localized = key.localized
        // If localization key doesn't exist, return original
        return localized == key ? interest : localized
    }
}

// MARK: - Supporting Views
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var isEditingProfilePhoto: Bool
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct GalleryImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 10
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: GalleryImagePicker
        
        init(_ parent: GalleryImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.images.append(image)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ProfileEditView()
        .environmentObject(AppStateManager.shared)
}
