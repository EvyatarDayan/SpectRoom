import Foundation

struct ModerationNotice: Equatable {
    enum Kind: Equatable {
        case warning(message: String)
        /// User is online when freeze is applied — must acknowledge, then sign out.
        case freezeAcknowledgement(until: Date, hours: Int)
        /// Shown after a login attempt while still frozen.
        case loginBlocked(until: Date)
        /// User is online when ban is applied — must acknowledge, then sign out.
        case banAcknowledgement
        /// Shown after a login attempt while permanently banned.
        case loginBanned
        /// Ban was lifted by admin — acknowledge, stay signed in / free to log in.
        case banLifted
        /// User is online when admin deletes the account — must acknowledge, then sign out.
        case deletedAcknowledgement
        /// Shown after a login attempt while the account was deleted by admin.
        case loginDeleted
        /// Soft-deleted account was restored — acknowledge, then go to onboarding/sign-in.
        case restoredAcknowledgement
    }

    let kind: Kind

    var title: String {
        switch kind {
        case .warning:
            return "admin.warning.popup.title".localized
        case .freezeAcknowledgement, .loginBlocked:
            return "admin.freeze.popup.title".localized
        case .banAcknowledgement, .loginBanned:
            return "admin.ban.popup.title".localized
        case .banLifted:
            return "admin.ban.lifted.popup.title".localized
        case .deletedAcknowledgement, .loginDeleted:
            return "admin.deleted.popup.title".localized
        case .restoredAcknowledgement:
            return "admin.restored.popup.title".localized
        }
    }

    var message: String {
        switch kind {
        case .warning(let message):
            return message
        case .freezeAcknowledgement(let until, let hours):
            return String(
                format: "admin.freeze.popup.message".localized,
                hours,
                Self.formattedUnlockDate(until)
            )
        case .loginBlocked(let until):
            let hours = max(1, Int(ceil(until.timeIntervalSinceNow / 3600)))
            return String(
                format: "admin.freeze.popup.message".localized,
                hours,
                Self.formattedUnlockDate(until)
            )
        case .banAcknowledgement, .loginBanned:
            return "admin.ban.popup.message".localized
        case .banLifted:
            return "admin.ban.lifted.popup.message".localized
        case .deletedAcknowledgement, .loginDeleted:
            return "admin.deleted.popup.message".localized
        case .restoredAcknowledgement:
            return "admin.restored.popup.message".localized
        }
    }

    var signsOutOnDismiss: Bool {
        switch kind {
        case .freezeAcknowledgement, .banAcknowledgement, .deletedAcknowledgement:
            return true
        // Restored is a signed-out handoff; dismiss only routes to sign-in (no forced re-logout loop).
        default:
            return false
        }
    }

    /// Warnings / freeze / ban / unban use a single primary button (no checkbox).
    var requiresCheckbox: Bool {
        false
    }

    /// Freeze and ban notices can open Help & Support (same sheet) before logout / after blocked login.
    var showsContactSupport: Bool {
        switch kind {
        case .freezeAcknowledgement, .loginBlocked, .banAcknowledgement, .loginBanned,
                .deletedAcknowledgement, .loginDeleted:
            return true
        default:
            return false
        }
    }

    var acceptLabel: String {
        switch kind {
        case .warning:
            return "admin.warning.popup.accept".localized
        case .freezeAcknowledgement, .loginBlocked:
            return "admin.freeze.popup.accept".localized
        case .banAcknowledgement, .loginBanned:
            return "admin.ban.popup.accept".localized
        case .banLifted:
            return "admin.ban.lifted.popup.accept".localized
        case .deletedAcknowledgement, .loginDeleted:
            return "admin.deleted.popup.accept".localized
        case .restoredAcknowledgement:
            return "admin.restored.popup.accept".localized
        }
    }

    /// Restore handoff uses a blue primary CTA; other moderation notices stay orange.
    var usesBlueAcceptButton: Bool {
        if case .restoredAcknowledgement = kind { return true }
        return false
    }

    var contactSupportLabel: String {
        "admin.freeze.popup.contact.support".localized
    }

    /// Locked Help & Support topic when opening Contact support from this notice.
    var supportTopic: HelpSupportView.Topic {
        switch kind {
        case .banAcknowledgement, .loginBanned:
            return .accountBan
        case .deletedAcknowledgement, .loginDeleted:
            return .accountDeleted
        default:
            return .accountFreeze
        }
    }

    static func formattedUnlockDate(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }
}
