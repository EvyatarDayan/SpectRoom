import SwiftUI

@MainActor
final class AccountBillingViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var toastMessage: String?
    @Published var selectedInterval: BillingInterval = .monthly
    @Published var subscription: CurrentSubscription?
    @Published var plans: [SubscriptionPlan] = []
    @Published var paymentMethods: [PaymentMethod] = []
    @Published var invoices: [Invoice] = []
    @Published var applePayEnabled = false
    @Published var googlePayEnabled = false
    @Published var isBusy = false
    @Published var isExportingBillingHistory = false

    @Published var pendingPlanChange: SubscriptionPlan?
    @Published var showingCancelConfirm = false
    @Published var paymentMethodPendingDelete: PaymentMethod?
    @Published var showingDeleteCardConfirm = false
    @Published var editingPaymentMethod: PaymentMethod?
    @Published var showingAddCard = false
    @Published var newCard = NewCardDraft()
    @Published var didAttemptCardSave = false
    /// Edit mode: card number shows `**** **** **** 1234` until the field is focused.
    @Published var cardNumberIsMasked = false
    /// Edit mode: CVC shows `***` until the field is focused.
    @Published var cvcIsMasked = false

    private let service: BillingServicing

    init(service: BillingServicing? = nil) {
        self.service = service ?? MockBillingService.shared
    }

    var isShowingCardForm: Bool {
        showingAddCard || editingPaymentMethod != nil
    }

    var isEditingCard: Bool {
        editingPaymentMethod != nil
    }

    var isCardFormValid: Bool {
        if isEditingCard {
            return newCard.isCardNameValid
                && newCard.isExpiryValid
                && (newCard.cardholderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || newCard.isCardholderNameValid)
                && (cardNumberIsMasked || newCard.cardNumber.isEmpty || newCard.isCardNumberLengthValid)
                && (cvcIsMasked || newCard.cvc.isEmpty || newCard.isCVCValid)
                && (newCard.postalCode.isEmpty || newCard.isPostalCodeValid)
        }
        return newCard.isValid
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

    func confirmPlanChange() async {
        guard let plan = pendingPlanChange else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            subscription = try await service.changePlan(to: plan.id, interval: selectedInterval)
            pendingPlanChange = nil
            showToast(String(format: "billing.toast.plan.updated".localized, plan.name))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func cancelSubscription() async {
        isBusy = true
        defer { isBusy = false }
        do {
            subscription = try await service.cancelSubscription()
            showingCancelConfirm = false
            showToast("billing.toast.subscription.cancelled".localized)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func setDefault(_ method: PaymentMethod) async {
        isBusy = true
        defer { isBusy = false }
        do {
            paymentMethods = try await service.setDefaultPaymentMethod(id: method.id)
            showToast("billing.toast.default.updated".localized)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func deletePaymentMethod() async {
        guard let method = paymentMethodPendingDelete else { return }
        let methodId = method.id
        isBusy = true
        defer { isBusy = false }
        do {
            paymentMethods = try await service.deletePaymentMethod(id: methodId)
            paymentMethodPendingDelete = nil
            showingDeleteCardConfirm = false
            showToast("billing.toast.card.removed".localized)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func requestDeletePaymentMethod(_ method: PaymentMethod) {
        paymentMethodPendingDelete = method
        showingDeleteCardConfirm = true
    }

    func cancelDeletePaymentMethod() {
        paymentMethodPendingDelete = nil
        showingDeleteCardConfirm = false
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

    func addCard() async {
        didAttemptCardSave = true
        guard newCard.isValid else {
            showToast("billing.error.invalid.card".localized)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            paymentMethods = try await service.addCard(newCard)
            dismissCardForm()
            showToast("billing.toast.card.added".localized)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func beginEditingCard(_ method: PaymentMethod) {
        editingPaymentMethod = method
        showingAddCard = false
        didAttemptCardSave = false
        newCard = NewCardDraft.draft(forEditing: method)
        if let last4 = method.last4, last4.count == 4 {
            newCard.cardNumber = "**** **** **** \(last4)"
            cardNumberIsMasked = true
        } else {
            newCard.cardNumber = ""
            cardNumberIsMasked = false
        }
        newCard.cvc = "***"
        cvcIsMasked = true
    }

    func clearMaskedCardNumberIfNeeded() {
        guard cardNumberIsMasked else { return }
        newCard.cardNumber = ""
        cardNumberIsMasked = false
    }

    func clearMaskedCVCIfNeeded() {
        guard cvcIsMasked else { return }
        newCard.cvc = ""
        cvcIsMasked = false
    }

    func dismissCardForm() {
        showingAddCard = false
        editingPaymentMethod = nil
        newCard = NewCardDraft()
        didAttemptCardSave = false
        cardNumberIsMasked = false
        cvcIsMasked = false
    }

    func saveCardForm() async {
        if isEditingCard {
            await updateCard()
        } else {
            await addCard()
        }
    }

    func updateCard() async {
        guard let method = editingPaymentMethod else { return }
        didAttemptCardSave = true
        var draft = newCard
        if cardNumberIsMasked {
            draft.cardNumber = ""
        }
        if cvcIsMasked {
            draft.cvc = ""
        }
        guard draft.isValidForEdit else {
            showToast("billing.error.invalid.card".localized)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            paymentMethods = try await service.updateCard(id: method.id, draft: draft)
            dismissCardForm()
            showToast("billing.toast.card.updated".localized)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func toggleApplePay(_ enabled: Bool) async {
        do {
            applePayEnabled = try await service.toggleApplePay(enabled: enabled)
        } catch {
            applePayEnabled = !enabled
            showToast(error.localizedDescription)
        }
    }

    func toggleGooglePay(_ enabled: Bool) async {
        do {
            googlePayEnabled = try await service.toggleGooglePay(enabled: enabled)
        } catch {
            googlePayEnabled = !enabled
            showToast(error.localizedDescription)
        }
    }

    func actionTitle(for plan: SubscriptionPlan) -> String {
        guard let current = subscription else { return "billing.action.select".localized }
        if plan.id == current.planId || plan.tier == current.tier {
            return "billing.action.current".localized
        }
        let order: [PlanTier] = [.free, .pro, .premium]
        let currentIndex = order.firstIndex(of: current.tier) ?? 0
        let nextIndex = order.firstIndex(of: plan.tier) ?? 0
        return nextIndex > currentIndex
            ? "billing.action.upgrade".localized
            : "billing.action.downgrade".localized
    }

    func isCurrent(_ plan: SubscriptionPlan) -> Bool {
        subscription?.planId == plan.id || subscription?.tier == plan.tier
    }

    func prorationSummary(for plan: SubscriptionPlan) -> String {
        let price = plan.formattedPrice(for: selectedInterval)
        let cycle = selectedInterval.titleKey.localized
        if isCurrent(plan) {
            return "billing.modal.already.current".localized
        }
        if plan.tier == .free {
            return "billing.modal.downgrade.free".localized
        }
        return String(format: "billing.modal.proration".localized, price, cycle)
    }

    private func apply(_ snap: BillingSnapshot) {
        subscription = snap.subscription
        plans = snap.availablePlans
        paymentMethods = snap.paymentMethods
        invoices = snap.invoices.sorted { $0.date > $1.date }
        applePayEnabled = snap.applePayEnabled
        googlePayEnabled = snap.googlePayEnabled
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
    private enum CardFormFocus: Hashable {
        case cardNumber
        case cvc
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = AccountBillingViewModel()
    @State private var showingCVCHelp = false
    @State private var billingExportURL: URL?
    @FocusState private var cardFormFocus: CardFormFocus?

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
            .sheet(isPresented: Binding(
                get: { viewModel.isShowingCardForm },
                set: { if !$0 { viewModel.dismissCardForm() } }
            )) {
                addCardSheet
            }
            .confirmationDialog(
                "billing.cancel.confirm.title".localized,
                isPresented: $viewModel.showingCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("billing.cancel.confirm.action".localized, role: .destructive) {
                    Task { await viewModel.cancelSubscription() }
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("billing.cancel.confirm.message".localized)
            }
            .alert(
                "billing.delete.card.title".localized,
                isPresented: $viewModel.showingDeleteCardConfirm
            ) {
                Button("common.cancel".localized, role: .cancel) {
                    viewModel.cancelDeletePaymentMethod()
                }
                Button("common.delete".localized, role: .destructive) {
                    Task { await viewModel.deletePaymentMethod() }
                }
            } message: {
                Text("billing.delete.card.message".localized)
            }
            .sheet(item: $viewModel.pendingPlanChange) { plan in
                planChangeSheet(plan)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                billingIntervalSection
                changePlanSection
                paymentMethodsSection
                invoicesSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: horizontalSizeClass == .regular ? 720 : .infinity)
            .frame(maxWidth: .infinity)
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

            if let subscription = viewModel.subscription,
               subscription.tier != .free,
               subscription.status != .cancelled {
                Button {
                    viewModel.showingCancelConfirm = true
                } label: {
                    Text(
                        subscription.status == .renewing
                            ? "billing.action.manage.renewal".localized
                            : "billing.action.cancel".localized
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.red)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
                .padding(.top, 4)
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
                    HStack(spacing: 6) {
                        Text(interval.titleKey.localized)
                            .font(.subheadline.weight(.semibold))
                        if interval == .yearly {
                            Text("billing.save.percent".localized)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.green.opacity(0.2)))
                                .foregroundColor(.green)
                        }
                    }
                    .foregroundColor(viewModel.selectedInterval == interval ? .white : SpectRoomTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(viewModel.selectedInterval == interval ? Color.blue : SpectRoomTheme.background)
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
        let isCurrent = viewModel.isCurrent(plan)
        return VStack(alignment: .leading, spacing: 10) {
            ZStack {
                HStack(spacing: 4) {
                    Text(plan.tier.displayNameKey.localized)
                        .font(.headline)
                        .foregroundColor(SpectRoomTheme.text)
                    Text(plan.tier.titleStars)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)

                if isCurrent {
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
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(plan.formattedPrice(for: viewModel.selectedInterval))
                        .font(.title3.weight(.bold))
                        .foregroundColor(SpectRoomTheme.text)
                    Text(viewModel.selectedInterval == .yearly ? "billing.per.year".localized : "billing.per.month".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                }
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
                guard !isCurrent else { return }
                viewModel.pendingPlanChange = plan
            } label: {
                Text(viewModel.actionTitle(for: plan))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(isCurrent ? SpectRoomTheme.secondaryText : .white)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isCurrent ? Color.primary.opacity(0.08) : Color.blue)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isCurrent || viewModel.isBusy)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? Color.green.opacity(0.1) : SpectRoomTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isCurrent ? Color.green.opacity(0.45) : SpectRoomTheme.subtleBorder(for: colorScheme),
                            lineWidth: isCurrent ? 1.5 : 1
                        )
                )
        )
    }

    // MARK: C. Payment methods

    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("billing.section.payment.methods".localized, systemImage: "creditcard.fill")
                Spacer()
                Button {
                    viewModel.editingPaymentMethod = nil
                    viewModel.newCard = NewCardDraft()
                    viewModel.didAttemptCardSave = false
                    viewModel.cardNumberIsMasked = false
                    viewModel.cvcIsMasked = false
                    viewModel.showingAddCard = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.blue.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("billing.payment.add".localized)
            }

            if viewModel.paymentMethods.isEmpty {
                emptyInline(message: "billing.payment.empty".localized)
            } else {
                ForEach(viewModel.paymentMethods) { method in
                    paymentMethodRow(method)
                }
            }

            Divider()
                .background(SpectRoomTheme.subtleBorder(for: colorScheme))

            walletPayRow(
                title: "billing.wallet.apple".localized,
                systemImage: "apple.logo",
                isOn: Binding(
                    get: { viewModel.applePayEnabled },
                    set: { newValue in Task { await viewModel.toggleApplePay(newValue) } }
                )
            )

            walletPayRow(
                title: "billing.wallet.google".localized,
                systemImage: "g.circle.fill",
                isOn: Binding(
                    get: { viewModel.googlePayEnabled },
                    set: { newValue in Task { await viewModel.toggleGooglePay(newValue) } }
                )
            )
        }
        .billingCardStyle()
    }

    private func paymentMethodRow(_ method: PaymentMethod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: method.brand?.systemImage ?? "creditcard.fill")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.1)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(method.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                    if method.isDefault {
                        Text("billing.badge.default".localized)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundColor(.green)
                    }
                }
                Text(method.maskedNumber)
                    .font(.caption.monospaced())
                    .foregroundColor(SpectRoomTheme.secondaryText)
                if let exp = method.expirationDisplay {
                    Text(String(format: "billing.card.expires".localized, exp))
                        .font(.caption2)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
            }

            Spacer()

            Menu {
                Button("common.edit".localized) {
                    viewModel.beginEditingCard(method)
                }
                if !method.isDefault {
                    Button("billing.payment.set.default".localized) {
                        Task { await viewModel.setDefault(method) }
                    }
                }
                Button("common.delete".localized, role: .destructive) {
                    viewModel.requestDeletePaymentMethod(method)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpectRoomTheme.background)
        )
    }

    private func walletPayRow(title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.1)))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(SpectRoomTheme.text)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.blue)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpectRoomTheme.background)
        )
    }

    // MARK: D. Invoices / billing history

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

    // MARK: Sheets

    private func planChangeSheet(_ plan: SubscriptionPlan) -> some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.actionTitle(for: plan))
                    .font(.title2.weight(.bold))
                    .foregroundColor(SpectRoomTheme.text)

                Text(String(format: "billing.modal.switching.to".localized, plan.tier.displayNameKey.localized))
                    .foregroundColor(SpectRoomTheme.secondaryText)

                Text(viewModel.prorationSummary(for: plan))
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.08))
                    )

                Spacer()

                Button {
                    Task { await viewModel.confirmPlanChange() }
                } label: {
                    HStack {
                        if viewModel.isBusy { ProgressView().tint(.white) }
                        Text("billing.modal.confirm".localized)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue))
                }
                .disabled(viewModel.isBusy)
            }
            .padding(20)
            .background(SpectRoomBackground())
            .navigationTitle("billing.modal.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) { viewModel.pendingPlanChange = nil }
                }
            }
        }
    }

    private var addCardSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    addCardField(
                        title: "billing.add.card.card.name".localized,
                        error: cardFieldError(
                            show: !viewModel.newCard.isCardNameValid,
                            message: "billing.add.card.card.name.invalid".localized
                        )
                    ) {
                        TextField("billing.add.card.card.name".localized, text: $viewModel.newCard.cardName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onChange(of: viewModel.newCard.cardName) { _, newValue in
                                let trimmedLimit = String(newValue.prefix(40))
                                if trimmedLimit != newValue {
                                    viewModel.newCard.cardName = trimmedLimit
                                }
                            }
                    }

                    addCardField(
                        title: "billing.add.card.name".localized,
                        error: cardFieldError(
                            show: !(viewModel.isEditingCard && viewModel.newCard.cardholderName.isEmpty)
                                && !viewModel.newCard.isCardholderNameValid,
                            message: "billing.add.card.name.invalid".localized
                        )
                    ) {
                        TextField("billing.add.card.name".localized, text: $viewModel.newCard.cardholderName)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onChange(of: viewModel.newCard.cardholderName) { _, newValue in
                                let filtered = String(newValue.filter { $0.isLetter || $0.isWhitespace })
                                if filtered != newValue {
                                    viewModel.newCard.cardholderName = filtered
                                }
                            }
                    }

                    addCardField(
                        title: "billing.add.card.number".localized,
                        error: cardFieldError(
                            show: !viewModel.cardNumberIsMasked
                                && !(viewModel.isEditingCard && viewModel.newCard.cardNumber.isEmpty)
                                && !viewModel.newCard.isCardNumberLengthValid,
                            message: "billing.add.card.number.invalid".localized
                        ),
                        hint: viewModel.isEditingCard
                            && !viewModel.cardNumberIsMasked
                            && viewModel.newCard.cardNumber.isEmpty
                            ? "billing.edit.card.number.hint".localized
                            : nil
                    ) {
                        TextField(
                            viewModel.isEditingCard && !viewModel.cardNumberIsMasked
                                ? "billing.edit.card.number.placeholder".localized
                                : "0000 0000 0000 0000",
                            text: $viewModel.newCard.cardNumber
                        )
                        .keyboardType(.numberPad)
                        .textContentType(.creditCardNumber)
                        .focused($cardFormFocus, equals: .cardNumber)
                        .onChange(of: cardFormFocus) { _, newValue in
                            if newValue == .cardNumber {
                                viewModel.clearMaskedCardNumberIfNeeded()
                            }
                        }
                        .onChange(of: viewModel.newCard.cardNumber) { _, newValue in
                            guard !viewModel.cardNumberIsMasked else { return }
                            let formatted = NewCardDraft.formatCardNumber(newValue)
                            if formatted != newValue {
                                viewModel.newCard.cardNumber = formatted
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        addCardField(
                            title: "billing.add.card.expiry".localized,
                            error: cardFieldError(
                                show: !viewModel.newCard.isExpiryValid,
                                message: "billing.add.card.expiry.invalid".localized
                            )
                        ) {
                            TextField("MM/YY", text: $viewModel.newCard.expiration)
                                .keyboardType(.numberPad)
                                .textContentType(.creditCardExpiration)
                                .onChange(of: viewModel.newCard.expiration) { _, newValue in
                                    let formatted = NewCardDraft.formatExpiration(newValue)
                                    if formatted != newValue {
                                        viewModel.newCard.expiration = formatted
                                    }
                                }
                        }

                        addCardField(
                            title: "billing.add.card.cvc".localized,
                            error: cardFieldError(
                                show: !viewModel.cvcIsMasked
                                    && !(viewModel.isEditingCard && viewModel.newCard.cvc.isEmpty)
                                    && !viewModel.newCard.isCVCValid,
                                message: "billing.add.card.cvc.invalid".localized
                            ),
                            titleAccessory: {
                                Button {
                                    showingCVCHelp = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("billing.add.card.cvc.help.a11y".localized)
                            }
                        ) {
                            TextField("billing.add.card.cvc".localized, text: $viewModel.newCard.cvc)
                                .keyboardType(.numberPad)
                                .textContentType(.creditCardSecurityCode)
                                .focused($cardFormFocus, equals: .cvc)
                                .onChange(of: cardFormFocus) { _, newValue in
                                    if newValue == .cvc {
                                        viewModel.clearMaskedCVCIfNeeded()
                                    }
                                }
                                .onChange(of: viewModel.newCard.cvc) { _, newValue in
                                    guard !viewModel.cvcIsMasked else { return }
                                    let filtered = String(newValue.filter(\.isNumber).prefix(3))
                                    if filtered != newValue {
                                        viewModel.newCard.cvc = filtered
                                    }
                                }
                        }
                    }

                    addCardField(
                        title: "billing.add.card.postal".localized,
                        error: cardFieldError(
                            show: !(viewModel.isEditingCard && viewModel.newCard.postalCode.isEmpty)
                                && !viewModel.newCard.isPostalCodeValid,
                            message: "billing.add.card.postal.invalid".localized
                        )
                    ) {
                        TextField("billing.add.card.postal".localized, text: $viewModel.newCard.postalCode)
                            .keyboardType(.asciiCapable)
                            .textContentType(.postalCode)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: viewModel.newCard.postalCode) { _, newValue in
                                let filtered = String(
                                    newValue
                                        .filter { $0.isNumber || $0 == " " }
                                        .prefix(6)
                                )
                                // Keep at most 5 digits inside the 6-character limit.
                                var digitsSeen = 0
                                let limited = filtered.filter { char in
                                    if char.isNumber {
                                        digitsSeen += 1
                                        return digitsSeen <= 5
                                    }
                                    return true
                                }
                                let result = String(limited.prefix(6))
                                if result != newValue {
                                    viewModel.newCard.postalCode = result
                                }
                            }
                    }
                }
                .padding(16)
            }
            .background(SpectRoomBackground())
            .navigationTitle(
                (viewModel.isEditingCard
                    ? "billing.edit.card.title"
                    : "billing.add.card.title").localized
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        cardFormFocus = nil
                        viewModel.dismissCardForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save".localized) {
                        Task { await viewModel.saveCardForm() }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .sheet(isPresented: $showingCVCHelp) {
                cvcHelpSheet
            }
        }
    }

    private var cvcHelpSheet: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Text("billing.add.card.cvc.help.title".localized)
                .font(.headline)
                .foregroundColor(SpectRoomTheme.text)

            Text("billing.add.card.cvc.help.message".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Image("CVC")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                .accessibilityLabel("billing.add.card.cvc.help.image.a11y".localized)

            Button("common.close".localized) {
                showingCVCHelp = false
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.blue))
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SpectRoomBackground())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }

    private func cardFieldError(show: Bool, message: String) -> String? {
        guard viewModel.didAttemptCardSave, show else { return nil }
        return message
    }

    private func addCardField<Content: View>(
        title: String,
        error: String? = nil,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        addCardField(
            title: title,
            error: error,
            hint: hint,
            titleAccessory: { EmptyView() },
            content: content
        )
    }

    private func addCardField<Content: View, Accessory: View>(
        title: String,
        error: String? = nil,
        hint: String? = nil,
        @ViewBuilder titleAccessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                titleAccessory()
                Spacer(minLength: 0)
            }
            content()
                .foregroundColor(SpectRoomTheme.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SpectRoomTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            error != nil
                                ? Color.red.opacity(0.55)
                                : SpectRoomTheme.subtleBorder(for: colorScheme),
                            lineWidth: 1
                        )
                )
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundColor(SpectRoomTheme.text)
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
                ForEach(0..<4, id: \.self) { _ in
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
