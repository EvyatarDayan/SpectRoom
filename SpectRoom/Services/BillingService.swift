import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
protocol BillingServicing {
    func fetchBillingSnapshot() async throws -> BillingSnapshot
    /// Current snapshot without artificial delay (for refreshing UI after mutations).
    func currentBillingSnapshot() -> BillingSnapshot
    func refreshPlanFromFirestore() async
    func changePlan(to planId: String, interval: BillingInterval) async throws -> CurrentSubscription
    func cancelSubscription() async throws -> CurrentSubscription
    func setDefaultPaymentMethod(id: String) async throws -> [PaymentMethod]
    func deletePaymentMethod(id: String) async throws -> [PaymentMethod]
    func addCard(_ draft: NewCardDraft) async throws -> [PaymentMethod]
    func updateCard(id: String, draft: NewCardDraft) async throws -> [PaymentMethod]
    func toggleApplePay(enabled: Bool) async throws -> Bool
    func toggleGooglePay(enabled: Bool) async throws -> Bool
}

/// Best-effort branded plan-change emails (same Cloud Function template as welcome mail).
enum PlanChangeEmailNotifier {
    static func notifyChanged(
        from previous: CurrentSubscription,
        to next: CurrentSubscription
    ) async {
        await send([
            "changeType": "changed",
            "fromPlan": previous.tier.emailPlanName,
            "fromInterval": previous.tier == .free ? "" : previous.interval.emailIntervalName,
            "toPlan": next.tier.emailPlanName,
            "toInterval": next.tier == .free ? "" : next.interval.emailIntervalName,
        ])
    }

    static func notifyCancelled(_ subscription: CurrentSubscription) async {
        var payload: [String: Any] = [
            "changeType": "cancelled",
            "fromPlan": subscription.tier.emailPlanName,
            "fromInterval": subscription.interval.emailIntervalName,
            "toPlan": "Free",
            "toInterval": "",
        ]
        if let renewsOn = subscription.renewsOn {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB_POSIX")
            formatter.dateFormat = "dd/MM/yyyy"
            payload["accessUntil"] = formatter.string(from: renewsOn)
        }
        await send(payload)
    }

    private static func send(_ data: [String: Any]) async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("sendSpectRoomPlanChangeEmail")
                .call(data)
            print("✅ Plan change email requested")
        } catch {
            print("⚠️ Plan change email failed: \(error.localizedDescription)")
        }
    }
}

private extension PlanTier {
    var emailPlanName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .premium: return "Premium"
        }
    }
}

private extension BillingInterval {
    var emailIntervalName: String {
        switch self {
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        }
    }
}

/// Local mock billing backend until StoreKit / Stripe is wired.
@MainActor
final class MockBillingService: BillingServicing {
    static let shared = MockBillingService()

    private static let persistedSubscriptionKey = "mockBillingCurrentSubscription"
    private static let persistedAccountHistoryKey = "mockBillingAccountHistory"

    private var snapshot: BillingSnapshot
    private let delayNanoseconds: UInt64 = 650_000_000

    private init() {
        snapshot = Self.makeInitialSnapshot()
        Task { await processDueAutomaticBillingIfNeeded() }
        // Do not write UserDefaults here for plan — Firestore hydrate owns the displayed plan.
    }

    func currentBillingSnapshot() -> BillingSnapshot {
        return snapshot
    }

