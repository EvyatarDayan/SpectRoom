import SwiftUI
import FirebaseAuth

struct MfaVerificationView: View {
    private enum PhoneFocus: Hashable {
        case national
    }

    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme

    let kind: MfaFlowKind

    @State private var code = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isBusy = false
    @State private var emailVerified = false
    @State private var smsSent = false
    @State private var smsSendFailed = false
    @State private var resendSecondsRemaining = 0
    @State private var phoneE164: String = ""
    @State private var phoneCountry = PhoneCountry.default
    @State private var phoneNational = ""
    @State private var resendTimer: Timer?
    @FocusState private var phoneFocus: PhoneFocus?

    private var maskedPhone: String {
        if kind == .signIn {
            return appState.mfaSignInMaskedPhone
        }
        let value = phoneE164.isEmpty ? appState.pendingMfaPhoneE164 : phoneE164
        return value.isEmpty ? "auth.mfa.phone.fallback".localized : PhoneNumberE164.maskedDisplay(value)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("auth.mfa.title".localized)
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.center)

                    Text(subtitleText)
                        .font(.body)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal)

                if kind == .enroll && !phoneE164.isEmpty {
                    Text(String(format: "auth.mfa.phone.using".localized, maskedPhone))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(SpectRoomTheme.text)
                        .padding(.horizontal)
                }

                if kind == .enroll && phoneE164.isEmpty {
                    phoneMissingCard
                } else if kind == .enroll && !emailVerified {
                    emailVerificationCard
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
                        appState.signOut(forceShowOnboarding: true)
                    } label: {
                        Text("auth.mfa.sign.out".localized)
                            .font(.subheadline)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                    .disabled(isBusy)
                    .padding(.bottom, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .spectRoomScreenBackground()
        .alert(isPresented: $showingError) {
            Alert(
                title: Text("auth.error".localized),
                message: Text(errorMessage),
                dismissButton: .default(Text("auth.ok".localized))
            )
        }
        .onAppear {
            Task { await prepareOnAppear() }
        }
        .onDisappear {
            resendTimer?.invalidate()
            resendTimer = nil
        }
    }

    private var subtitleText: String {
        if kind == .enroll && phoneE164.isEmpty {
            return "auth.mfa.phone.missing.title".localized
        }
        if kind == .enroll && !emailVerified {
            return "auth.mfa.email.subtitle".localized
        }
        if kind == .enroll && smsSendFailed {
            return "auth.mfa.sending.failed.subtitle".localized
        }
        if kind == .enroll && !smsSent {
            return "auth.mfa.sending.subtitle".localized
        }
        return String(format: "auth.mfa.code.subtitle".localized, maskedPhone)
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
            Text(String(format: "auth.mfa.error.sms.detail".localized, phoneE164.isEmpty ? maskedPhone : phoneE164))
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
        }
    }

    private var emailVerificationCard: some View {
        VStack(spacing: 16) {
            Text("auth.mfa.email.body".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                Task { await resendVerificationEmail() }
            } label: {
                Text("auth.mfa.email.resend".localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            }
            .disabled(isBusy)

            Button {
                Task { await checkEmailAndStartSms() }
            } label: {
                loadingLabel(title: "auth.mfa.email.continue".localized)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isBusy ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isBusy)
            .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    private var otpCard: some View {
        VStack(spacing: 16) {
            TextField("auth.mfa.code.placeholder".localized, text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
                .onChange(of: code) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits.count > 6 {
                        code = String(digits.prefix(6))
                    } else if digits != newValue {
                        code = digits
                    }
                }

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

            if resendSecondsRemaining > 0 {
                Text(String(format: "auth.mfa.resend.cooldown".localized, resendSecondsRemaining))
                    .font(.footnote)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            } else {
                Button {
                    Task { await resendSms() }
                } label: {
                    Text("auth.mfa.resend".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                }
                .disabled(isBusy)
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
                .padding(.top, 8)
            }
        }
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
            smsSent = true
            startResendCooldown()
            return
        }

        await resolveEnrollmentPhone()

        do {
            let verified = try await appState.authService.reloadAndIsEmailVerified()
            await MainActor.run { emailVerified = verified }
            // Stay on email step until the user taps "I've verified my email".
        } catch {
            present(error)
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

    private func resendVerificationEmail() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await appState.authService.sendEmailVerificationForMfa()
            await MainActor.run {
                errorMessage = "auth.mfa.email.sent".localized
                showingError = true
            }
        } catch {
            present(error)
        }
    }

    private func checkEmailAndStartSms() async {
        isBusy = true
        defer { isBusy = false }
        do {
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
            let verified = try await appState.authService.reloadAndIsEmailVerified()
            await MainActor.run { emailVerified = verified }
            guard verified else {
                await MainActor.run {
                    errorMessage = "auth.mfa.error.email.unverified".localized
                    showingError = true
                }
                return
            }
            await startEnrollmentSmsIfNeeded(force: true)
        } catch {
            present(error)
        }
    }

    private func startEnrollmentSmsIfNeeded(force: Bool = false) async {
        guard kind == .enroll else { return }
        guard !phoneE164.isEmpty else {
            await MainActor.run {
                errorMessage = "auth.error.phone.invalid".localized
                showingError = true
            }
            return
        }
        if smsSent && !force { return }

        isBusy = true
        defer { isBusy = false }
        do {
            await MainActor.run { smsSendFailed = false }
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
            try await appState.authService.startMfaEnrollment(phoneE164: phoneE164)
            await MainActor.run {
                smsSent = true
                smsSendFailed = false
                startResendCooldown()
            }
        } catch {
            await MainActor.run {
                smsSent = false
                smsSendFailed = true
            }
            if let authError = error as? SpectRoomAuthError,
               case .emailNotVerifiedForMfa = authError {
                await MainActor.run {
                    emailVerified = false
                    smsSendFailed = false
                }
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
        } catch {
            present(error)
        }
    }

    private func resendSms() async {
        isBusy = true
        defer { isBusy = false }
        do {
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
            if kind == .signIn {
                try await appState.authService.resendSignInMfaCode()
            } else {
                try await appState.authService.resendMfaEnrollmentCode(phoneE164: phoneE164)
            }
            await MainActor.run { startResendCooldown() }
        } catch {
            present(error)
        }
    }

    private func startResendCooldown() {
        resendTimer?.invalidate()
        resendSecondsRemaining = 45
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.main.async {
                if resendSecondsRemaining <= 1 {
                    resendSecondsRemaining = 0
                    timer.invalidate()
                } else {
                    resendSecondsRemaining -= 1
                }
            }
        }
    }

    private func present(_ error: Error) {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let ns = error as NSError
        print("❌ MFA error domain=\(ns.domain) code=\(ns.code) \(raw)")
        if raw.localizedCaseInsensitiveContains("canHandleNotification")
            || raw.localizedCaseInsensitiveContains("app delegate swizzling") {
            errorMessage = String(
                format: "auth.mfa.error.sms.detail".localized,
                phoneE164.isEmpty ? maskedPhone : phoneE164
            )
        } else {
            errorMessage = raw
        }
        showingError = true
    }
}
