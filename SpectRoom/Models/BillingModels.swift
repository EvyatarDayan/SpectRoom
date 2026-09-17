import Foundation

/// Unified billing price display: always `"9.99 USD"` (dot decimal, USD code).
enum BillingCurrency {
    static let code = "USD"

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter
    }()

    static func format(_ amount: Decimal, currencyCode: String = code) -> String {
        let value = NSDecimalNumber(decimal: amount)
        let number = amountFormatter.string(from: value) ?? "\(amount)"
        let code = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let resolved = code.isEmpty ? Self.code : code
        return "\(number) \(resolved)"
    }
}

// MARK: - Plans

enum BillingInterval: String, CaseIterable, Identifiable, Codable {
    case monthly
    case yearly

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .monthly: return "billing.interval.monthly"
        case .yearly: return "billing.interval.yearly"
        }
    }

    /// Lowercase adjective used in CTAs (“Change to yearly Pro”).
    var adjectiveKey: String {
        switch self {
        case .monthly: return "billing.interval.monthly.adj"
        case .yearly: return "billing.interval.yearly.adj"
        }
    }
}

enum PlanTier: String, CaseIterable, Identifiable, Codable {
    case free
    case pro
    case premium

    var id: String { rawValue }

    /// Daily Discover like/pass quota for this plan.
    var dailyDiscoverSwipeLimit: Int {
        switch self {
        case .free: return 10
        case .pro: return 15
        case .premium: return 20
        }
    }

    /// Daily Discover swipe undos. `nil` means unlimited (Premium).
    var dailyDiscoverUndoLimit: Int? {
        switch self {
        case .free: return 3
        case .pro: return 6
        case .premium: return nil
        }
    }

    /// Free: match % only. Pro / Premium: full factor breakdown.
    var showsFullMatchBreakdown: Bool {
        switch self {
        case .free: return false
        case .pro, .premium: return true
        }
    }

    /// Days between profile boosts. `nil` means boost is not available (Free).
    var profileBoostCooldownDays: Int? {
        switch self {
        case .free: return nil
        case .pro: return 14
        case .premium: return 7
        }
    }

    /// Combined daily image + voice + video message sends.
    var dailyMediaMessageLimit: Int {
        switch self {
        case .free: return 5
        case .pro: return 20
        case .premium: return 50
        }
    }

    /// Max chat video file size (picked original, compressed upload, and user-facing limit).
    var maxVideoUploadBytes: Int {
        switch self {
        case .free: return 10 * 1024 * 1024
        case .pro: return 20 * 1024 * 1024
        case .premium: return 40 * 1024 * 1024
        }
    }

    var maxVideoUploadMegabytes: Int {
        maxVideoUploadBytes / (1024 * 1024)
    }

    var displayNameKey: String {
        switch self {
        case .free: return "billing.plan.free"
        case .pro: return "billing.plan.pro"
        case .premium: return "billing.plan.premium"
        }
    }

    /// Label on profile photos (“Free Plan”, “Pro Plan”, “Premium Plan”).
    var profilePlanLabelKey: String {
        switch self {
        case .free: return "profile.plan.free"
        case .pro: return "profile.plan.pro"
        case .premium: return "profile.plan.premium"
        }
    }

    /// Icon after the profile plan label (Free none, Pro star, Premium crown).
    var profilePlanSymbol: String {
        switch self {
        case .free: return ""
        case .pro: return "⭐️"
        case .premium: return "👑"
        }
    }

    /// Icon next to plan titles in Account & Billing (Free sprout, Pro star, Premium crown).
    var titleStars: String {
        switch self {
        case .free: return "🌱"
        case .pro, .premium: return profilePlanSymbol
        }
    }

    /// Gold star count kept for any legacy call sites that need a numeric count.
    var titleStarCount: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .premium: return 1
        }
    }

    var accentSystemImage: String {
        switch self {
        case .free: return "sparkles"
        case .pro: return "star.circle.fill"
        case .premium: return "crown.fill"
        }
    }

    /// Localization keys for plan feature bullets (Account & Billing).
    var featureKeys: [String] {
        switch self {
        case .free:
            return [
                "billing.feature.swipes.10",
                "billing.feature.undos.3",
                "billing.feature.match.basic",
                "billing.feature.boost.none",
                "billing.feature.media.5",
                "billing.feature.video.10"
            ]
        case .pro:
            return [
                "billing.feature.swipes.15",
                "billing.feature.undos.6",
                "billing.feature.match.full",
                "billing.feature.boost.14",
                "billing.feature.media.20",
                "billing.feature.video.20"
            ]
        case .premium:
            return [
                "billing.feature.swipes.20",
                "billing.feature.undos.unlimited",
                "billing.feature.match.full",
                "billing.feature.boost.7",
                "billing.feature.media.50",
                "billing.feature.video.40"
            ]
        }
    }

    var usageSummaryKey: String {
        switch self {
        case .free: return "billing.usage.free"
        case .pro: return "billing.usage.pro"
        case .premium: return "billing.usage.premium"
        }
    }
}

