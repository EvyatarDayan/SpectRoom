import Foundation

/// Stored on `users/{uid}.profileStatus` for admin filtering of unfinished signups.
enum UserProfileStatus: String {
    case incomplete
    case complete

    static let firestoreKey = "profileStatus"

    private static let profileFieldKeys: Set<String> = [
        "name",
        "age",
        "bio",
        "location",
        "photos",
        "profilePhotoURL",
        "interests",
        "gender",
        "interestedIn",
        "lookingFor",
        "idealFirstDate"
    ]

    static func updateTouchesProfileFields(_ data: [String: Any]) -> Bool {
        data.keys.contains { profileFieldKeys.contains($0) }
    }

    /// Same completion rules as `AppStateManager.isProfileComplete()`.
    static func evaluate(from userData: [String: Any]) -> UserProfileStatus {
        let name = (userData["name"] as? String ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let nameComponents = name.components(separatedBy: " ")
        let hasFullName = nameComponents.count >= 2 && nameComponents.allSatisfy { !$0.isEmpty }

        let age = userData["age"] as? Int
            ?? (userData["age"] as? NSNumber)?.intValue
            ?? 0
        let hasValidAge = age >= 18

        let (displayString, latitude, longitude) = locationFields(from: userData)
        let trimmedLocation = displayString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let hasLocation: Bool
        if trimmedLocation.isEmpty {
            hasLocation = false
        } else if let latitude, let longitude {
            hasLocation = SwedenLocation.contains(latitude: latitude, longitude: longitude)
        } else {
            hasLocation = true
        }

        let bio = (userData["bio"] as? String ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let hasBio = bio.count >= 30

        let profilePhotoURL = (userData["profilePhotoURL"] as? String)?
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let hasProfilePhoto = !profilePhotoURL.isEmpty && URL(string: profilePhotoURL) != nil

        let photos = (userData["photos"] as? [String] ?? []).filter { photoURL in
            let trimmed = photoURL.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return !trimmed.isEmpty && URL(string: trimmed) != nil
        }
        let hasPhotos = photos.count >= 2 && photos.count <= 5

        let interests = userData["interests"] as? [String] ?? []
        let hasInterests = interests.count >= 3
        let hasGender = !(userData["gender"] as? String ?? "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .isEmpty
        let interestedIn = userData["interestedIn"] as? [String] ?? []
        let lookingFor = userData["lookingFor"] as? [String] ?? []
        let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []

        let isComplete = hasFullName
            && hasValidAge
            && hasLocation
            && hasBio
            && hasProfilePhoto
            && hasPhotos
            && hasInterests
            && hasGender
            && !interestedIn.isEmpty
            && !lookingFor.isEmpty
            && !idealFirstDate.isEmpty

        return isComplete ? .complete : .incomplete
    }

    private static func locationFields(from userData: [String: Any]) -> (String, Double?, Double?) {
        let locationData = userData["location"] as? [String: Any] ?? [:]
        let displayString = locationData["displayString"] as? String ?? ""
        return (
            displayString,
            doubleValue(locationData["latitude"]),
            doubleValue(locationData["longitude"])
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }
}
