import Foundation

enum MediaDailyLimitError: LocalizedError {
    case dailyLimitReached(limit: Int)

    var errorDescription: String? {
        MediaDailyLimit.limitMessage
    }
}

/// Tracks combined image + voice message sends per account for the local day.
enum MediaDailyLimit {
    private static let dateKeyPrefix = "mediaDailySendDate_"
    private static let countKeyPrefix = "mediaDailySendCount_"

    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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

    static var maxMediaPerDay: Int {
        DiscoverDailyLimit.currentPlanTier.dailyMediaMessageLimit
    }

    /// Copy for the daily-limit overlay, tailored to the active plan.
    static var limitMessage: String {
        switch DiscoverDailyLimit.currentPlanTier {
        case .free:
            return "messages.media.limit.message.free".localized
        case .pro:
            return "messages.media.limit.message.pro".localized
        case .premium:
            return "messages.media.limit.message.premium".localized
        }
    }

    static func currentCount() -> Int {
        guard let accountKey else { return 0 }
        let defaults = UserDefaults.standard
        let dateKey = dateKeyPrefix + accountKey
        let countKey = countKeyPrefix + accountKey

        if defaults.string(forKey: dateKey) != todayKey {
            defaults.set(todayKey, forKey: dateKey)
            defaults.set(0, forKey: countKey)
            return 0
        }
        return defaults.integer(forKey: countKey)
    }

    static var remaining: Int {
        max(0, maxMediaPerDay - currentCount())
    }

    static var hasReachedLimit: Bool {
        currentCount() >= maxMediaPerDay
    }

    static var canSend: Bool {
        !hasReachedLimit
    }

    @discardableResult
    static func recordSend() -> Int {
        guard let accountKey else { return 0 }
        let count = currentCount() + 1
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: dateKeyPrefix + accountKey)
        defaults.set(count, forKey: countKeyPrefix + accountKey)
        return count
    }

    static func reset() {
        guard let accountKey else { return }
        let defaults = UserDefaults.standard
        defaults.set(todayKey, forKey: dateKeyPrefix + accountKey)
        defaults.set(0, forKey: countKeyPrefix + accountKey)
    }
}
