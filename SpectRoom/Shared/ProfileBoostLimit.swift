import Foundation

enum ProfileBoostError: LocalizedError {
    case notAvailableOnPlan
    case alreadyActive
    case onCooldown(until: Date)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAvailableOnPlan:
            return "profile.boost.error.plan".localized
        case .alreadyActive:
            return "profile.boost.error.active".localized
        case .onCooldown(let until):
            return String(
                format: "profile.boost.error.cooldown".localized,
                until.formatted(date: .abbreviated, time: .omitted)
            )
        case .notAuthenticated:
            return "auth.error".localized
        }
    }
}

/// Local cooldown + active-window tracking for profile boosts (synced from Firebase when available).
enum ProfileBoostLimit {
    /// How long a boost elevates Discover visibility after activation.
    static let activeDuration: TimeInterval = 24 * 60 * 60

    private static func lastBoostStorageKey(for accountKey: String) -> String {
        "profileLastBoostAt_\(accountKey)"
    }

    private static func boostedUntilStorageKey(for accountKey: String) -> String {
        "profileBoostedUntil_\(accountKey)"
    }

    private static var accountKey: String? {
        if let uid = FirebaseAuthService.shared.auth.currentUser?.uid, !uid.isEmpty {
            return uid
        }
        if let email = FirebaseAuthService.shared.auth.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !email.isEmpty {
            return email
        }
        return nil
    }

    static var cooldownDays: Int? {
        DiscoverDailyLimit.currentPlanTier.profileBoostCooldownDays
    }

    static var isAvailableOnPlan: Bool {
        cooldownDays != nil
    }

    static var lastBoostAt: Date? {
        guard let accountKey else { return nil }
        let interval = UserDefaults.standard.double(forKey: lastBoostStorageKey(for: accountKey))
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    static var boostedUntil: Date? {
        guard let accountKey else { return nil }
        let interval = UserDefaults.standard.double(forKey: boostedUntilStorageKey(for: accountKey))
        guard interval > 0 else { return nil }
        let date = Date(timeIntervalSince1970: interval)
        return date > Date() ? date : nil
    }

    static var isBoostActive: Bool {
        boostedUntil != nil
    }

    static var nextBoostAvailableAt: Date? {
        guard let cooldownDays, let lastBoostAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: cooldownDays, to: lastBoostAt)
    }

    static var canActivate: Bool {
        guard isAvailableOnPlan else { return false }
        guard !isBoostActive else { return false }
        guard let next = nextBoostAvailableAt else { return true }
        return Date() >= next
    }

    /// Sync local cache from Firebase user fields.
    static func syncFromRemote(lastBoostAt: Date?, boostedUntil: Date?) {
        guard let accountKey else { return }
        let defaults = UserDefaults.standard
        if let lastBoostAt {
            defaults.set(lastBoostAt.timeIntervalSince1970, forKey: lastBoostStorageKey(for: accountKey))
        }
        if let boostedUntil, boostedUntil > Date() {
            defaults.set(boostedUntil.timeIntervalSince1970, forKey: boostedUntilStorageKey(for: accountKey))
        } else {
            defaults.removeObject(forKey: boostedUntilStorageKey(for: accountKey))
        }
    }

    static func recordActivation(at date: Date = Date(), activeUntil: Date) {
        guard let accountKey else { return }
        let defaults = UserDefaults.standard
        defaults.set(date.timeIntervalSince1970, forKey: lastBoostStorageKey(for: accountKey))
        defaults.set(activeUntil.timeIntervalSince1970, forKey: boostedUntilStorageKey(for: accountKey))
    }

    static func reset() {
        guard let accountKey else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastBoostStorageKey(for: accountKey))
        defaults.removeObject(forKey: boostedUntilStorageKey(for: accountKey))
    }
}
