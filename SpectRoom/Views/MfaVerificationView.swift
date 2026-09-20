import SwiftUI
import FirebaseAuth

struct MfaVerificationView: View {
    private enum PhoneFocus: Hashable {
        case national
    }

    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    let kind: MfaFlowKind

    @State private var code = ""
    @State private var errorMessage = ""
    @State private var alertTitle = ""
    @State private var showingError = false
    @State private var isBusy = false
    @State private var emailVerified = false
    @State private var showEmailVerifiedCelebration = false
    @State private var isHandlingEmailVerified = false
    @State private var smsSent = false
    @State private var smsSendFailed = false
    @State private var smsRateLimited = false
    @State private var isEditingPhone = false
    @State private var lastSmsResendAt: Date?
    @State private var smsResendToast = ""
    @State private var smsResendToastTask: Task<Void, Never>?
    @State private var emailResendSecondsRemaining = 0
    @State private var phoneE164: String = ""
    @State private var phoneCountry = PhoneCountry.default
    @State private var phoneNational = ""
    @State private var emailResendTimer: Timer?
    @State private var emailPollTask: Task<Void, Never>?
    @State private var emailIconPulse = false
    @FocusState private var phoneFocus: PhoneFocus?
    @FocusState private var isCodeFieldFocused: Bool

    private let smsResendCooldownSeconds: TimeInterval = 45

    private var maskedPhone: String {
        if kind == .signIn {
            return appState.mfaSignInMaskedPhone
        }
        let value = phoneE164.isEmpty ? appState.pendingMfaPhoneE164 : phoneE164
        return value.isEmpty ? "auth.mfa.phone.fallback".localized : value
    }

    private var displayedPhone: String {
        if kind == .enroll {
            let value = phoneE164.isEmpty ? appState.pendingMfaPhoneE164 : phoneE164
            if !value.isEmpty { return value }
        }
        return maskedPhone
    }

    private var verificationEmail: String {
        appState.authService.currentUser?.email
            ?? Auth.auth().currentUser?.email
            ?? ""
    }

    private var isWaitingForEmail: Bool {
        kind == .enroll && !phoneE164.isEmpty && !emailVerified && !showEmailVerifiedCelebration
    }

    private var isOnOtpStep: Bool {
        if kind == .signIn { return true }
        return emailVerified
            && !showEmailVerifiedCelebration
            && !phoneE164.isEmpty
            && !isEditingPhone
            && (smsSent || smsSendFailed)
    }

    private var headerTitle: String {
        if isWaitingForEmail || showEmailVerifiedCelebration {
            return "auth.mfa.email.title".localized
        }
        if isOnOtpStep && !smsSendFailed {
            return "auth.mfa.code.title".localized
        }
        if kind == .enroll && isEditingPhone {
            return "auth.mfa.phone.edit.title".localized
        }
        return "auth.mfa.title".localized
    }

    /// Lock asset under the security titles (not on the email-verify step, which has its own icon).
    private var showsSecurityLockIcon: Bool {
        !isWaitingForEmail && !showEmailVerifiedCelebration
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text(headerTitle)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.center)

                    if showsSecurityLockIcon {
                        Image("lock")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                            .accessibilityHidden(true)
                    }

                    if !subtitleText.isEmpty {
                        Text(subtitleText)
                            .font(.body)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal)

                if kind == .enroll && phoneE164.isEmpty {
                    phoneMissingCard
                } else if kind == .enroll && showEmailVerifiedCelebration {
                    emailVerifiedCelebration
                } else if kind == .enroll && !emailVerified {
                    emailVerificationCard
                } else if kind == .enroll && isEditingPhone {
                    editPhoneCard
                } else if kind == .enroll && smsSendFailed {
                    smsFailedCard
                } else if kind == .enroll && !smsSent {
                    sendingSmsCard
                } else {
                    otpCard
                }

                Spacer(minLength: 24)