    /// Align mock billing with the plan stored on the user document (startup / profile load / live sync).
    func applyRemotePlanTier(
        _ tier: PlanTier,
        interval: BillingInterval? = nil,
        status: SubscriptionStatus? = nil
    ) {
        guard let plan = snapshot.availablePlans.first(where: { $0.tier == tier }) else { return }
        let resolvedInterval: BillingInterval = {
            if tier == .free { return .monthly }
            return interval ?? snapshot.subscription.interval
        }()
        let resolvedStatus: SubscriptionStatus = {
            if tier == .free { return .none }
            return status ?? snapshot.subscription.status
        }()
        let renews = Calendar.current.date(
            byAdding: resolvedInterval == .yearly ? .year : .month,
            value: 1,
            to: Date()
        )
        let keepCancelled =
            resolvedStatus == .cancelled
            && tier != .free
        snapshot.subscription = CurrentSubscription(
            planId: plan.id,
            tier: plan.tier,
            status: keepCancelled ? .cancelled : resolvedStatus,
            interval: resolvedInterval,
            renewsOn: plan.tier == .free ? nil : (keepCancelled ? (snapshot.subscription.renewsOn ?? renews) : (snapshot.subscription.renewsOn ?? renews)),
            cancelledAt: plan.tier == .free ? nil : (keepCancelled ? (snapshot.subscription.cancelledAt ?? Date()) : nil),
            usageSummary: plan.usageSummary
        )
        Self.persistSubscription(snapshot.subscription)
        DiscoverDailyLimit.applyLocalPlanTier(tier)
    }

    var currentSubscription: CurrentSubscription { snapshot.subscription }

    func fetchBillingSnapshot() async throws -> BillingSnapshot {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        // Keep mock display aligned with the hydrated local plan cache (Firestore SoT).
        let cached = DiscoverDailyLimit.currentPlanTier
        if snapshot.subscription.tier != cached {
            applyRemotePlanTier(cached, interval: snapshot.subscription.interval)
        }
        await processDueAutomaticBillingIfNeeded()
        await refreshAccountHistoryFromCloud()
        return snapshot
    }

    /// Pull latest `planTier` / `billingInterval` from Firestore and apply locally.
    func refreshPlanFromFirestore() async {
        guard let data = try? await FirebaseAuthService.shared.fetchUserData(preferServer: true) else { return }
        let parsed = PlanTierCloudSync.parseBillingPlan(from: data)
        await MainActor.run {
            PlanTierCloudSync.applyRemoteBillingPlan(
                tier: parsed.tier,
                interval: parsed.interval,
                status: parsed.status
            )
        }
        await refreshAccountHistoryFromCloud()
    }

    func changePlan(to planId: String, interval: BillingInterval) async throws -> CurrentSubscription {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let plan = snapshot.availablePlans.first(where: { $0.id == planId }) else {
            throw BillingServiceError.planNotFound
        }

        let previous = snapshot.subscription
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
        DiscoverDailyLimit.syncPlanTier(plan.tier, interval: plan.tier == .free ? nil : interval)

        let next = snapshot.subscription
        let changed =
            previous.tier != next.tier
            || previous.interval != next.interval
            || previous.status == .cancelled
        if changed {
            await appendPlanChangeHistory(from: previous, to: next, plan: plan)
            Task { await PlanChangeEmailNotifier.notifyChanged(from: previous, to: next) }
        }
        return next
    }

    func cancelSubscription() async throws -> CurrentSubscription {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard snapshot.subscription.tier != .free else {
            throw BillingServiceError.nothingToCancel
        }
        let beforeCancel = snapshot.subscription
        snapshot.subscription.status = .cancelled
        snapshot.subscription.cancelledAt = Date()
        if snapshot.subscription.renewsOn == nil {
            snapshot.subscription.renewsOn = Calendar.current.date(
                byAdding: snapshot.subscription.interval == .yearly ? .year : .month,
                value: 1,
                to: Date()
            )
        }
        Self.persistSubscription(snapshot.subscription)
        let cancelled = snapshot.subscription
        await appendHistoryEvent(
            AccountHistoryEvent(
                kind: .cancelPlan,
                planTier: beforeCancel.tier,
                interval: beforeCancel.interval
            )
        )
        Task { await PlanChangeEmailNotifier.notifyCancelled(cancelled) }
        Task { @MainActor in
            await PlanTierCloudSync.pushCancellationToFirestore(
                tier: beforeCancel.tier,
                interval: beforeCancel.interval,
                cancelledAt: cancelled.cancelledAt ?? Date()
            )
        }
        // Cancelled paid plans keep remaining access for the period; swipe quota stays on current tier.
        return cancelled
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

        return BillingSnapshot(
            subscription: subscription,
            availablePlans: plans,
            paymentMethods: methods,
            accountHistory: [],
            applePayEnabled: true,
            googlePayEnabled: false
        )
    }

