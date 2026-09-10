import Foundation

@MainActor
protocol BillingServicing {
    func fetchBillingSnapshot() async throws -> BillingSnapshot
    func changePlan(to planId: String, interval: BillingInterval) async throws -> CurrentSubscription
    func cancelSubscription() async throws -> CurrentSubscription
    func setDefaultPaymentMethod(id: String) async throws -> [PaymentMethod]
    func deletePaymentMethod(id: String) async throws -> [PaymentMethod]
    func addCard(_ draft: NewCardDraft) async throws -> [PaymentMethod]
    func updateCard(id: String, draft: NewCardDraft) async throws -> [PaymentMethod]
    func toggleApplePay(enabled: Bool) async throws -> Bool
    func toggleGooglePay(enabled: Bool) async throws -> Bool
}

/// Local mock billing backend until StoreKit / Stripe is wired.
@MainActor
final class MockBillingService: BillingServicing {
    static let shared = MockBillingService()

    private static let persistedSubscriptionKey = "mockBillingCurrentSubscription"

    private var snapshot: BillingSnapshot
    private let delayNanoseconds: UInt64 = 650_000_000

    private init() {
        snapshot = Self.makeInitialSnapshot()
        DiscoverDailyLimit.syncPlanTier(snapshot.subscription.tier)
    }

