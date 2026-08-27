import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

// MARK: - MFA types

enum AuthSignInOutcome {
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

        do {
            _ = try await auth.signIn(withEmail: email, password: password)
            try await finishVerifiedSignInChecks()
            return .completed
        } catch {
            if let resolver = Self.multiFactorResolver(from: error) {
                Self.pendingSignInResolver = resolver
                let hint = resolver.hints.compactMap { $0 as? PhoneMultiFactorInfo }.first
                let masked: String
                if let name = hint?.displayName?.nilIfEmpty {
                    masked = name
                } else if let phone = hint?.phoneNumber {
                    masked = PhoneNumberE164.maskedDisplay(phone)
                } else {
                    masked = "auth.mfa.phone.fallback".localized
                }

                let verificationID = try await sendSignInMfaCode(resolver: resolver, hint: hint)
                Self.pendingVerificationID = verificationID

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

    func confirmSignInMfa(code: String) async throws {
        guard let resolver = Self.pendingSignInResolver,
              let verificationID = Self.pendingVerificationID else {
            throw SpectRoomAuthError.mfaSessionExpired
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
        }
        #endif
        print("📱 MFA enroll to \(phoneE164), testMode=\(Auth.auth().settings?.isAppVerificationDisabledForTesting ?? false), clientID=\(FirebaseApp.app()?.options.clientID ?? "nil")")
        #endif

        let session = try await getMultiFactorSession(for: user)
        let verificationID = try await verifyPhoneForEnrollment(phoneE164: phoneE164, session: session)
        Self.pendingVerificationID = verificationID
        Self.pendingEnrollPhoneE164 = phoneE164

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
        if let userData = try await fetchUserData() {
            if userData["isDeleted"] as? Bool == true {
                try auth.signOut()
                await MainActor.run {
                    self.isVerifyingSignIn = false
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.hasResolvedUserProfile = true
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
        }
    }

    private func sendSignInMfaCode(
        resolver: MultiFactorResolver,
        hint: PhoneMultiFactorInfo?
    ) async throws -> String {
        guard let hint else {
            throw SpectRoomAuthError.mfaFactorUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    with: hint,
                    uiDelegate: SpectRoomAuthUIDelegate.shared,
                    multiFactorSession: resolver.session
                ) { verificationID, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let verificationID {
                        continuation.resume(returning: verificationID)
                    } else {
                        continuation.resume(throwing: SpectRoomAuthError.mfaSendFailed)
                    }
                }
            }
        }
    }

    private func getMultiFactorSession(for user: User) async throws -> MultiFactorSession {
        try await withCheckedThrowingContinuation { continuation in
            user.multiFactor.getSessionWithCompletion { session, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let session {
                    continuation.resume(returning: session)
                } else {
                    continuation.resume(throwing: SpectRoomAuthError.mfaSendFailed)
                }
            }
        }
    }

    private func verifyPhoneForEnrollment(phoneE164: String, session: MultiFactorSession) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                PhoneAuthProvider.provider().verifyPhoneNumber(
                    phoneE164,
                    uiDelegate: SpectRoomAuthUIDelegate.shared,
                    multiFactorSession: session
                ) { verificationID, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let verificationID {
                        continuation.resume(returning: verificationID)
                    } else {
                        continuation.resume(throwing: SpectRoomAuthError.mfaSendFailed)
                    }
                }
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

    private static func multiFactorResolver(from error: Error) -> MultiFactorResolver? {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              nsError.code == AuthErrorCode.secondFactorRequired.rawValue else {
            return nil
        }
        return nsError.userInfo[AuthErrorUserInfoMultiFactorResolverKey] as? MultiFactorResolver
    }

    private static func clearPendingMfaSignIn() {
        pendingSignInResolver = nil
        pendingVerificationID = nil
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
            default:
                break
            }
        }

        let message = nsError.localizedDescription
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
