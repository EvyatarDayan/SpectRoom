#if DEBUG
import Foundation
import FirebaseCore
@testable import FirebaseAuth

/// DEBUG Simulator helper: Firebase Auth checks notification forwarding *before*
/// honoring `isAppVerificationDisabledForTesting`. On Simulator that probe often
/// fails (1s timeout), which blocks MFA enrollment even for Console test numbers.
///
/// `immediateCallbackForTestFaking` is the same hook Firebase's own unit tests use.
enum SimulatorPhoneAuthSupport {
    /// Satisfies Auth's notification-forwarding probe without changing test-mode.
    static func enableNotificationProbeIfNeeded() {
        #if targetEnvironment(simulator)
        guard FirebaseApp.app() != nil else { return }
        Auth.auth().notificationManager.immediateCallbackForTestFaking = { true }
        print("✅ Simulator MFA: forced Auth notification-forwarding OK (test hook)")
        #endif
    }

    static func enableForMfaIfNeeded() {
        #if targetEnvironment(simulator)
        guard FirebaseApp.app() != nil else { return }
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        enableNotificationProbeIfNeeded()
        #endif
    }
}
#endif