    func fetchBillingSnapshot() async throws -> BillingSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        DiscoverDailyLimit.syncPlanTier(snapshot.subscription.tier)
        return snapshot
    }

    func changePlan(to planId: String, interval: BillingInterval) async throws -> CurrentSubscription {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let plan = snapshot.availablePlans.first(where: { $0.id == planId }) else {
            throw BillingServiceError.planNotFound
        }

        let renews = Calendar.current.date(
            byAdding: interval == .yearly ? .year : .month,
            value: 1,
            to: Date()
        )

        snapshot.subscription = CurrentSubscription(
            planId: plan.id,
            tier: plan.tier,
            status: plan.tier == .free ? .none : .renewing,
            interval: interval,
            renewsOn: plan.tier == .free ? nil : renews,
            cancelledAt: nil,
            usageSummary: plan.usageSummary
        )
        Self.persistSubscription(snapshot.subscription)
        DiscoverDailyLimit.syncPlanTier(plan.tier)
        return snapshot.subscription
    }

    func cancelSubscription() async throws -> CurrentSubscription {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard snapshot.subscription.tier != .free else {
            throw BillingServiceError.nothingToCancel
        }
        snapshot.subscription.status = .cancelled
        snapshot.subscription.cancelledAt = Date()
        Self.persistSubscription(snapshot.subscription)
        // Cancelled paid plans keep remaining access for the period; swipe quota stays on current tier.
        return snapshot.subscription
    }

    func setDefaultPaymentMethod(id: String) async throws -> [PaymentMethod] {
        try await Task.sleep(nanoseconds: delayNanoseconds / 2)
        guard snapshot.paymentMethods.contains(where: { $0.id == id }) else {
            throw BillingServiceError.paymentMethodNotFound
        }
        snapshot.paymentMethods = snapshot.paymentMethods.map { method in
            var copy = method
            copy.isDefault = method.id == id
            return copy
        }
        return snapshot.paymentMethods
    }

    func deletePaymentMethod(id: String) async throws -> [PaymentMethod] {
        try await Task.sleep(nanoseconds: delayNanoseconds / 2)
        guard let index = snapshot.paymentMethods.firstIndex(where: { $0.id == id }) else {
            throw BillingServiceError.paymentMethodNotFound
        }
        let wasDefault = snapshot.paymentMethods[index].isDefault
        snapshot.paymentMethods.remove(at: index)
        if wasDefault, let first = snapshot.paymentMethods.first {
            snapshot.paymentMethods[0].isDefault = true
            _ = first
        }
        return snapshot.paymentMethods
    }

    func addCard(_ draft: NewCardDraft) async throws -> [PaymentMethod] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard draft.isValid else { throw BillingServiceError.invalidCard }
        let digits = draft.digitsOnlyCardNumber
        guard let month = draft.expiryMonth, let year = draft.expiryYearFull else {
            throw BillingServiceError.invalidCard
        }

        let brand: CardBrand
        if digits.hasPrefix("4") {
            brand = .visa
        } else if digits.hasPrefix("5") {
            brand = .mastercard
        } else if digits.hasPrefix("3") {
            brand = .amex
        } else {
            brand = .other
        }

        let makeDefault = snapshot.paymentMethods.isEmpty
        if makeDefault {
            snapshot.paymentMethods = snapshot.paymentMethods.map {
                var copy = $0
                copy.isDefault = false
                return copy
            }
        }

        let method = PaymentMethod(
            id: UUID().uuidString,
            type: .card,
            cardName: draft.cardName.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand,
            last4: String(digits.suffix(4)),
            expMonth: month,
            expYear: year,
            isDefault: makeDefault || draft.cardholderName.lowercased().contains("default"),
            walletEnabled: false
        )
        if method.isDefault {
            snapshot.paymentMethods = snapshot.paymentMethods.map {
                var copy = $0
                copy.isDefault = false
                return copy
            }
        }
        snapshot.paymentMethods.insert(method, at: 0)
        return snapshot.paymentMethods
    }

    func updateCard(id: String, draft: NewCardDraft) async throws -> [PaymentMethod] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard draft.isValidForEdit else { throw BillingServiceError.invalidCard }
        guard let index = snapshot.paymentMethods.firstIndex(where: { $0.id == id }) else {
            throw BillingServiceError.paymentMethodNotFound
        }
        guard let month = draft.expiryMonth, let year = draft.expiryYearFull else {
            throw BillingServiceError.invalidCard
        }

        var method = snapshot.paymentMethods[index]
        method.cardName = draft.cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        method.expMonth = month
        method.expYear = year

        if draft.isCardNumberLengthValid {
            let digits = draft.digitsOnlyCardNumber
            if digits.hasPrefix("4") {
                method.brand = .visa
            } else if digits.hasPrefix("5") {
                method.brand = .mastercard
            } else if digits.hasPrefix("3") {
                method.brand = .amex
            } else {
                method.brand = .other
            }
            method.last4 = String(digits.suffix(4))
        }

        snapshot.paymentMethods[index] = method
        return snapshot.paymentMethods
    }

    func toggleApplePay(enabled: Bool) async throws -> Bool {
        try await Task.sleep(nanoseconds: delayNanoseconds / 3)
        snapshot.applePayEnabled = enabled
        return snapshot.applePayEnabled
    }

    func toggleGooglePay(enabled: Bool) async throws -> Bool {
        try await Task.sleep(nanoseconds: delayNanoseconds / 3)
        snapshot.googlePayEnabled = enabled
        return snapshot.googlePayEnabled
    }

    private static func makeInitialSnapshot() -> BillingSnapshot {
        let plans: [SubscriptionPlan] = [
            SubscriptionPlan(
                id: "plan_free",
                tier: .free,
                name: "Free",
                monthlyPrice: 0,
                yearlyPrice: 0,
                currencyCode: "USD",
                features: PlanTier.free.featureKeys,
                usageSummary: PlanTier.free.usageSummaryKey
            ),
            SubscriptionPlan(
                id: "plan_pro",
                tier: .pro,
                name: "Pro",
                monthlyPrice: Decimal(string: "9.99")!,
                yearlyPrice: Decimal(string: "95.90")!,
                currencyCode: "USD",
                features: PlanTier.pro.featureKeys,
                usageSummary: PlanTier.pro.usageSummaryKey
            ),
            SubscriptionPlan(
                id: "plan_premium",
                tier: .premium,
                name: "Premium",
                monthlyPrice: Decimal(string: "19.99")!,
                yearlyPrice: Decimal(string: "191.90")!,
                currencyCode: "USD",
                features: PlanTier.premium.featureKeys,
                usageSummary: PlanTier.premium.usageSummaryKey
            )
        ]

        let defaultSubscription = CurrentSubscription(
            planId: "plan_free",
            tier: .free,
            status: .none,
            interval: .monthly,
            renewsOn: nil,
            cancelledAt: nil,
            usageSummary: PlanTier.free.usageSummaryKey
        )
        var subscription = loadPersistedSubscription(validPlanIds: Set(plans.map(\.id)))
            ?? defaultSubscription
        if let plan = plans.first(where: { $0.id == subscription.planId }) {
            subscription.usageSummary = plan.usageSummary
        }

        let methods: [PaymentMethod] = [
            PaymentMethod(
                id: "pm_visa",
                type: .card,
                cardName: "Personal",
                brand: .visa,
                last4: "4242",
                expMonth: 8,
                expYear: 2028,
                isDefault: true,
                walletEnabled: false
            ),
            PaymentMethod(
                id: "pm_mc",
                type: .card,
                cardName: "Travel",
                brand: .mastercard,
                last4: "4444",
                expMonth: 12,
                expYear: 2027,
                isDefault: false,
                walletEnabled: false
            )
        ]

        let calendar = Calendar.current
        let invoices: [Invoice] = [
            Invoice(
                id: "inv_1003",
                date: calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
                description: "SpectRoom Pro — Monthly",
                planTier: .pro,
                interval: .monthly,
                amount: Decimal(string: "9.99")!,
                currencyCode: "USD",
                status: .paid,
                pdfURL: URL(string: "https://example.com/invoices/inv_1003.pdf")
            ),
            Invoice(
                id: "inv_1002",
                date: calendar.date(byAdding: .month, value: -2, to: Date()) ?? Date(),
                description: "SpectRoom Pro — Monthly",
                planTier: .pro,
                interval: .monthly,
                amount: Decimal(string: "9.99")!,
                currencyCode: "USD",
                status: .paid,
                pdfURL: URL(string: "https://example.com/invoices/inv_1002.pdf")
            ),
            Invoice(
                id: "inv_1001",
                date: calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
                description: "SpectRoom Pro — Monthly",
                planTier: .pro,
                interval: .monthly,
                amount: Decimal(string: "9.99")!,
                currencyCode: "USD",
                status: .refunded,
                pdfURL: URL(string: "https://example.com/invoices/inv_1001.pdf")
            ),
            Invoice(
                id: "inv_1000",
                date: calendar.date(byAdding: .month, value: -4, to: Date()) ?? Date(),
                description: "SpectRoom Premium — Monthly",
                planTier: .premium,
                interval: .yearly,
                amount: Decimal(string: "19.99")!,
                currencyCode: "USD",
                status: .paid,
                pdfURL: URL(string: "https://example.com/invoices/inv_1000.pdf")
            ),
            Invoice(
                id: "inv_0999",
                date: calendar.date(byAdding: .month, value: -5, to: Date()) ?? Date(),
                description: "SpectRoom Pro — Monthly",
                planTier: .pro,
                interval: .monthly,
                amount: Decimal(string: "9.99")!,
                currencyCode: "USD",
                status: .pending,
                pdfURL: nil
            ),
            Invoice(
                id: "inv_0998",
                date: calendar.date(byAdding: .month, value: -6, to: Date()) ?? Date(),
                description: "SpectRoom Pro — Monthly",
                planTier: .pro,
                interval: .monthly,
                amount: Decimal(string: "9.99")!,
                currencyCode: "USD",
                status: .paid,
                pdfURL: URL(string: "https://example.com/invoices/inv_0998.pdf")
            ),
            Invoice(
                id: "inv_old",
                date: calendar.date(byAdding: .year, value: -4, to: Date()) ?? Date(),
                description: "SpectRoom Pro — Monthly",
                planTier: .pro,
                interval: .monthly,
                amount: Decimal(string: "9.99")!,
                currencyCode: "USD",
                status: .paid,
                pdfURL: nil
            )
        ]

        return BillingSnapshot(
            subscription: subscription,
            availablePlans: plans,
            paymentMethods: methods,
            invoices: invoices,
            applePayEnabled: true,
            googlePayEnabled: false
        )
    }

    private static func persistSubscription(_ subscription: CurrentSubscription) {
        guard let data = try? JSONEncoder().encode(subscription) else { return }
        UserDefaults.standard.set(data, forKey: persistedSubscriptionKey)
    }

    private static func loadPersistedSubscription(validPlanIds: Set<String>) -> CurrentSubscription? {
        if let data = UserDefaults.standard.data(forKey: persistedSubscriptionKey),
           let subscription = try? JSONDecoder().decode(CurrentSubscription.self, from: data),
           validPlanIds.contains(subscription.planId) {
            return subscription
        }

        // Fallback for upgrades made before subscription persistence existed.
        let tier = DiscoverDailyLimit.currentPlanTier
        guard tier != .free else { return nil }
        let planId: String
        switch tier {
        case .free: planId = "plan_free"
        case .pro: planId = "plan_pro"
        case .premium: planId = "plan_premium"
        }
        guard validPlanIds.contains(planId) else { return nil }
        let restored = CurrentSubscription(
            planId: planId,
            tier: tier,
            status: .renewing,
            interval: .monthly,
            renewsOn: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
            cancelledAt: nil,
            usageSummary: tier.usageSummaryKey
        )
        persistSubscription(restored)
        return restored
    }
}

enum BillingServiceError: LocalizedError {
    case planNotFound
    case paymentMethodNotFound
    case invalidCard
    case nothingToCancel
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .planNotFound:
            return "billing.error.plan.not.found".localized
        case .paymentMethodNotFound:
            return "billing.error.payment.not.found".localized
        case .invalidCard:
            return "billing.error.invalid.card".localized
        case .nothingToCancel:
            return "billing.error.nothing.to.cancel".localized
        case .generic(let message):
            return message
        }
    }
}
