import Foundation
import FirebaseCore
import FirebaseAuth

/// Ensures `FirebaseApp.configure()` runs before any `Auth.auth()` / Firestore access.
enum FirebaseBootstrap {
    private static let lock = NSLock()
    private static var didConfigure = false

    @discardableResult
    static func configureIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if FirebaseApp.app() == nil {
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
        }

        didConfigure = true
        applyDebugPhoneAuthSettings()
        return true
    }

    /// Simulator cannot complete silent APNs for Phone/MFA.
    /// Enables Firebase test-phone mode (Console → Authentication → Phone → Phone numbers for testing).
    static func applyDebugPhoneAuthSettings() {
        #if DEBUG
        #if targetEnvironment(simulator)
        guard let settings = Auth.auth().settings else {
            print("❌ Auth.settings is nil — cannot enable phone test mode")
            return
        }
        settings.isAppVerificationDisabledForTesting = true
        print("✅ Phone/MFA test mode ON (simulator). Flag=\(settings.isAppVerificationDisabledForTesting)")
        #endif
        #endif
    }
}