enum SubscriptionStatus: String, Codable {
    case active
    case renewing
    case cancelled
    case pastDue
    case none

    var titleKey: String {
        switch self {
        case .active: return "billing.status.active"
        case .renewing: return "billing.status.renewing"
        case .cancelled: return "billing.status.cancelled"
        case .pastDue: return "billing.status.past.due"
        case .none: return "billing.status.none"
        }
    }
}

struct SubscriptionPlan: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let tier: PlanTier
    let name: String
    let monthlyPrice: Decimal
    let yearlyPrice: Decimal
    let currencyCode: String
    let features: [String]
    let usageSummary: String?

    func price(for interval: BillingInterval) -> Decimal {
        interval == .yearly ? yearlyPrice : monthlyPrice
    }

    func formattedPrice(for interval: BillingInterval) -> String {
        BillingCurrency.format(price(for: interval), currencyCode: currencyCode)
    }

    func formattedPriceWithInterval(for interval: BillingInterval) -> String {
        let period = interval == .yearly
            ? "billing.per.year".localized
            : "billing.per.month".localized
        return "\(formattedPrice(for: interval)) \(period)"
    }

    /// Yearly discount vs paying monthly for 12 months (0…1).
    var yearlySavingsFraction: Decimal {
        let monthlyAnnual = monthlyPrice * 12
        guard monthlyAnnual > 0 else { return 0 }
        return max(0, (monthlyAnnual - yearlyPrice) / monthlyAnnual)
    }
}

struct CurrentSubscription: Equatable, Codable {
    var planId: String
    var tier: PlanTier
    var status: SubscriptionStatus
    var interval: BillingInterval
    var renewsOn: Date?
    var cancelledAt: Date?
    var usageSummary: String?
}

// MARK: - Payment methods

enum PaymentMethodType: String, Codable {
    case card
    case applePay
    case googlePay
}

enum CardBrand: String, Codable, CaseIterable {
    case visa
    case mastercard
    case amex
    case discover
    case other

    var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "Amex"
        case .discover: return "Discover"
        case .other: return "Card"
        }
    }

    var systemImage: String {
        switch self {
        case .visa, .mastercard, .amex, .discover, .other:
            return "creditcard.fill"
        }
    }
}

struct PaymentMethod: Identifiable, Equatable, Codable {
    let id: String
    let type: PaymentMethodType
    var cardName: String?
    var brand: CardBrand?
    var last4: String?
    var expMonth: Int?
    var expYear: Int?
    var isDefault: Bool
    var walletEnabled: Bool

    var displayTitle: String {
        let trimmed = cardName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return brand?.displayName ?? "Card"
    }

    var maskedNumber: String {
        guard let last4, !last4.isEmpty else { return "••••" }
        return "•••• •••• •••• \(last4)"
    }

    var expirationDisplay: String? {
        guard let expMonth, let expYear else { return nil }
        return String(format: "%02d/%02d", expMonth, expYear % 100)
    }
}

struct NewCardDraft: Equatable {
    var cardName: String = ""
    var cardholderName: String = ""
    var cardNumber: String = ""
    /// Formatted as `MM/YY`.
    var expiration: String = ""
    var cvc: String = ""
    var postalCode: String = ""

    static let requiredCardDigitCount = 16
    static let requiredCVCDigitCount = 3

    var digitsOnlyCardNumber: String {
        cardNumber.filter(\.isNumber)
    }

    var digitsOnlyExpiration: String {
        expiration.filter(\.isNumber)
    }

    var expiryMonth: Int? {
        guard digitsOnlyExpiration.count == 4 else { return nil }
        return Int(String(digitsOnlyExpiration.prefix(2)))
    }

    var expiryYearFull: Int? {
        guard digitsOnlyExpiration.count == 4,
              let yy = Int(String(digitsOnlyExpiration.suffix(2))) else { return nil }
        return 2000 + yy
    }

    var isCardNameValid: Bool {
        !cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isCardNumberLengthValid: Bool {
        digitsOnlyCardNumber.count == Self.requiredCardDigitCount
    }

    var isCardholderNameValid: Bool {
        let trimmed = cardholderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isWhitespace }
    }

    var isExpiryValid: Bool {
        guard let month = expiryMonth, (1...12).contains(month),
              let year = expiryYearFull else { return false }
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        if year < currentYear { return false }
        if year == currentYear && month < currentMonth { return false }
        return true
    }