    private func appendPlanChangeHistory(
        from previous: CurrentSubscription,
        to next: CurrentSubscription,
        plan: SubscriptionPlan
    ) async {
        let kind: AccountHistoryEventKind = {
            if previous.tier == .free, next.tier != .free {
                return .newPlan
            }
            return .changePlan
        }()

        let now = Date()

        // Paid take-up also records the charge. Give the plan action a slightly
        // later timestamp so it stays above the charge after date sorting.
        if next.tier != .free {
            await appendAutomaticBillingEvent(for: plan, interval: next.interval, at: now)
        }

        await appendHistoryEvent(
            AccountHistoryEvent(
                date: now.addingTimeInterval(0.001),
                kind: kind,
                planTier: next.tier,
                interval: next.interval
            )
        )
    }

    private func appendAutomaticBillingEvent(
        for plan: SubscriptionPlan,
        interval: BillingInterval,
        at date: Date
    ) async {
        await appendHistoryEvent(
            AccountHistoryEvent(
                date: date,
                kind: .automaticBilling,
                planTier: plan.tier,
                interval: interval,
                amount: plan.price(for: interval),
                currencyCode: plan.currencyCode,
                status: .paid
            )
        )
    }

    private func appendHistoryEvent(_ event: AccountHistoryEvent) async {
        let pushed = await AccountHistoryCloudSync.pushEvent(event)
        guard pushed else { return }
        // Display list comes only from Firestore.
        await refreshAccountHistoryFromCloud()
    }

    /// Firestore is the only source for the Account History list when signed in.
    private func refreshAccountHistoryFromCloud() async {
        let remote = await AccountHistoryCloudSync.fetchEvents()
        snapshot.accountHistory = remote
        Self.persistAccountHistory(remote)
    }

    /// When a renewing paid plan's period ends, log automatic billing and roll `renewsOn` forward.
    /// Cancelled plans that lapse become Free (no billing charge).
    private func processDueAutomaticBillingIfNeeded() async {
        var subscription = snapshot.subscription
        guard subscription.tier != .free,
              let renewsOn = subscription.renewsOn,
              renewsOn <= Date() else { return }

        guard let plan = snapshot.availablePlans.first(where: { $0.id == subscription.planId }) else { return }

        if subscription.status == .cancelled {
            subscription = CurrentSubscription(
                planId: "plan_free",
                tier: .free,
                status: .none,
                interval: .monthly,
                renewsOn: nil,
                cancelledAt: nil,
                usageSummary: PlanTier.free.usageSummaryKey
            )
            snapshot.subscription = subscription
            Self.persistSubscription(subscription)
            DiscoverDailyLimit.syncPlanTier(.free, interval: nil)
            await appendHistoryEvent(
                AccountHistoryEvent(
                    date: renewsOn,
                    kind: .changePlan,
                    planTier: .free,
                    interval: .monthly
                )
            )
            return
        }

        // Catch up any missed renewal periods (mock auto-billing).
        var cursor = renewsOn
        let now = Date()
        var safety = 0
        while cursor <= now, safety < 36 {
            await appendAutomaticBillingEvent(for: plan, interval: subscription.interval, at: cursor)
            cursor = Calendar.current.date(
                byAdding: subscription.interval == .yearly ? .year : .month,
                value: 1,
                to: cursor
            ) ?? now.addingTimeInterval(1)
            safety += 1
        }
        subscription.renewsOn = cursor
        subscription.status = .renewing
        snapshot.subscription = subscription
        Self.persistSubscription(subscription)
    }

    private static func persistSubscription(_ subscription: CurrentSubscription) {
        guard let data = try? JSONEncoder().encode(subscription) else { return }
        UserDefaults.standard.set(data, forKey: persistedSubscriptionKey)
    }

    private static func persistAccountHistory(_ events: [AccountHistoryEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: persistedAccountHistoryKey)
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
