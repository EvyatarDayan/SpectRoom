//
//  HelpSupportView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-11-16.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FirebaseFirestore
import UIKit

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppStateManager

    enum Topic: String, CaseIterable, Identifiable {
        case safety, bug, feedback, accountFreeze, accountBan, accountDeleted, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .bug:
                return "support.topic.bug".localized
            case .safety:
                return "support.topic.safety".localized
            case .feedback:
                return "support.topic.feedback".localized
            case .accountFreeze:
                return localizedOrFallback("support.topic.account.freeze", "Account freeze")
            case .accountBan:
                return localizedOrFallback("support.topic.account.ban", "Account ban")
            case .accountDeleted:
                return localizedOrFallback("support.topic.account.deleted", "Account deleted")
            case .other:
                return "support.topic.other".localized
            }
        }

        private static func localizedOrFallback(_ key: String, _ fallback: String) -> String {
            let value = key.localized
            return (value == key || value.isEmpty) ? fallback : value
        }

        private func localizedOrFallback(_ key: String, _ fallback: String) -> String {
            Self.localizedOrFallback(key, fallback)
        }

        var subjectPrefix: String {
            switch self {
            case .bug:           return "[Bug]"
            case .safety:        return "[Safety]"
            case .feedback:      return "[Feedback]"
            case .accountFreeze: return "[Account freeze]"
            case .accountBan:    return "[Account ban]"
            case .accountDeleted: return "[Account deleted]"
            case .other:         return "[Other]"
            }
        }

        /// Moderation topics are only offered when the sheet is opened from freeze/ban flows.
        var isModerationOnly: Bool {
            switch self {
            case .accountFreeze, .accountBan, .accountDeleted: return true
            default: return false
            }
        }
    }

    /// Topics shown in the chip row. Moderation topics only appear when preselected/locked.
    private var selectableTopics: [Topic] {
        if let lockedTopic {
            return [lockedTopic]
        }
        return Topic.allCases.filter { !$0.isModerationOnly }
    }

    var initialTopic: Topic = .safety
    var lockedTopic: Topic? = nil
    var maxMessageLength: Int = 500
    var onMessageSent: (() -> Void)? = nil

    @State private var selectedTopic: Topic
    @State private var message: String = ""
    @State private var isSending = false
    @State private var didSendSuccessfully = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var didAttemptSend = false
    @State private var showingImagePicker = false
    @State private var attachedImage: UIImage? = nil
    @State private var imageValidationError: ChatImageValidationError? = nil

    init(
        initialTopic: Topic = .safety,
        lockedTopic: Topic? = nil,
        maxMessageLength: Int = 500,
        onMessageSent: (() -> Void)? = nil
    ) {
        self.initialTopic = initialTopic
        self.lockedTopic = lockedTopic
        self.maxMessageLength = maxMessageLength
        self.onMessageSent = onMessageSent
        _selectedTopic = State(initialValue: lockedTopic ?? initialTopic)
    }

    private var showMinWarning: Bool {
        didAttemptSend && !didSendSuccessfully && message.trimmingCharacters(in: .whitespacesAndNewlines).count < 20
    }

    var body: some View {
        NavigationView {
            ZStack {
                SpectRoomBackground()

                VStack(alignment: .leading, spacing: 24) {
                        VStack(spacing: 16) {
                            Text("support.title".localized)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(SpectRoomTheme.text)
                                .multilineTextAlignment(.center)

                            Text("support.subtitle".localized)
                                .font(.body)
                                .foregroundColor(SpectRoomTheme.text.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)

                        // Topic chips
                        VStack(alignment: .leading, spacing: 8) {
                            Text("support.topic.label".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)

                            HStack(spacing: 10) {
                                ForEach(selectableTopics) { topic in
                                    let isSelected = topic == selectedTopic
                                    Button {
                                        guard lockedTopic == nil else { return }
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if didSendSuccessfully {
                                                resetFormAfterTopicChange()
                                            }
                                            selectedTopic = topic
                                        }
                                    } label: {
                                        Text(topic.label)
                                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .foregroundColor(isSelected ? .white : SpectRoomTheme.text)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.blue : SpectRoomTheme.card)
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.clear : SpectRoomTheme.subtleBorder(for: colorScheme), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(lockedTopic != nil)
                                }
                            }
                        }

                        // Message field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("support.message.label".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)

                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("support.message.placeholder".localized)
                                        .foregroundColor(Color.gray.opacity(0.6))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                }
                                TextEditor(text: $message)
                                    .frame(height: 140)
                                    .padding(8)
                                    .scrollContentBackground(.hidden)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.sentences)
                                    .disabled(didSendSuccessfully)
                                    .opacity(didSendSuccessfully ? 0.5 : 1)
                                    .onChange(of: message) { _, newValue in
                                        if newValue.count > maxMessageLength {
                                            message = String(newValue.prefix(maxMessageLength))
                                        }
                                    }
                            }
                            .background(SpectRoomTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        showMinWarning ? Color.red : Color.gray.opacity(0.25),
                                        lineWidth: showMinWarning ? 1.5 : 1
                                    )
                            )

                            HStack {
                                Text(showMinWarning ? "support.message.min.chars".localized : " ")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.red)
                                    .opacity(showMinWarning ? 1 : 0)
                                Spacer()
                                Text("\(message.count) / \(maxMessageLength)")
                                    .font(.system(size: 12))
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                            }
                            .padding(.top, 2)
                        }

                        attachmentSection

                        // Send button
                        Button(action: send) {
                            Group {
                                if isSending {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(didSendSuccessfully ? "support.button.sent".localized : "support.button.send".localized)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(didSendSuccessfully ? Color.green : Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isSending || didSendSuccessfully)

                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("support.nav.title".localized)
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.close".localized) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            SupportImagePicker(
                selectedImage: $attachedImage,
                imageValidationError: $imageValidationError
            )
            .ignoresSafeArea()
        }
        .onChange(of: imageValidationError) { _, error in
            guard let error else { return }
            errorMessage = error.alertMessageKey.localized
            showErrorAlert = true
            imageValidationError = nil
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("support.attachment.label".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)

            if let attachedImage {
                HStack(spacing: 12) {
                    Image(uiImage: attachedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("support.attachment.added".localized)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(SpectRoomTheme.text)
                        Text("support.attachment.hint".localized)
                            .font(.caption)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }

                    Spacer(minLength: 8)

                    if !didSendSuccessfully {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.attachedImage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(SpectRoomTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("support.attachment.remove".localized)
                    }
                }
                .padding(12)
                .background(SpectRoomTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .opacity(didSendSuccessfully ? 0.5 : 1)
            } else {
                Button {
                    showingImagePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 18, weight: .medium))
                        Text("support.attachment.add".localized)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                    }
                    .foregroundColor(.blue)
                    .padding(14)
                    .background(SpectRoomTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.blue.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(didSendSuccessfully || isSending)

                Text("support.attachment.hint".localized)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
        }
    }
}

// MARK: - Actions
private extension HelpSupportView {
    func resetFormAfterTopicChange() {
        message = ""
        attachedImage = nil
        didSendSuccessfully = false
        didAttemptSend = false
    }

    func send() {
        didAttemptSend = true
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return }

        isSending = true

        let userId = appState.currentUser?.firebaseDocumentId ?? appState.currentUser?.id.uuidString ?? "unknown"
        let userName = appState.currentUser?.name ?? "Unknown"
        let userEmail = appState.currentUser?.email ?? ""
        let ticketId = Self.makeSupportTicketId()
        let topicLabel = selectedTopic.label
        let image = attachedImage

        Task {
            do {
                var imageURL: String? = nil
                if let image {
                    imageURL = try await PhotoStorageService.shared.uploadSupportImage(image, for: userId)
                }

                var data: [String: Any] = [
                    "ticketId": ticketId,
                    "userId": userId,
                    "userName": userName,
                    "userEmail": userEmail,
                    "topic": topicLabel,
                    "message": trimmed,
                    "status": "new",
                    "createdAt": FieldValue.serverTimestamp()
                ]
                if let imageURL {
                    data["imageURL"] = imageURL
                    data["hasAttachment"] = true
                }

                try await Firestore.firestore().collection("supportMessages").addDocument(data: data)

                await MainActor.run {
                    isSending = false
                    didSendSuccessfully = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        onMessageSent?()
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    if let storageError = error as? PhotoStorageError,
                       let description = storageError.errorDescription {
                        errorMessage = description
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    showErrorAlert = true
                }
            }
        }
    }

    /// e.g. `20082026-12345` — day/month/year + 5 random digits
    static func makeSupportTicketId(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "ddMMyyyy"
        let datePart = formatter.string(from: date)
        let randomPart = String(format: "%05d", Int.random(in: 0...99_999))
        return "\(datePart)-\(randomPart)"
    }
}

// MARK: - Single image gallery picker (≤5MB, JPG/PNG/HEIC)

private struct SupportImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var imageValidationError: ChatImageValidationError?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SupportImagePicker

        init(_ parent: SupportImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let result = results.first else { return }
            let provider = result.itemProvider

            guard let typeId = ChatImageProcessor.matchingTypeIdentifier(for: provider) else {
                DispatchQueue.main.async {
                    self.parent.imageValidationError = .unsupportedFormat
                }
                return
            }
            if Self.isGIF(typeId) {
                DispatchQueue.main.async {
                    self.parent.imageValidationError = .unsupportedFormat
                }
                return
            }
            loadImage(provider: provider, typeId: typeId)
        }

        private static func isGIF(_ typeId: String) -> Bool {
            let lower = typeId.lowercased()
            return lower == UTType.gif.identifier.lowercased()
                || lower.contains("gif")
        }

        private func loadImage(provider: NSItemProvider, typeId: String) {
            if typeId != UTType.image.identifier,
               provider.hasItemConformingToTypeIdentifier(typeId) {
                provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
                    self.handlePickedImageData(data, typeIdentifier: typeId, error: error, provider: provider)
                }
                return
            }

            let candidates = [
                UTType.jpeg.identifier,
                UTType.heic.identifier,
                UTType.png.identifier,
                UTType.heif.identifier,
            ]
            if let match = candidates.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
                provider.loadDataRepresentation(forTypeIdentifier: match) { data, error in
                    self.handlePickedImageData(data, typeIdentifier: match, error: error, provider: provider)
                }
                return
            }

            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self.parent.selectedImage = image.normalizedUpOrientation()
                    } else {
                        self.parent.imageValidationError = .unsupportedFormat
                    }
                }
            }
        }

        private func handlePickedImageData(
            _ data: Data?,
            typeIdentifier: String,
            error: Error?,
            provider: NSItemProvider
        ) {
            if let error {
                print("⚠️ Support image load failed: \(error.localizedDescription)")
            }

            if let data {
                do {
                    try ChatImageProcessor.validateOriginalData(data, typeIdentifier: typeIdentifier)
                    guard let image = UIImage(data: data) else {
                        throw ChatImageValidationError.processingFailed
                    }
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image.normalizedUpOrientation()
                    }
                    return
                } catch let validation as ChatImageValidationError {
                    DispatchQueue.main.async {
                        self.parent.imageValidationError = validation
                    }
                    return
                } catch {
                    DispatchQueue.main.async {
                        self.parent.imageValidationError = .processingFailed
                    }
                    return
                }
            }

            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        if let jpeg = image.jpegData(compressionQuality: 1.0),
                           jpeg.count > ChatImageProcessor.maxOriginalBytes {
                            self.parent.imageValidationError = .fileTooLarge
                        } else {
                            self.parent.selectedImage = image.normalizedUpOrientation()
                        }
                    } else {
                        self.parent.imageValidationError = .unsupportedFormat
                    }
                }
            }
        }
    }
}

#Preview {
    HelpSupportView()
        .environmentObject(AppStateManager.shared)
}