                if kind == .enroll {
                    Button {
                        stopEmailVerificationPolling()
                        appState.signOut(forceShowOnboarding: true)
                    } label: {
                        Text("auth.mfa.sign.out".localized)
                            .font(.subheadline)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                    .disabled(isBusy || showEmailVerifiedCelebration)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .authFlowPreferenceControls()
        .spectRoomScreenBackground()
        .overlay {
            if showingError {
                SpectRoomNoticePopup(
                    title: alertTitle,
                    message: errorMessage,
                    onDismiss: { showingError = false }
                )
            }
        }
        .onAppear {
            Task { await prepareOnAppear() }
        }
        .onDisappear {
            emailResendTimer?.invalidate()
            emailResendTimer = nil
            smsResendToastTask?.cancel()
            smsResendToastTask = nil
            stopEmailVerificationPolling()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isWaitingForEmail else { return }
            Task { await checkEmailVerifiedQuietly() }
        }
    }

    private var subtitleText: String {
        if kind == .enroll && phoneE164.isEmpty {
            return "auth.mfa.phone.missing.title".localized
        }
        if kind == .enroll && (isWaitingForEmail || showEmailVerifiedCelebration) {
            return ""
        }
        if kind == .enroll && isEditingPhone {
            return "auth.mfa.phone.edit.subtitle".localized
        }
        if kind == .enroll && smsSendFailed {
            return smsRateLimited
                ? "auth.mfa.error.rate.limited.subtitle".localized
                : "auth.mfa.sending.failed.subtitle".localized
        }
        if kind == .enroll && !smsSent {
            return "auth.mfa.sending.subtitle".localized
        }
        // OTP step carries its own copy inside the card.
        return ""
    }

    private var sendingSmsCard: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("auth.mfa.sending.body".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var smsFailedCard: some View {
        VStack(spacing: 16) {
            if smsRateLimited {
                Text("auth.mfa.error.rate.limited".localized)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text(smsFailureDetailText)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button {
                    Task { await startEnrollmentSmsIfNeeded(force: true) }
                } label: {
                    loadingLabel(title: "auth.mfa.resend".localized)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isBusy ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isBusy)
                .padding(.horizontal)
            }
        }
    }

    private var smsFailureDetailText: String {
        String(format: "auth.mfa.error.sms.unavailable".localized, displayedPhoneNumber)
    }

    private var displayedPhoneNumber: String {
        phoneE164.isEmpty ? maskedPhone : phoneE164
    }

    private var phoneMissingCard: some View {
        VStack(spacing: 16) {
            PhoneNumberInputView(
                country: $phoneCountry,
                nationalNumber: $phoneNational,
                isFocused: $phoneFocus,
                focusValue: .national
            )
            .padding(.horizontal)

            Text("auth.phone.helper".localized)
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .padding(.horizontal)

            Button {
                saveMissingPhone()
            } label: {
                loadingLabel(title: "auth.mfa.phone.missing.save".localized)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isBusy)
            .padding(.horizontal)
        }
    }

    private func saveMissingPhone() {
        guard let e164 = PhoneNumberE164.build(country: phoneCountry, nationalNumber: phoneNational) else {
            alertTitle = "auth.notice".localized
            errorMessage = "auth.error.phone.invalid".localized
            showingError = true
            return
        }
        phoneE164 = e164
        appState.pendingMfaPhoneE164 = e164
        Task {
            try? await appState.authService.updateUserData([
                "phoneE164": e164,
                "mfaEnrolled": false
            ])
            await MainActor.run {
                startEmailResendCooldown()
                startEmailVerificationPolling()
            }
        }
    }

    private var emailVerificationCard: some View {
        VStack(spacing: 22) {
            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.blue.gradient)
                .scaleEffect(emailIconPulse ? 1.08 : 0.96)
                .opacity(emailIconPulse ? 1.0 : 0.82)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                        emailIconPulse = true
                    }
                }

            Text(emailWaitingBodyText)
                .font(.body)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                Task { await checkEmailAndStartSms(manual: true) }
            } label: {
                loadingLabel(title: "auth.mfa.email.check".localized)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isBusy ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isBusy)
            .padding(.horizontal)

