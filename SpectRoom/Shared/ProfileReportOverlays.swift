//
//  ProfileReportOverlays.swift
//  SpectRoom
//

import SwiftUI

enum ProfileReportReason: String, CaseIterable, Identifiable {
    case inappropriateContent
    case fakeProfileOrSpam
    case harassmentOrBullying
    case somethingElse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inappropriateContent: return "profile.report.reason.inappropriate.content".localized
        case .fakeProfileOrSpam: return "profile.report.reason.fake.profile.spam".localized
        case .harassmentOrBullying: return "profile.report.reason.harassment.bullying".localized
        case .somethingElse: return "profile.report.reason.something.else".localized
        }
    }

    /// Stable English value stored in Firestore (not localized).
    var storageCategory: String {
        switch self {
        case .inappropriateContent: return "Inappropriate Content"
        case .fakeProfileOrSpam: return "Fake profile or Spam"
        case .harassmentOrBullying: return "Harassment or Bullying"
        case .somethingElse: return "Something else"
        }
    }
}

enum ReportReasonHeaderStyle {
    /// Red title: "Report Evya"
    case reportOnly
    /// Red title: "Evya has been blocked!"
    case blocked
}

/// First step from chat Report: choose Report only or Report and block.
struct ReportConfirmationOverlay: View {
    let firstName: String
    let onCancel: () -> Void
    let onReport: () -> Void
    let onReportAndBlock: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(String(format: "profile.report.confirm.title".localized, firstName))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                        .padding(.bottom, 4)

                    Text(String(format: "profile.report.confirm.message".localized, firstName))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                HStack(spacing: 12) {
                    destructiveOutlineButton(
                        title: "profile.report.confirm.report.and.block".localized,
                        lineLimit: 2,
                        action: onReportAndBlock
                    )

                    destructiveOutlineButton(
                        title: "profile.report.confirm.action".localized,
                        lineLimit: 1,
                        action: onReport
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(SpectRoomTheme.background)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
            }
            .padding(.horizontal, 36)
        }
    }

    @ViewBuilder
    private func destructiveOutlineButton(title: String, lineLimit: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .lineLimit(lineLimit)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ReportReasonOverlay: View {
    let firstName: String
    var headerStyle: ReportReasonHeaderStyle = .blocked
    let onCancel: () -> Void
    let onSubmit: (ProfileReportReason, String?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isTextFieldFocused: Bool
    @State private var selectedReason: ProfileReportReason? = .inappropriateContent
    @State private var somethingElseText = ""
    @State private var didAttemptSubmit = false
    @State private var showBlockedNotReportedConfirmation = false

    private let somethingElseMinChars = 20
    private let somethingElseMaxChars = 200

    private var trimmedSomethingElseText: String {
        somethingElseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showSomethingElseMinWarning: Bool {
        selectedReason == .somethingElse
            && didAttemptSubmit
            && trimmedSomethingElseText.count < somethingElseMinChars
    }

    private var isSomethingElseActive: Bool {
        selectedReason == .somethingElse
    }

    private var headerTitle: String {
        switch headerStyle {
        case .reportOnly:
            return String(format: "profile.report.notice".localized, firstName)
        case .blocked:
            return String(format: "profile.report.blocked.notice".localized, firstName)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture {
                    if showBlockedNotReportedConfirmation {
                        onCancel()
                    }
                }

            if showBlockedNotReportedConfirmation {
                blockedNotReportedContent
            } else {
                reportFormContent
            }
        }
    }

    private var blockedNotReportedContent: some View {
        VStack(spacing: 0) {
            Text(String(format: "profile.report.blocked.not.reported".localized, firstName))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(SpectRoomTheme.text)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()

            Button(action: onCancel) {
                Text("common.got.it".localized)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var reportFormContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                    .padding(.bottom, 4)

                Divider()

                Text(String(format: "profile.report.title".localized, firstName))
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.leading)

                Text(String(format: "profile.report.confidential".localized, firstName))
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(ProfileReportReason.allCases) { reason in
                    reportOptionButton(reason: reason, isSelected: selectedReason == reason) {
                        selectReason(reason)
                    }
                }

                textFieldSection
            }

            HStack(spacing: 12) {
                Button {
                    handleCancelTapped()
                } label: {
                    Text("common.cancel".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SpectRoomTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    submitReport()
                } label: {
                    Text("profile.report.submit".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.red.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(SpectRoomTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var textFieldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if somethingElseText.isEmpty {
                    Text("profile.report.something.else.placeholder".localized)
                        .font(.body)
                        .foregroundColor(Color.gray.opacity(isSomethingElseActive ? 0.6 : 0.35))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $somethingElseText)
                    .frame(height: 100)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .focused($isTextFieldFocused)
                    .disabled(!isSomethingElseActive)
                    .opacity(isSomethingElseActive ? 1 : 0.45)
                    .onChange(of: somethingElseText) { _, newValue in
                        if newValue.count > somethingElseMaxChars {
                            somethingElseText = String(newValue.prefix(somethingElseMaxChars))
                        }
                    }
            }
            .background(isSomethingElseActive ? SpectRoomTheme.background : SpectRoomTheme.background.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        showSomethingElseMinWarning ? Color.red : Color.gray.opacity(isSomethingElseActive ? 0.25 : 0.15),
                        lineWidth: showSomethingElseMinWarning ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectSomethingElseField()
            }

            HStack {
                Text(showSomethingElseMinWarning ? "support.message.min.chars".localized : " ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .opacity(showSomethingElseMinWarning ? 1 : 0)
                Spacer()
                Text("\(somethingElseText.count) / \(somethingElseMaxChars)")
                    .font(.system(size: 12))
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .opacity(isSomethingElseActive ? 1 : 0.45)
            }
            .padding(.top, 2)
        }
        .opacity(isSomethingElseActive ? 1 : 0.85)
    }

    private func handleCancelTapped() {
        if headerStyle == .blocked {
            showBlockedNotReportedConfirmation = true
        } else {
            onCancel()
        }
    }

    private func submitReport() {
        didAttemptSubmit = true
        guard let selectedReason else { return }
        if selectedReason == .somethingElse {
            guard trimmedSomethingElseText.count >= somethingElseMinChars else { return }
            onSubmit(selectedReason, trimmedSomethingElseText)
            return
        }
        onSubmit(selectedReason, nil)
    }

    private func selectReason(_ reason: ProfileReportReason) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedReason = reason
            didAttemptSubmit = false
            if reason == .somethingElse {
                isTextFieldFocused = true
            } else {
                isTextFieldFocused = false
            }
        }
    }

    private func selectSomethingElseField() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedReason = .somethingElse
            isTextFieldFocused = true
        }
    }

    @ViewBuilder
    private func reportOptionButton(
        reason: ProfileReportReason,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                reportIcon(for: reason)
                    .frame(width: 24, height: 24)

                Text(reason.label)
                    .font(.body)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.blue.opacity(0.08) : SpectRoomTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.blue : SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func reportIcon(for reason: ProfileReportReason) -> some View {
        switch reason {
        case .inappropriateContent:
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.orange)
        case .fakeProfileOrSpam:
            Text("🤖")
                .font(.system(size: 20))
        case .harassmentOrBullying:
            Text("🚫")
                .font(.system(size: 20))
        case .somethingElse:
            Text("💬")
                .font(.system(size: 20))
        }
    }
}

struct ReportThankYouOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                Text("profile.report.thank.you".localized)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                Button(action: onDismiss) {
                    Text("common.ok".localized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
    }
}
