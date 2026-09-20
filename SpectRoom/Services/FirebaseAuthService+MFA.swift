import Foundation
@preconcurrency import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

// MARK: - MFA types

enum AuthSignInOutcome {
    case completed
    case mfaRequired(maskedPhone: String)
}

enum ReauthOutcome {
    case completed
    case mfaRequired(maskedPhone: String)
}

enum MfaFlowKind: Equatable {
    case enroll
    case signIn
}

extension FirebaseAuthService {
    private static let phoneE164Key = "phoneE164"
    private static let phoneVerifiedAtKey = "phoneVerifiedAt"
    private static let mfaEnrolledKey = "mfaEnrolled"

    /// In-memory MFA challenge (resolver cannot be persisted).
    private static var pendingSignInResolver: MultiFactorResolver?
    private static var pendingVerificationID: String?
    private static var pendingEnrollPhoneE164: String?
    private static var pendingReauthResolver: MultiFactorResolver?
    private static var pendingReauthVerificationID: String?

    var isMfaEnrolled: Bool {
        guard let factors = auth.currentUser?.multiFactor.enrolledFactors else { return false }
        return !factors.isEmpty
    }

    // MARK: - Sign-in MFA

    /// Email/password sign-in that surfaces an SMS MFA challenge when required.
    func signInWithPossibleMfa(email: String, password: String) async throws -> AuthSignInOutcome {
        await MainActor.run {
            self.isVerifyingSignIn = true
            self.hasResolvedUserProfile = false
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            // Soft-deleted / admin-deleted accounts can still have Auth+MFA until hard wipe.
            // Block before password/MFA so deleted users never reach the Security Code screen.
            try await throwIfEmailBlockedFromSignIn(normalizedEmail)

            _ = try await auth.signIn(withEmail: email, password: password)
            try await finishVerifiedSignInChecks()
            return .completed
        } catch {
            if error is SpectRoomAuthError {
                await MainActor.run {
                    self.isVerifyingSignIn = false
                    if self.auth.currentUser == nil {
                        self.isAuthenticated = false
                    }
                }
                throw error
            }

            if let resolver = Self.multiFactorResolver(from: error) {
                // Password was correct but MFA is required — re-check deletion before sending SMS.
                do {
                    try await throwIfEmailBlockedFromSignIn(normalizedEmail)
                } catch {
                    Self.clearPendingMfaSignIn()
                    await MainActor.run {
                        self.isVerifyingSignIn = false
                        self.isAuthenticated = false
                    }
                    throw error
                }

                Self.pendingSignInResolver = resolver
                let hint = resolver.hints.compactMap { $0 as? PhoneMultiFactorInfo }.first
                let masked = Self.maskedPhone(for: hint)

                // Always open the security-code screen when the password is correct.
                // SMS may fail on Simulator (APNs/app verification) — the MFA UI can Resend.
                do {
                    let verificationID = try await sendSignInMfaCode(resolver: resolver, hint: hint)
                    Self.pendingVerificationID = verificationID
                } catch {
                    print("⚠️ Initial sign-in MFA SMS failed (continuing to code screen): \(error.localizedDescription)")
                    Self.pendingVerificationID = nil
                }

                await MainActor.run {
                    self.isVerifyingSignIn = false
                }
                return .mfaRequired(maskedPhone: masked)
            }

            await MainActor.run {
                self.isVerifyingSignIn = false
                if self.auth.currentUser == nil {
                    self.isAuthenticated = false
                }
            }
            throw error
        }
    }

    func resendSignInMfaCode() async throws {
        guard let resolver = Self.pendingSignInResolver else {
            throw SpectRoomAuthError.mfaSessionExpired
        }
        let hint = resolver.hints.compactMap { $0 as? PhoneMultiFactorInfo }.first
        let verificationID = try await sendSignInMfaCode(resolver: resolver, hint: hint)
        Self.pendingVerificationID = verificationID
    }