    var isCVCValid: Bool {
        cvc.filter(\.isNumber).count == Self.requiredCVCDigitCount
            && cvc.count == Self.requiredCVCDigitCount
    }

    var isPostalCodeValid: Bool {
        let allowed = postalCode.allSatisfy { $0.isNumber || $0 == " " }
        guard allowed else { return false }
        guard postalCode.count <= 6 else { return false }
        let digits = postalCode.filter(\.isNumber)
        return (4...5).contains(digits.count)
    }

    var isValid: Bool {
        isCardNameValid
            && isCardholderNameValid
            && isCardNumberLengthValid
            && isExpiryValid
            && isCVCValid
            && isPostalCodeValid
    }

    /// Edit keeps existing number/CVC/postal/cardholder when those fields are left blank.
    var isValidForEdit: Bool {
        isCardNameValid
            && isExpiryValid
            && (cardholderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCardholderNameValid)
            && (cardNumber.isEmpty || isCardNumberLengthValid)
            && (cvc.isEmpty || isCVCValid)
            && (postalCode.isEmpty || isPostalCodeValid)
    }

    static func formatCardNumber(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(requiredCardDigitCount))
        guard !digits.isEmpty else { return "" }
        var groups: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let end = digits.index(index, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            groups.append(String(digits[index..<end]))
            index = end
        }
        return groups.joined(separator: " ")
    }

    static func formatExpiration(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        if digits.count <= 2 { return digits }
        return "\(digits.prefix(2))/\(digits.dropFirst(2))"
    }

    static func draft(forEditing method: PaymentMethod) -> NewCardDraft {
        var draft = NewCardDraft()
        draft.cardName = method.cardName ?? ""
        if let expMonth = method.expMonth, let expYear = method.expYear {
            draft.expiration = String(format: "%02d/%02d", expMonth, expYear % 100)
        }
        return draft
    }
}

// MARK: - Account history

enum AccountHistoryEventKind: String, Codable, CaseIterable {
    case newPlan
    case changePlan
    case cancelPlan
    case automaticBilling

    var titleKey: String {
        switch self {
        case .newPlan: return "billing.history.event.new.plan"
        case .changePlan: return "billing.history.event.change.plan"
        case .cancelPlan: return "billing.history.event.cancel.plan"
        case .automaticBilling: return "billing.history.event.automatic.billing"
        }
    }
}

enum InvoiceStatus: String, Codable, CaseIterable {
    case paid
    case refunded
    case pending

    var titleKey: String {
        switch self {
        case .paid: return "billing.invoice.status.paid"
        case .refunded: return "billing.invoice.status.refunded"
        case .pending: return "billing.invoice.status.pending"
        }
    }
}

/// Plan / billing activity shown under Account History.
struct AccountHistoryEvent: Identifiable, Equatable, Codable {
    let id: String
    let date: Date
    let kind: AccountHistoryEventKind
    let planTier: PlanTier?
    let interval: BillingInterval?
    let amount: Decimal?
    let currencyCode: String
    let status: InvoiceStatus?

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        kind: AccountHistoryEventKind,
        planTier: PlanTier?,
        interval: BillingInterval?,
        amount: Decimal? = nil,
        currencyCode: String = "USD",
        status: InvoiceStatus? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.planTier = planTier
        self.interval = interval
        self.amount = amount
        self.currencyCode = currencyCode
        self.status = status
    }

    /// e.g. "Monthly Pro"
    var planLabel: String {
        let tierName = (planTier ?? .free).displayNameKey.localized
        guard let interval, planTier != .free else { return tierName }
        return "\(interval.titleKey.localized) \(tierName)"
    }

    var displayTitle: String {
        String(format: kind.titleKey.localized, planLabel)
    }

    var showsAmount: Bool {
        kind == .automaticBilling && amount != nil
    }

    /// e.g. "14 Sep 2026 14:43"
    func formattedDateTime() -> String {
        Self.dateTimeFormatter.string(from: date)
    }

    func formattedAmount() -> String {
        guard let amount else { return "—" }
        return BillingCurrency.format(amount, currencyCode: currencyCode)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.dateFormat = "d MMM yyyy HH:mm"
        return formatter
    }()
}

/// Kept as a typealias so older call sites / docs referring to invoices still compile during migration.
typealias Invoice = AccountHistoryEvent

// MARK: - Snapshot

struct BillingSnapshot: Equatable {
    var subscription: CurrentSubscription
    var availablePlans: [SubscriptionPlan]
    var paymentMethods: [PaymentMethod]
    var accountHistory: [AccountHistoryEvent]
    var applePayEnabled: Bool
    var googlePayEnabled: Bool

    /// Backward-compatible alias used by older view code.
    var invoices: [AccountHistoryEvent] {
        get { accountHistory }
        set { accountHistory = newValue }
    }
}
