import Foundation
import FirebaseCore
import FirebaseAuth
import UIKit

/// Ensures `FirebaseApp.configure()` runs when `UIApplication` is ready.
/// Configuring (or touching `Auth.auth()`) from SwiftUI `App.init` leaves Auth's phone
/// managers (`tokenManager` / `notificationManager`) nil — SMS MFA then fails with
/// `notificationNotForwarded` and `setAPNSToken` crashes. See firebase-ios-sdk#16273.
enum FirebaseBootstrap {
    private static let lock = NSLock()
    private static var didConfigure = false

    /// True once configure has completed successfully.
    static var isConfigured: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didConfigure && FirebaseApp.app() != nil
    }

    @discardableResult
    static func configureIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if FirebaseApp.app() != nil {
            didConfigure = true
            applyDebugPhoneAuthSettingsUnlocked()
            return true
        }

        // Auth phone managers init only when UIApplication.shared exists.
        guard isUIApplicationAvailable() else {
            print("⏳ Deferring Firebase configure until UIApplication is ready (use AppDelegate)")
            return false
        }

        var options: FirebaseOptions?
        var source: String?

        if let bundlePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let bundleOptions = FirebaseOptions(contentsOfFile: bundlePath) {
            options = bundleOptions
            source = "main bundle"
        } else if let projectPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist", inDirectory: nil),
                  let projectOptions = FirebaseOptions(contentsOfFile: projectPath) {
            options = projectOptions
            source = "project directory"
        } else {
            let absolutePath = "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom/SpectRoom/GoogleService-Info.plist"
            if FileManager.default.fileExists(atPath: absolutePath),
               let absoluteOptions = FirebaseOptions(contentsOfFile: absolutePath) {
                options = absoluteOptions
                source = "absolute path"
            }
        }

        if let options {
            FirebaseApp.configure(options: options)
            print("✅ Firebase configured with project: \(options.projectID) (source: \(source ?? "unknown"))")
        } else {
            FirebaseApp.configure()
            if let app = FirebaseApp.app() {
                print("✅ Firebase configured with default options: \(app.options.projectID)")
            } else {
                assertionFailure("❌ Firebase configuration failed. Ensure GoogleService-Info.plist is included in the target.")
                return false
            }
        }

        didConfigure = true
        applyDebugPhoneAuthSettingsUnlocked()
        return true
    }

    /// Simulator only: skip silent APNs / reCAPTCHA so Console “Phone numbers for testing” work.
    /// Never enable this on a real device with a live number — Firebase returns
    /// “The request does not contain a client identifier.” (MISSING_CLIENT_IDENTIFIER).
    static func applyDebugPhoneAuthSettings() {
        lock.lock()
        defer { lock.unlock() }
        applyDebugPhoneAuthSettingsUnlocked()
    }

    private static func applyDebugPhoneAuthSettingsUnlocked() {
        #if DEBUG
        guard FirebaseApp.app() != nil else { return }
        guard let settings = Auth.auth().settings else {
            print("❌ Auth.settings is nil — cannot set phone test mode")
            return
        }
        #if targetEnvironment(simulator)
        settings.isAppVerificationDisabledForTesting = true
        print("✅ Phone/MFA test mode ON (simulator). Use Console test numbers. Flag=\(settings.isAppVerificationDisabledForTesting)")
        #else
        settings.isAppVerificationDisabledForTesting = false
        if let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty {
            print("✅ Phone/MFA real verification (device). clientID present. testMode=false")
        } else {
            print("⚠️ Phone/MFA: GoogleService-Info.plist is missing CLIENT_ID — reCAPTCHA may fail. Enable Google Sign-In once and re-download the plist.")
        }
        #endif
        #endif
    }

    private static func isUIApplicationAvailable() -> Bool {
        let sel = NSSelectorFromString("sharedApplication")
        guard UIApplication.responds(to: sel),
              let raw = UIApplication.perform(sel) else {
            return false
        }
        return raw.takeUnretainedValue() is UIApplication
    }
}