    /// True when the initial MFA SMS for the pending sign-in challenge succeeded.
    var hasPendingSignInMfaVerificationID: Bool {
        Self.pendingVerificationID != nil
    }

    func confirmSignInMfa(code: String) async throws {
        guard let resolver = Self.pendingSignInResolver else {
            throw SpectRoomAuthError.mfaSessionExpired
        }
        guard let verificationID = Self.pendingVerificationID else {
            // Password was accepted, but no SMS verification ID exists yet
            // (common on Simulator when APNs/app verification fails).
            throw SpectRoomAuthError.mfaSendFailed
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            throw SpectRoomAuthError.invalidMfaCode
        }

        await MainActor.run {
            self.isVerifyingSignIn = true
        }

        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: trimmed
            )
            let assertion = PhoneMultiFactorGenerator.assertion(with: credential)
            _ = try await resolver.resolveSignIn(with: assertion)

            Self.clearPendingMfaSignIn()
            // Drop restore handoff before UI reacts to the new session (prevents restore↔login loop).
            markRestoredNoticeDismissed()
            await clearPendingAccountRestoredNoticeIfNeeded()
            try await finishVerifiedSignInChecks()
        } catch {
            await MainActor.run {
                self.isVerifyingSignIn = false
            }
            throw mapMfaError(error)
        }
    }

    func cancelPendingMfaSignIn() {
        Self.clearPendingMfaSignIn()
        if auth.currentUser == nil {
            Task { @MainActor in
                self.isAuthenticated = false
            }
        }
    }

    // MARK: - Reauthentication MFA (sensitive actions, e.g. delete account)

    /// Password reauth that surfaces SMS MFA when the account has a second factor.
    func reauthenticateWithPossibleMfa(password: String) async throws -> ReauthOutcome {
        guard let user = auth.currentUser, let email = user.email else {
            throw SpectRoomAuthError.notAuthenticated
        }

        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpectRoomAuthError.wrongPassword
        }

        let credential = EmailAuthProvider.credential(withEmail: email, password: trimmed)
        do {
            try await user.reauthenticate(with: credential)
            Self.clearPendingMfaReauth()
            return .completed
        } catch {
            if let resolver = Self.multiFactorResolver(from: error) {
                Self.pendingReauthResolver = resolver
                let hint = resolver.hints.compactMap { $0 as? PhoneMultiFactorInfo }.first
                let masked = Self.maskedPhone(for: hint)

                do {
                    let verificationID = try await sendSignInMfaCode(resolver: resolver, hint: hint)
                    Self.pendingReauthVerificationID = verificationID
                } catch {
                    print("⚠️ Reauth MFA SMS failed (continuing to code step): \(error.localizedDescription)")
                    Self.pendingReauthVerificationID = nil
                }
                return .mfaRequired(maskedPhone: masked)
            }

            print("⚠️ Reauthentication failed: \(error.localizedDescription)")
            throw Self.mapPasswordReauthError(error)
        }
    }

    var hasPendingReauthMfaVerificationID: Bool {
        Self.pendingReauthVerificationID != nil
    }

    func resendReauthMfaCode() async throws {
        guard let resolver = Self.pendingReauthResolver else {
            throw SpectRoomAuthError.mfaSessionExpired
        }
        let hint = resolver.hints.compactMap { $0 as? PhoneMultiFactorInfo }.first
        let verificationID = try await sendSignInMfaCode(resolver: resolver, hint: hint)
        Self.pendingReauthVerificationID = verificationID
    }

    /// Completes MFA after password reauth; does not change session identity beyond refreshing auth.
    func confirmReauthMfa(code: String) async throws {
        guard let resolver = Self.pendingReauthResolver else {
            throw SpectRoomAuthError.mfaSessionExpired
        }
        guard let verificationID = Self.pendingReauthVerificationID else {
            throw SpectRoomAuthError.mfaSendFailed
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            throw SpectRoomAuthError.invalidMfaCode
        }

        do {
            let credential = PhoneAuthProvider.provider().credential(
                withVerificationID: verificationID,
                verificationCode: trimmed
            )
            let assertion = PhoneMultiFactorGenerator.assertion(with: credential)
            _ = try await resolver.resolveSignIn(with: assertion)
            Self.clearPendingMfaReauth()
        } catch {
            throw mapMfaError(error)
        }
    }

    func cancelPendingMfaReauth() {
        Self.clearPendingMfaReauth()
    }

    // MARK: - Enrollment MFA

    func sendEmailVerificationForMfa() async throws {
        guard let user = auth.currentUser else {
            throw SpectRoomAuthError.notAuthenticated
        }
        try await user.reload()
        if user.isEmailVerified { return }

        do {
            try await sendBrandedEmailVerification()
            return
        } catch {
            print("⚠️ Branded verification email failed, using Firebase default: \(FirebaseAuthService.humanReadableFunctionsError(error))")
        }

        try await user.sendEmailVerification()
    }

    func reloadAndIsEmailVerified() async throws -> Bool {
        guard let user = auth.currentUser else {
            throw SpectRoomAuthError.notAuthenticated
        }
        try await user.reload()
        return user.isEmailVerified
    }

    /// Starts SMS enrollment. Requires a verified email (Firebase Identity Platform rule).
    func startMfaEnrollment(phoneE164: String) async throws {
        FirebaseBootstrap.configureIfNeeded()
        FirebaseBootstrap.applyDebugPhoneAuthSettings()
        #if DEBUG && targetEnvironment(simulator)
        SimulatorPhoneAuthSupport.enableForMfaIfNeeded()
        #endif

        guard let user = auth.currentUser else {
            throw SpectRoomAuthError.notAuthenticated
        }

        try await user.reload()
        guard user.isEmailVerified else {
            throw SpectRoomAuthError.emailNotVerifiedForMfa
        }

        #if DEBUG
        #if targetEnvironment(simulator)
        if Auth.auth().settings?.isAppVerificationDisabledForTesting != true {
            print("⚠️ Re-applying phone test mode before MFA enroll")
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
        } else {
            // Re-inject in case an earlier failed probe cached forwarding=false for this process.
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
        }
        #endif
        print("📱 MFA enroll to \(phoneE164), testMode=\(Auth.auth().settings?.isAppVerificationDisabledForTesting ?? false), clientID=\(FirebaseApp.app()?.options.clientID ?? "nil")")
        #endif

        let session = try await getMultiFactorSession(for: user)
        do {
            let verificationID = try await verifyPhoneForEnrollment(phoneE164: phoneE164, session: session)
            Self.pendingVerificationID = verificationID
            Self.pendingEnrollPhoneE164 = phoneE164
            #if DEBUG
            print("✅ MFA enroll SMS verificationID received (\(verificationID.prefix(8))…)")
            #endif
        } catch {
            #if DEBUG
            let ns = error as NSError
            print("❌ MFA enroll SMS failed domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
            #endif
            throw mapMfaError(error)
        }

        try await updateUserData([
            Self.phoneE164Key: phoneE164,
            Self.mfaEnrolledKey: false
        ])
    }

    func resendMfaEnrollmentCode(phoneE164: String) async throws {
        try await startMfaEnrollment(phoneE164: phoneE164)
    }

    func confirmMfaEnrollment(code: String, phoneE164: String) async throws {
        guard let user = auth.currentUser else {
            throw SpectRoomAuthError.notAuthenticated
        }
        guard let verificationID = Self.pendingVerificationID else {
            throw SpectRoomAuthError.mfaSessionExpired
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            throw SpectRoomAuthError.invalidMfaCode
        }

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: trimmed
        )
        let assertion = PhoneMultiFactorGenerator.assertion(with: credential)

        do {
            try await enroll(user: user, assertion: assertion, displayName: "Phone")
        } catch {
            throw mapMfaError(error)
        }

        let e164 = Self.pendingEnrollPhoneE164 ?? phoneE164
        try await updateUserData([
            Self.phoneE164Key: e164,
            Self.phoneVerifiedAtKey: Date().timeIntervalSince1970,
            Self.mfaEnrolledKey: true
        ])

        Self.pendingVerificationID = nil
        Self.pendingEnrollPhoneE164 = nil

        // Welcome mail only after email + SMS MFA (not on Auth account creation).
        await Self.requestWelcomeEmailAfterMfaEnrollment()
    }

    /// Best-effort: enrollment must not fail if mail delivery fails.
    private static func requestWelcomeEmailAfterMfaEnrollment() async {
        do {
            _ = try await Functions.functions(region: "us-central1")
                .httpsCallable("sendSpectRoomWelcomeEmail")
                .call([:])
            print("✅ Welcome email requested after MFA enrollment")
        } catch {
            print("⚠️ Welcome email after MFA failed: \(error.localizedDescription)")
        }
    }

    func fetchStoredPhoneE164() async -> String? {
        guard let data = try? await fetchUserData() else { return nil }
        return data[Self.phoneE164Key] as? String
    }

    // MARK: - Private helpers

    private func finishVerifiedSignInChecks() async throws {
        // Always prefer server for moderation gates so a recently lifted freeze/ban
        // is not blocked by a stale local cache of discoverFrozenUntil / isBanned.
        if let userData = try await fetchUserData(preferServer: true) {
            if userData["isDeleted"] as? Bool == true {
                let uid = auth.currentUser?.uid
                if Self.isAdminDeletedAccount(userData), let uid {
                    await MainActor.run {
                        self.markRequiresDeletedAcknowledgement(userId: uid)
                    }
                }
                try auth.signOut()
                await MainActor.run {
                    self.isVerifyingSignIn = false
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.hasResolvedUserProfile = true
                }
                if Self.isAdminDeletedAccount(userData) {
                    throw SpectRoomAuthError.accountDeletedByAdmin
                }
                throw SpectRoomAuthError.accountPendingDeletion
            }
            if userData["isBanned"] as? Bool == true {
                try auth.signOut()
                await MainActor.run {
                    self.isVerifyingSignIn = false
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.hasResolvedUserProfile = true
                }
                throw SpectRoomAuthError.accountBanned
            }
            if let freezeUntil = Self.parseDiscoverFreezeUntil(from: userData),
               freezeUntil > Date() {
                try auth.signOut()
                await MainActor.run {
                    self.isVerifyingSignIn = false
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.hasResolvedUserProfile = true
                }
                throw SpectRoomAuthError.accountFrozen(until: freezeUntil)
            }
        }

        let userId = auth.currentUser?.uid
        await MainActor.run {
            self.isVerifyingSignIn = false
            self.hasResolvedUserProfile = false
            self.isAuthenticated = self.auth.currentUser != nil
        }

        if let userId {
            await loadUserData(for: userId)
            await updateFCMTokenIfNeeded()
            await clearPendingAccountRestoredNoticeIfNeeded()
        }
    }

    private func sendSignInMfaCode(
        resolver: MultiFactorResolver,
        hint: PhoneMultiFactorInfo?
    ) async throws -> String {
        guard let hint else {
            throw SpectRoomAuthError.mfaFactorUnavailable
        }
        let session = resolver.session
        #if DEBUG && targetEnvironment(simulator)
        // Do NOT use isAppVerificationDisabledForTesting for MFA sign-in.
        // That SDK path posts the obfuscated hint (+*******…) as E.164 → invalid-phone-number.
        // reCAPTCHA + Console test numbers still accept the fixed code (123456).
        FirebaseBootstrap.prepareSimulatorMfaSignInVerify()
        let probeTask = Task {
            await FirebaseBootstrap.sustainSimulatorMfaNotificationProbe()
        }
        defer {
            probeTask.cancel()
            // Restore enrollment-friendly test mode for later flows.
            FirebaseBootstrap.applyDebugPhoneAuthSettings()
        }
        #endif
        return try await performPhoneAuthRequest(timeoutSeconds: 60) { resume in
            DispatchQueue.main.async {
                #if DEBUG && targetEnvironment(simulator)
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    with: hint,
                    uiDelegate: SpectRoomAuthUIDelegate.shared,
                    multiFactorSession: session
                ) { verificationID, error in
                    if let error {
                        let ns = error as NSError
                        print("❌ MFA sign-in SMS failed domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
                        resume(.failure(error))
                    } else if let verificationID {
                        print("✅ MFA sign-in SMS verificationID received (simulator)")
                        resume(.success(verificationID))
                    } else {
                        resume(.failure(SpectRoomAuthError.mfaSendFailed))
                    }
                }
                #else
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    with: hint,
                    uiDelegate: SpectRoomAuthUIDelegate.shared,
                    multiFactorSession: session
                ) { verificationID, error in
                    if let error {
                        resume(.failure(error))
                    } else if let verificationID {
                        resume(.success(verificationID))
                    } else {
                        resume(.failure(SpectRoomAuthError.mfaSendFailed))
                    }
                }
                #endif
            }
        }
    }

    private func getMultiFactorSession(for user: User) async throws -> MultiFactorSession {
        try await performPhoneAuthRequest(timeoutSeconds: 30) { resume in
            user.multiFactor.getSessionWithCompletion { session, error in
                if let error {
                    resume(.failure(error))
                } else if let session {
                    resume(.success(session))
                } else {
                    resume(.failure(SpectRoomAuthError.mfaSendFailed))
                }
            }
        }
    }

    private func verifyPhoneForEnrollment(phoneE164: String, session: MultiFactorSession) async throws -> String {
        #if DEBUG && targetEnvironment(simulator)
        FirebaseBootstrap.prepareSimulatorMfaPhoneVerify()
        let probeTask = Task {
            await FirebaseBootstrap.sustainSimulatorMfaNotificationProbe()
        }
        defer { probeTask.cancel() }
        #endif

        return try await performPhoneAuthRequest(timeoutSeconds: 45) { resume in
            DispatchQueue.main.async {
                #if DEBUG && targetEnvironment(simulator)
                // Test mode: no reCAPTCHA UI. Passing a UIDelegate can stall Simulator MFA.
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    phoneE164,
                    uiDelegate: nil,
                    multiFactorSession: session
                ) { verificationID, error in
                    if let error {
                        resume(.failure(error))
                    } else if let verificationID {
                        resume(.success(verificationID))
                    } else {
                        resume(.failure(SpectRoomAuthError.mfaSendFailed))
                    }
                }
                #else
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    phoneE164,
                    uiDelegate: SpectRoomAuthUIDelegate.shared,
                    multiFactorSession: session
                ) { verificationID, error in
                    if let error {
                        resume(.failure(error))
                    } else if let verificationID {
                        resume(.success(verificationID))
                    } else {
                        resume(.failure(SpectRoomAuthError.mfaSendFailed))
                    }
                }
                #endif
            }
        }
    }

    /// Wraps Firebase phone/MFA callbacks with a timeout. Simulator reCAPTCHA/APNs can hang forever.
    private func performPhoneAuthRequest<T: Sendable>(
        timeoutSeconds: TimeInterval,
        start: @escaping (@escaping (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var settled = false
            let resumeOnce: (Result<T, Error>) -> Void = { result in
                lock.lock()
                defer { lock.unlock() }
                guard !settled else { return }
                settled = true
                continuation.resume(with: result)
            }

            start(resumeOnce)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) {
                resumeOnce(.failure(SpectRoomAuthError.mfaSendFailed))
            }
        }
    }

    private func enroll(user: User, assertion: MultiFactorAssertion, displayName: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.multiFactor.enroll(with: assertion, displayName: displayName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Prefer the real phone number over MFA display names like "Phone".
    /// SpectRoom shows the full number on the security-code screen (not masked).
    private static func maskedPhone(for hint: PhoneMultiFactorInfo?) -> String {
        if let phone = hint?.phoneNumber.nilIfEmpty {
            return phone
        }
        if let name = hint?.displayName?.nilIfEmpty {
            let genericNames: Set<String> = ["phone", "sms", "mobile", "mfa"]
            if !genericNames.contains(name.lowercased()) {
                return name
            }
        }
        return "auth.mfa.phone.fallback".localized
    }

    private static func multiFactorResolver(from error: Error) -> MultiFactorResolver? {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           nsError.code == AuthErrorCode.secondFactorRequired.rawValue,
           let resolver = nsError.userInfo[AuthErrorUserInfoMultiFactorResolverKey] as? MultiFactorResolver {
            return resolver
        }

        // Some SDK / simulator paths nest the resolver under NSUnderlyingErrorKey.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           let resolver = multiFactorResolver(from: underlying) {
            return resolver
        }

        for value in nsError.userInfo.values {
            if let resolver = value as? MultiFactorResolver {
                return resolver
            }
            if let nested = value as? NSError,
               let resolver = multiFactorResolver(from: nested) {
                return resolver
            }
        }
        return nil
    }

    private static func clearPendingMfaSignIn() {
        pendingSignInResolver = nil
        pendingVerificationID = nil
    }

    private static func clearPendingMfaReauth() {
        pendingReauthResolver = nil
        pendingReauthVerificationID = nil
    }

    private static func mapPasswordReauthError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            switch nsError.code {
            case AuthErrorCode.wrongPassword.rawValue,
                 AuthErrorCode.invalidCredential.rawValue,
                 AuthErrorCode.invalidEmail.rawValue,
                 AuthErrorCode.userNotFound.rawValue:
                return SpectRoomAuthError.wrongPassword
            default:
                break
            }
        }
        if let code = AuthErrorCode(_bridgedNSError: nsError)?.code {
            switch code {
            case .wrongPassword, .invalidCredential, .invalidEmail, .userNotFound:
                return SpectRoomAuthError.wrongPassword
            default:
                break
            }
        }
        let message = nsError.localizedDescription
        if message.localizedCaseInsensitiveContains("password")
            || message.localizedCaseInsensitiveContains("credential")
            || message.localizedCaseInsensitiveContains("invalid email") {
            return SpectRoomAuthError.wrongPassword
        }
        return error
    }

    private func mapMfaError(_ error: Error) -> Error {
        if error is SpectRoomAuthError { return error }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain {
            switch nsError.code {
            case AuthErrorCode.invalidVerificationCode.rawValue,
                 AuthErrorCode.missingVerificationCode.rawValue:
                return SpectRoomAuthError.invalidMfaCode
            case AuthErrorCode.sessionExpired.rawValue,
                 AuthErrorCode.invalidVerificationID.rawValue:
                return SpectRoomAuthError.mfaSessionExpired
            case AuthErrorCode.unverifiedEmail.rawValue:
                return SpectRoomAuthError.emailNotVerifiedForMfa
            case AuthErrorCode.tooManyRequests.rawValue:
                return SpectRoomAuthError.mfaRateLimited
            default:
                break
            }
        }

        if let code = AuthErrorCode(_bridgedNSError: nsError)?.code {
            switch code {
            case .invalidVerificationCode, .missingVerificationCode:
                return SpectRoomAuthError.invalidMfaCode
            case .sessionExpired, .invalidVerificationID:
                return SpectRoomAuthError.mfaSessionExpired
            case .unverifiedEmail:
                return SpectRoomAuthError.emailNotVerifiedForMfa
            case .tooManyRequests:
                return SpectRoomAuthError.mfaRateLimited
            default:
                break
            }
        }

        let message = nsError.localizedDescription
        if message.localizedCaseInsensitiveContains("unusual activity")
            || message.localizedCaseInsensitiveContains("too many requests")
            || message.localizedCaseInsensitiveContains("blocked all requests") {
            return SpectRoomAuthError.mfaRateLimited
        }
        if message.localizedCaseInsensitiveContains("multifactor verification code")
            || message.localizedCaseInsensitiveContains("invalid verification code") {
            return SpectRoomAuthError.invalidMfaCode
        }

        return error
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
