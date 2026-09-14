import SwiftUI

@MainActor
final class AccountBillingViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var toastMessage: String?
    @Published var selectedInterval: BillingInterval = .monthly
    @Published var subscription: CurrentSubscription?
    @Published var plans: [SubscriptionPlan] = []
    @Published var invoices: [Invoice] = []
    @Published var isBusy = false
    @Published var isExportingBillingHistory = false

    @Published var pendingPlanChange: SubscriptionPlan?
    @Published var planChangeSuccessLabel: String?
    @Published var showingCancelConfirm = false
    @Published var cancelSuccessPlanLabel: String?

    private let service: BillingServicing

    init(service: BillingServicing? = nil) {
        self.service = service ?? MockBillingService.shared
    }

    var currentPlan: SubscriptionPlan? {
        plans.first(where: { $0.id == subscription?.planId })
            ?? plans.first(where: { $0.tier == subscription?.tier })
    }

    var recentInvoices: [Invoice] {
        let cutoff = Calendar.current.date(byAdding: .year, value: -3, to: Date()) ?? .distantPast
        return invoices
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            let snap = try await service.fetchBillingSnapshot()
            apply(snap)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    /// Call after capturing/clearing `pendingPlanChange` so the confirm alert dismisses immediately.
    func performPlanChange(_ plan: SubscriptionPlan) async {
        let targetLabel = changeTargetLabel(for: plan)
        isBusy = true
        defer { isBusy = false }
        do {
            subscription = try await service.changePlan(to: plan.id, interval: selectedInterval)
            planChangeSuccessLabel = targetLabel
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func dismissPlanChangeDialog() {
        pendingPlanChange = nil
        planChangeSuccessLabel = nil
    }

    func performCancelSubscription(planLabel: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            subscription = try await service.cancelSubscription()
            cancelSuccessPlanLabel = planLabel
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func cancelSuccessMessage(planLabel: String) -> String {
        String(format: "billing.cancel.success.message".localized, planLabel)
    }

    func exportBillingHistoryPDF() async -> URL? {
        guard !recentInvoices.isEmpty else {
            showToast("billing.invoices.empty".localized)
            return nil
        }
        isExportingBillingHistory = true
        defer { isExportingBillingHistory = false }
        do {
            let email = FirebaseAuthService.shared.auth.currentUser?.email ?? ""
            return try BillingHistoryExport.writePDFFile(
                accountEmail: email,
                invoices: recentInvoices
            )
        } catch {
            showToast("billing.invoices.export.error".localized)
            return nil
        }
    }

    func actionTitle(for plan: SubscriptionPlan) -> String {
        guard let current = subscription else {
            return String(format: "billing.action.change.to".localized, changeTargetLabel(for: plan))
        }
        if isCurrent(plan) {
            if plan.tier != .free, current.status == .cancelled {
                return String(
                    format: "billing.action.renew.interval".localized,
                    selectedInterval.adjectiveKey.localized
                )
            }
            if canCancelCurrentPlan(plan) {
                return "billing.action.cancel.plan".localized
            }
            if plan.tier != .free, current.status != .cancelled, current.interval != selectedInterval {
                return String(format: "billing.action.change.to".localized, changeTargetLabel(for: plan))
            }
            return "billing.action.current".localized
        }
        return String(format: "billing.action.change.to".localized, changeTargetLabel(for: plan))
    }

    /// Current paid plan that can still be cancelled (same billing interval selected).
    func canCancelCurrentPlan(_ plan: SubscriptionPlan) -> Bool {
        guard isCurrent(plan), plan.tier != .free else { return false }
        guard let subscription, subscription.status != .cancelled else { return false }
        return subscription.interval == selectedInterval
    }

    /// Cancelled paid plan that can be renewed for the selected interval.
    func canRenewCancelledPlan(_ plan: SubscriptionPlan) -> Bool {
        guard isCurrent(plan), plan.tier != .free else { return false }
        return subscription?.status == .cancelled
    }

    /// Same tier + interval as the live subscription (Free ignores interval).
    /// Cancelled plans are never treated as exact current so renew stays tappable.
    func isExactCurrentSelection(_ plan: SubscriptionPlan) -> Bool {
        guard isCurrent(plan) else { return false }
        if plan.tier == .free { return true }
        guard subscription?.status != .cancelled else { return false }
        return subscription?.interval == selectedInterval
    }

    private func changeTargetLabel(for plan: SubscriptionPlan) -> String {
        let planName = plan.tier.displayNameKey.localized
        guard plan.tier != .free else { return planName }
        return "\(selectedInterval.adjectiveKey.localized) \(planName)"
    }

    func currentPlanLabel() -> String {
        guard let current = subscription else { return "billing.plan.free".localized }
        let planName = current.tier.displayNameKey.localized
        guard current.tier != .free else { return planName }
        return "\(current.interval.adjectiveKey.localized) \(planName)"
    }

    func planChangeAlertTitle(for plan: SubscriptionPlan) -> String {
        String(format: "billing.action.change.to".localized, changeTargetLabel(for: plan))
    }

    func planChangeAlertMessage(for plan: SubscriptionPlan) -> String {
        let confirm = String(
            format: "billing.change.confirm.message".localized,
            currentPlanLabel(),
            changeTargetLabel(for: plan)
        )
        return "\(confirm)\n\n\(billingOutcomeExplanation(for: plan))"
    }

    func planChangeSuccessMessage(planLabel: String) -> String {
        String(format: "billing.change.success.message".localized, planLabel)
    }

    /// Charge / proration outcome shown under the confirm question.
    func billingOutcomeExplanation(for plan: SubscriptionPlan) -> String {
        if plan.tier == .free {
            return "billing.modal.downgrade.free".localized
        }
        let price = plan.formattedPrice(for: selectedInterval)
        let cycle = selectedInterval.titleKey.localized
        return String(format: "billing.modal.proration".localized, price, cycle)
    }

    func isCurrent(_ plan: SubscriptionPlan) -> Bool {
        subscription?.planId == plan.id || subscription?.tier == plan.tier
    }

    private func apply(_ snap: BillingSnapshot) {
        subscription = snap.subscription
        plans = snap.availablePlans
        invoices = snap.invoices.sorted { $0.date > $1.date }
        selectedInterval = snap.subscription.interval
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

struct AccountBillingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = AccountBillingViewModel()
    @State private var billingExportURL: URL?

    var body: some View {
        NavigationView {
            ZStack {
                SpectRoomBackground()

                Group {
                    if viewModel.isLoading {
                        billingSkeleton
                    } else if let loadError = viewModel.loadError {
                        errorState(loadError)
                    } else {
                        billingContent
                    }
                }

                if let toast = viewModel.toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.black.opacity(0.82)))
                            .padding(.bottom, 28)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.25), value: viewModel.toastMessage)
                }
            }
            .navigationTitle("billing.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close".localized) { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .alert(
                String(
                    format: "billing.cancel.confirm.title".localized,
                    (viewModel.subscription?.tier.displayNameKey.localized ?? "billing.plan.pro".localized)
                ),
                isPresented: $viewModel.showingCancelConfirm
            ) {
                Button("billing.cancel.confirm.yes".localized, role: .destructive) {
                    let planLabel = viewModel.subscription?.tier.displayNameKey.localized
                        ?? "billing.plan.pro".localized
                    viewModel.showingCancelConfirm = false
                    Task { await viewModel.performCancelSubscription(planLabel: planLabel) }
                }
                Button("billing.cancel.confirm.no".localized, role: .cancel) {}
            } message: {
                Text("billing.cancel.confirm.message".localized)
            }
            .alert(
                "billing.cancel.success.title".localized,
                isPresented: Binding(
                    get: { viewModel.cancelSuccessPlanLabel != nil },
                    set: { if !$0 { viewModel.cancelSuccessPlanLabel = nil } }
                )
            ) {
                Button("common.ok".localized, role: .cancel) {
                    viewModel.cancelSuccessPlanLabel = nil
                }
            } message: {
                if let label = viewModel.cancelSuccessPlanLabel {
                    Text(viewModel.cancelSuccessMessage(planLabel: label))
                }
            }
            .alert(
                viewModel.pendingPlanChange.map { viewModel.planChangeAlertTitle(for: $0) } ?? "",
                isPresented: Binding(
                    get: { viewModel.pendingPlanChange != nil },
                    set: { if !$0 { viewModel.pendingPlanChange = nil } }
                )
            ) {
                Button("billing.modal.confirm".localized) {
                    guard let plan = viewModel.pendingPlanChange else { return }
                    viewModel.pendingPlanChange = nil
                    Task { await viewModel.performPlanChange(plan) }
                }
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.dismissPlanChangeDialog()
                }
            } message: {
                if let plan = viewModel.pendingPlanChange {
                    Text(viewModel.planChangeAlertMessage(for: plan))
                }
            }
            .alert(
                "billing.change.success.title".localized,
                isPresented: Binding(
                    get: { viewModel.planChangeSuccessLabel != nil },
                    set: { if !$0 { viewModel.planChangeSuccessLabel = nil } }
                )
            ) {
                Button("common.ok".localized, role: .cancel) {
                    viewModel.planChangeSuccessLabel = nil
                }
            } message: {
                if let label = viewModel.planChangeSuccessLabel {
                    Text(viewModel.planChangeSuccessMessage(planLabel: label))
                }
            }
            .sheet(isPresented: Binding(
                get: { billingExportURL != nil },
                set: { if !$0 { billingExportURL = nil } }
            )) {
                if let billingExportURL {
                    ActivityShareSheet(items: [billingExportURL])
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Content

    private var billingContent: some View {
        VStack(spacing: 0) {
            billingIntervalSection
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
                .frame(maxWidth: .infinity)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    changePlanSection
                    invoicesSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: A. Billing interval

    private var billingIntervalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            billingIntervalToggle
        }
        .billingCardStyle()
    }

    // MARK: B. Change plan

    private var changePlanSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                ForEach(viewModel.plans) { plan in
                    planCard(plan)
                }
            }
        }
        .billingCardStyle()
    }

    private var billingIntervalToggle: some View {
        HStack(spacing: 8) {
            ForEach(BillingInterval.allCases) { interval in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedInterval = interval
                    }
                } label: {
                    let isSelected = viewModel.selectedInterval == interval
                    HStack(spacing: 4) {
                        Text(interval.titleKey.localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(isSelected ? .white : SpectRoomTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .layoutPriority(1)
                        if interval == .yearly {
                            Text("billing.save.percent".localized)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .foregroundColor(isSelected ? .white : Color(red: 0.05, green: 0.45, blue: 0.2))
                                .background(
                                    Capsule().fill(isSelected ? Color.green : Color.green.opacity(0.22))
                                )
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.blue : SpectRoomTheme.background)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpectRoomTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let canCancel = viewModel.canCancelCurrentPlan(plan)
        let canRenew = viewModel.canRenewCancelledPlan(plan)
        let isExactCurrent = viewModel.isExactCurrentSelection(plan)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack {
                HStack(spacing: 4) {
                    Text(plan.tier.displayNameKey.localized)
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                    if !plan.tier.titleStars.isEmpty {
                        Text(plan.tier.titleStars)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)

                if isExactCurrent {
                    HStack {
                        Spacer()
                        Text("billing.badge.current".localized)
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundColor(.blue)
                    }
                }
            }

            if plan.tier == .free {
                Text("billing.price.no.charge".localized)
                    .font(.title3.weight(.bold))
                    .foregroundColor(SpectRoomTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                planPriceLine(for: plan)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.tier.featureKeys, id: \.self) { featureKey in
                    Label {
                        Text(featureKey.localized)
                            .font(.subheadline)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
            }

            Button {
                if canCancel {
                    viewModel.showingCancelConfirm = true
                } else if canRenew || !isExactCurrent {
                    viewModel.planChangeSuccessLabel = nil
                    viewModel.pendingPlanChange = plan
                }
            } label: {
                Text(viewModel.actionTitle(for: plan))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(canCancel ? .red : (isExactCurrent ? SpectRoomTheme.secondaryText : .white))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                canCancel
                                    ? Color.red.opacity(0.08)
                                    : (isExactCurrent ? Color.primary.opacity(0.08) : Color.blue)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy || (isExactCurrent && !canCancel))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isExactCurrent ? Color.green.opacity(0.1) : SpectRoomTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isExactCurrent ? Color.green.opacity(0.45) : SpectRoomTheme.subtleBorder(for: colorScheme),
                            lineWidth: isExactCurrent ? 1.5 : 1
                        )
                )
        )
    }

    // MARK: C. Invoices / billing history

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("billing.section.invoices".localized, systemImage: "doc.text.fill")
                Spacer()
                Button {
                    Task {
                        if let url = await viewModel.exportBillingHistoryPDF() {
                            billingExportURL = url
                        }
                    }
                } label: {
                    if viewModel.isExportingBillingHistory {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("billing.invoices.export".localized, systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isExportingBillingHistory || viewModel.recentInvoices.isEmpty)
                .accessibilityLabel("billing.invoices.export".localized)
            }

            if viewModel.recentInvoices.isEmpty {
                emptyInline(message: "billing.invoices.empty".localized)
            } else {
                let rowHeight: CGFloat = 62
                let maxVisibleRows = 6
                let visibleCount = min(viewModel.recentInvoices.count, maxVisibleRows)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.recentInvoices) { invoice in
                            invoiceRow(invoice)
                            if invoice.id != viewModel.recentInvoices.last?.id {
                                Divider().padding(.leading, 4)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(visibleCount) * rowHeight)
                .scrollIndicators(.visible)
            }
        }
        .billingCardStyle()
    }

    private func invoiceRow(_ invoice: Invoice) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoice.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                Text(invoice.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(invoice.formattedAmount())
                .font(.subheadline.weight(.bold))
                .foregroundColor(SpectRoomTheme.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundColor(SpectRoomTheme.text)
    }

    private func planPriceLine(for plan: SubscriptionPlan) -> some View {
        let price = plan.formattedPrice(for: viewModel.selectedInterval)
        let period = viewModel.selectedInterval == .yearly
            ? "billing.per.year".localized
            : "billing.per.month".localized
        return (Text(price)
            .font(.title3.weight(.bold))
            + Text(" \(period)")
            .font(.subheadline.weight(.semibold)))
            .foregroundColor(SpectRoomTheme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyInline(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(SpectRoomTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var billingSkeleton: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 140)
                        .redacted(reason: .placeholder)
                }
            }
            .padding(16)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.secondaryText)
            Button("common.retry".localized) {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

private extension View {
    func billingCardStyle() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SpectRoomTheme.card)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}