            if emailResendSecondsRemaining > 0 {
                VStack(spacing: 4) {
                    Text("auth.mfa.email.resend".localized)
                        .font(.subheadline.weight(.semibold))
                    Text("auth.mfa.email.resend.wait.hint".localized)
                        .font(.footnote)
                }
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
            } else {
                Button {
                    Task { await resendVerificationEmail() }
                } label: {
                    Text("auth.mfa.email.resend".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                }
                .disabled(isBusy)
            }
        }
        .padding(.horizontal)
    }

    private var emailWaitingBodyText: String {
        let email = verificationEmail.isEmpty ? "auth.mfa.email.fallback".localized : verificationEmail
        return String(format: "auth.mfa.email.body".localized, email)
    }

    private var emailVerifiedCelebration: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundColor(.green)
                .transition(.scale.combined(with: .opacity))

            Text("auth.mfa.email.verified".localized)
                .font(.title2.weight(.bold))
                .foregroundColor(SpectRoomTheme.text)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
        .padding(.horizontal)
    }

    private var editPhoneCard: some View {
        VStack(spacing: 16) {
            PhoneNumberInputView(
                country: $phoneCountry,
                nationalNumber: $phoneNational,
                isFocused: $phoneFocus,
                focusValue: .national
            )
            .padding(.horizontal)

            Text("auth.phone.helper".localized)
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                saveEditedPhone()
            } label: {
                loadingLabel(title: "auth.mfa.phone.edit.save".localized)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isBusy)
            .padding(.horizontal)

            Button {
                isEditingPhone = false
            } label: {
                Text("auth.mfa.phone.edit.cancel".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
            .disabled(isBusy)
        }
    }

    private func saveEditedPhone() {
        guard let e164 = PhoneNumberE164.build(country: phoneCountry, nationalNumber: phoneNational) else {
            alertTitle = "auth.notice".localized
            errorMessage = "auth.error.phone.invalid".localized
            showingError = true
            return
        }
        phoneE164 = e164
        appState.pendingMfaPhoneE164 = e164
        UserDefaults.standard.set(e164, forKey: "pendingMfaPhoneE164")
        code = ""
        isEditingPhone = false
        smsSent = false
        smsSendFailed = false
        Task {
            try? await appState.authService.updateUserData([
                "phoneE164": e164,
                "mfaEnrolled": false
            ])
            await startEnrollmentSmsIfNeeded(force: true)
        }
    }

    private var otpCard: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(
                    (kind == .signIn && !appState.authService.hasPendingSignInMfaVerificationID && !smsSent)
                        ? "auth.mfa.code.request.to".localized
                        : "auth.mfa.code.sent.to".localized
                )
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Text(displayedPhone)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)

                if kind == .enroll {
                    Button {
                        applyPhoneFields(from: phoneE164)
                        isEditingPhone = true
                        isCodeFieldFocused = false
                    } label: {
                        Text("auth.mfa.edit.number".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.blue)
                    }
                    .disabled(isBusy)
                }
            }
            .padding(.horizontal)

            otpDigitBoxes
                .padding(.horizontal, 20)

            Button {
                Task { await confirmCode() }
            } label: {
                loadingLabel(title: "auth.mfa.verify".localized)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isBusy || code.count < 6 ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isBusy || code.count < 6)
            .padding(.horizontal)

            Button {
                attemptResendSms()
            } label: {
                Text("auth.mfa.resend.link".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            }
            .disabled(isBusy)

            if !smsResendToast.isEmpty {
                Text(smsResendToast)
                    .font(.footnote)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .transition(.opacity)
            }

            if kind == .signIn {
                Button {
                    appState.cancelMfaSignIn()
                } label: {
                    Text("auth.mfa.back.to.sign.in".localized)
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                .disabled(isBusy)
                .padding(.top, 4)
            }
        }
        .onAppear {
            isCodeFieldFocused = true
        }
    }

    private var otpDigitBoxes: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCodeFieldFocused)
                .opacity(0.02)
                .frame(height: 56)
                .onChange(of: code) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    let trimmed = String(digits.prefix(6))
                    if trimmed != newValue {
                        code = trimmed
                    }
                }

            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    let digit = digit(at: index)
                    Text(digit.isEmpty ? " " : digit)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    code.count == index && isCodeFieldFocused
                                        ? Color.blue
                                        : Color.gray.opacity(0.3),
                                    lineWidth: code.count == index && isCodeFieldFocused ? 2 : 1
                                )
                        )
                        .cornerRadius(12)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isCodeFieldFocused = true
        }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let i = code.index(code.startIndex, offsetBy: index)
        return String(code[i])
    }

    @ViewBuilder
    private func loadingLabel(title: String) -> some View {
        HStack {
            if isBusy {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
            Text(title)
                .font(.headline)
        }
    }

    // MARK: - Actions

    private func prepareOnAppear() async {
        FirebaseBootstrap.applyDebugPhoneAuthSettings()

        if kind == .signIn {
            emailVerified = true
            if appState.authService.hasPendingSignInMfaVerificationID {
                smsSent = true
                markSmsResendCooldownStarted()
            } else {
                // Initial SMS often fails on Simulator — retry quietly; show toast, not a popup.
                smsSent = false
                await resendSms(showErrorsAsToast: true)
            }
            return
        }

        await resolveEnrollmentPhone()

        do {
            let verified = try await appState.authService.reloadAndIsEmailVerified()
            if verified {
                await MainActor.run { emailVerified = true }
                await startEnrollmentSmsIfNeeded(force: true)
            } else {
                await MainActor.run {
                    emailVerified = false
                    startEmailResendCooldown()
                    startEmailVerificationPolling()
                }
            }
        } catch {
            present(error)
            await MainActor.run {
                startEmailResendCooldown()
                startEmailVerificationPolling()
            }
        }
    }

    /// Prefer in-memory signup phone, then UserDefaults, then Firestore.
    private func resolveEnrollmentPhone() async {
        var resolved = appState.pendingMfaPhoneE164.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolved.isEmpty {
            resolved = (UserDefaults.standard.string(forKey: "pendingMfaPhoneE164") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if resolved.isEmpty {
            resolved = (await appState.authService.fetchStoredPhoneE164() ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Brief retry — auth can open MFA before the signup stub write finishes.
        if resolved.isEmpty {
            try? await Task.sleep(nanoseconds: 400_000_000)
            resolved = (await appState.authService.fetchStoredPhoneE164() ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        await MainActor.run {
            phoneE164 = resolved
            if !resolved.isEmpty {
                appState.pendingMfaPhoneE164 = resolved
                applyPhoneFields(from: resolved)
            }
        }
    }

    private func applyPhoneFields(from e164: String) {
        guard e164.hasPrefix("+") else { return }
        let match = PhoneCountry.all
            .sorted { $0.dialCode.count > $1.dialCode.count }
            .first { e164.hasPrefix($0.dialCode) }
        if let match {
            phoneCountry = match
            phoneNational = String(e164.dropFirst(match.dialCode.count))
        }
    }

    private func startEmailVerificationPolling() {
        stopEmailVerificationPolling()
        emailPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await checkEmailVerifiedQuietly()
            }
        }
    }

    private func stopEmailVerificationPolling() {
        emailPollTask?.cancel()
        emailPollTask = nil
    }

    private func checkEmailVerifiedQuietly() async {
        guard kind == .enroll, !emailVerified, !showEmailVerifiedCelebration, !isHandlingEmailVerified else { return }
        do {
            let verified = try await appState.authService.reloadAndIsEmailVerified()
            guard verified else { return }
            await advanceAfterEmailVerified(showCelebration: true)
        } catch {
            // Quiet polling — ignore transient reload failures.
        }
    }

    private func advanceAfterEmailVerified(showCelebration: Bool) async {
        let shouldProceed = await MainActor.run { () -> Bool in
            guard !isHandlingEmailVerified else { return false }
            isHandlingEmailVerified = true
            stopEmailVerificationPolling()
            return true
        }
        guard shouldProceed else { return }

        if showCelebration {
            await MainActor.run {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    showEmailVerifiedCelebration = true
                }
            }
            try? await Task.sleep(nanoseconds: 1_250_000_000)
        }

        await MainActor.run {
            emailVerified = true
            showEmailVerifiedCelebration = false
            emailResendTimer?.invalidate()
            emailResendTimer = nil
            emailResendSecondsRemaining = 0
        }
        await startEnrollmentSmsIfNeeded(force: true)
        await MainActor.run { isHandlingEmailVerified = false }
    }

    private func resendVerificationEmail() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await appState.authService.sendEmailVerificationForMfa()
            await MainActor.run {
                startEmailResendCooldown()
                alertTitle = "auth.mfa.email.sent.title".localized
                errorMessage = "auth.mfa.email.sent".localized
                showingError = true
            }
        } catch {
            present(error)
        }
    }

    private func checkEmailAndStartSms(manual: Bool) async {
        await MainActor.run { isBusy = true }
        do {
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
            let verified = try await appState.authService.reloadAndIsEmailVerified()
            await MainActor.run { isBusy = false }
            guard verified else {
                if manual {
                    await MainActor.run {
                        alertTitle = ""
                        errorMessage = "auth.mfa.error.email.unverified".localized
                        showingError = true
                    }
                }
                return
            }
            await advanceAfterEmailVerified(showCelebration: true)
        } catch {
            await MainActor.run { isBusy = false }
            present(error)
        }
    }

    private func startEnrollmentSmsIfNeeded(force: Bool = false) async {
        guard kind == .enroll else { return }
        guard !phoneE164.isEmpty else {
            await MainActor.run {
                alertTitle = "auth.notice".localized
                errorMessage = "auth.error.phone.invalid".localized
                showingError = true
            }
            return
        }
        if smsSent && !force { return }

        isBusy = true
        defer { isBusy = false }
        do {
            await MainActor.run {
                smsSendFailed = false
                smsRateLimited = false
            }
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
            #if DEBUG && targetEnvironment(simulator)
            FirebaseBootstrap.prepareSimulatorMfaPhoneVerify()
            #endif
            try await appState.authService.startMfaEnrollment(phoneE164: phoneE164)
            await MainActor.run {
                smsSent = true
                smsSendFailed = false
                smsRateLimited = false
                markSmsResendCooldownStarted()
            }
        } catch {
            let rateLimited = isSmsRateLimited(error)
            #if DEBUG
            let ns = error as NSError
            print("❌ MFA enroll SMS UI failed domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
            #endif
            await MainActor.run {
                smsSent = false
                smsSendFailed = true
                smsRateLimited = rateLimited
            }
            if let authError = error as? SpectRoomAuthError,
               case .emailNotVerifiedForMfa = authError {
                await MainActor.run {
                    emailVerified = false
                    smsSendFailed = false
                    smsRateLimited = false
                    isHandlingEmailVerified = false
                    startEmailVerificationPolling()
                }
            } else if rateLimited {
                // Show on-screen message only — no popup.
            } else if kind == .enroll {
                // smsFailedCard shows the message — no popup.
            } else {
                present(error)
            }
        }
    }

    private func confirmCode() async {
        isBusy = true
        defer { isBusy = false }
        do {
            if kind == .signIn {
                try await appState.confirmMfaSignIn(code: code)
            } else {
                try await appState.confirmMfaEnrollment(code: code, phoneE164: phoneE164)
            }
        } catch let authError as SpectRoomAuthError {
            switch authError {
            case .mfaSendFailed, .mfaSessionExpired
                where kind == .signIn && !appState.authService.hasPendingSignInMfaVerificationID:
                // Prefer a recoverable hint over a dead-end "session expired" popup when SMS never landed.
                showSmsResendToast("auth.mfa.error.send".localized)
            default:
                present(authError)
            }
        } catch {
            present(error)
        }
    }

    private func attemptResendSms() {
        if let last = lastSmsResendAt,
           Date().timeIntervalSince(last) < smsResendCooldownSeconds {
            showSmsResendToast("auth.mfa.resend.wait".localized)
            return
        }
        Task { await resendSms() }
    }

    private func showSmsResendToast(_ message: String) {
        smsResendToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            smsResendToast = message
        }
        smsResendToastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    smsResendToast = ""
                }
            }
        }
    }

    private func resendSms(showErrorsAsToast: Bool = false) async {
        isBusy = true
        defer { isBusy = false }
        do {
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
            if kind == .signIn {
                try await appState.authService.resendSignInMfaCode()
            } else {
                try await appState.authService.resendMfaEnrollmentCode(phoneE164: phoneE164)
            }
            await MainActor.run {
                markSmsResendCooldownStarted()
                code = ""
                smsSent = true
                smsSendFailed = false
                smsRateLimited = false
                showSmsResendToast("auth.mfa.resend.sent".localized)
            }
        } catch {
            if isSmsRateLimited(error) {
                await MainActor.run {
                    smsSent = false
                    smsSendFailed = true
                    smsRateLimited = true
                }
            } else if kind == .enroll {
                await MainActor.run {
                    smsSent = false
                    smsSendFailed = true
                }
            } else if showErrorsAsToast {
                // Avoid "Invalid format." Notice popups on Simulator auto-retry.
                showSmsResendToast("auth.mfa.error.send".localized)
            } else {
                // Manual Resend: keep the OTP screen usable with a clear send message.
                let mapped = (error as? SpectRoomAuthError) ?? error
                let message = (mapped as? SpectRoomAuthError)?.errorDescription
                    ?? FirebaseAuthService.humanReadableFunctionsError(error)
                if message.localizedCaseInsensitiveContains("invalid format")
                    || message.localizedCaseInsensitiveContains("invalid phone") {
                    showSmsResendToast("auth.mfa.error.send".localized)
                } else {
                    present(error)
                }
            }
        }
    }

    private func isSmsRateLimited(_ error: Error) -> Bool {
        if let authError = error as? SpectRoomAuthError, case .mfaRateLimited = authError {
            return true
        }
        let ns = error as NSError
        if ns.domain == AuthErrorDomain, ns.code == AuthErrorCode.tooManyRequests.rawValue {
            return true
        }
        let message = ns.localizedDescription
        return message.localizedCaseInsensitiveContains("unusual activity")
            || message.localizedCaseInsensitiveContains("blocked all requests")
            || message.localizedCaseInsensitiveContains("too many requests")
    }

    private func markSmsResendCooldownStarted() {
        lastSmsResendAt = Date()
    }

    private func startEmailResendCooldown() {
        emailResendTimer?.invalidate()
        emailResendSecondsRemaining = 30
        emailResendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.main.async {
                if emailResendSecondsRemaining <= 1 {
                    emailResendSecondsRemaining = 0
                    timer.invalidate()
                } else {
                    emailResendSecondsRemaining -= 1
                }
            }
        }
    }

    private func present(_ error: Error) {
        if let authError = error as? SpectRoomAuthError, let message = authError.errorDescription {
            switch authError {
            case .invalidMfaCode, .emailNotVerifiedForMfa:
                alertTitle = ""
                errorMessage = message
            case .mfaSendFailed:
                alertTitle = "auth.notice".localized
                errorMessage = smsFailureDetailText
            default:
                alertTitle = "auth.notice".localized
                errorMessage = message
            }
            showingError = true
            return
        }

        let ns = error as NSError
        print("❌ MFA error domain=\(ns.domain) code=\(ns.code) \(error.localizedDescription)")

        if ns.domain == AuthErrorDomain,
           ns.code == AuthErrorCode.invalidVerificationCode.rawValue
            || ns.code == AuthErrorCode.missingVerificationCode.rawValue {
            alertTitle = ""
            errorMessage = "auth.mfa.error.invalid.code".localized
            showingError = true
            return
        }

        alertTitle = "auth.notice".localized

        let raw = FirebaseAuthService.humanReadableFunctionsError(error)
        let isSmsDeliveryIssue =
            raw.localizedCaseInsensitiveContains("canHandleNotification")
            || raw.localizedCaseInsensitiveContains("app delegate swizzling")
            || raw.localizedCaseInsensitiveContains("client identifier")
            || raw.localizedCaseInsensitiveContains("failed to get document from server")
            || raw.localizedCaseInsensitiveContains("firestoreSourceServer")
            || raw.localizedCaseInsensitiveContains("local cache")
            || raw.localizedCaseInsensitiveContains("Phone numbers for testing")
            || raw.localizedCaseInsensitiveContains("reCAPTCHA")
            || raw.localizedCaseInsensitiveContains("APNs")
            || ns.code == AuthErrorCode.notificationNotForwarded.rawValue
            || ns.code == AuthErrorCode.missingClientIdentifier.rawValue

        // Never surface Firebase/DEBUG troubleshooting text in the UI.
        errorMessage = isSmsDeliveryIssue ? smsFailureDetailText : raw
        showingError = true
    }
}
