//
//  HelpSupportView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-11-16.
//

import SwiftUI
import MessageUI

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingContactForm = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 40) {
                        Spacer().frame(height: 40)
                        
                        // Title
                        Text("We'd love to hear from you!")
                            .font(.system(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 24)
                            .padding(.top, 70)
                        
                        // Description
                        Text("Whether you have questions, feedback, or just want to say hi, feel free to reach out.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                        
                        // Top divider
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        
                        // Email / Website block
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("Email:")
                                    .font(.system(size: 18))
                                    .fontWeight(.semibold)
                                Button(action: {
                                    openMail(to: "abashelariprod@gmail.com")
                                }) {
                                    Text("abashelariprod@gmail.com")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("Website:")
                                    .font(.system(size: 18))
                                    .fontWeight(.semibold)
                                Button(action: {
                                    openWebsite("https://abashelariprod.wordpress.com")
                                }) {
                                    Text("abashelariprod.com")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        
                        // Bottom divider
                        Divider()
                            .padding(.horizontal, 24)
                        
                        // OR separator
                        Text("OR")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                            .padding(.bottom, 6)
                        
                        // Push the button section down
//                        Spacer(minLength: 0)
                        
                        // Contact button (placeholder - design to be supplied)
                        Button(action: {
                             showingContactForm = true
                        }) {
                            Text("Contact form")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(18)
                        }
                        .padding(.horizontal, 24)
                        
                        // Response note
                        Text("We aim to respond within 24 hours. Thank you for getting in touch!")
                            .font(.body)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 24)
                        
                        Spacer().frame(height: 24)
                    }
                    // Ensure spacer can push content toward the bottom of the screen
                    .frame(minHeight: UIScreen.main.bounds.height * 0.9, alignment: .top)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Help and support")
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingContactForm) {
            ContactFormView()
        }
        .presentationDetents([.large])
    }
}

#Preview {
    HelpSupportView()
        .environmentObject(AppStateManager.shared)
}

// MARK: - Helpers
private extension HelpSupportView {
    func openMail(to address: String) {
        let mailto = "mailto:\(address)"
        if let url = URL(string: mailto) {
            UIApplication.shared.open(url)
        }
    }
    
    func openWebsite(_ urlString: String) {
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Contact Form
struct ContactFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppStateManager
    
    @State private var fullName: String = ""
    @State private var email: String = ""
    @State private var subject: String = ""
    @State private var message: String = ""
    @State private var isSending = false
    @State private var showSentAlert = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var showMailComposer = false
    @State private var mailComposerResultMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        formField(title: "Full name", text: $fullName)
                            .textInputAutocapitalization(.words)
                            .padding(.top, 100)
                        
                        formField(title: "Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        
                        formField(title: "Subject", text: $subject)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Message")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $message)
                                    .frame(minHeight: 140)
                                    .padding(10)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                                    )
                            }
                        }
                        
                        Button(action: send) {
                            if isSending {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(14)
                            } else {
                                Text("Send")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(14)
                            }
                        }
                        .disabled(isSending)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Contact form")
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear(perform: populateFromUser)
        .alert("Message sent!", isPresented: $showSentAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Thank you. We'll get back to you soon.")
        }
        .alert(validationMessage, isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) { }
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposerView(
                recipients: ["abashelariprod@gmail.com"],
                subject: subject,
                body:
"""
Full name: \(fullName)
Email: \(email)

Message:
\(message)
"""
            ) { result in
                isSending = false
                switch result {
                case .sent:
                    showSentAlert = true
                case .failed(let errorDescription):
                    mailComposerResultMessage = errorDescription ?? "Failed to send email."
                default:
                    break
                }
            }
        }
        .alert("Email", isPresented: Binding(
            get: { mailComposerResultMessage != nil },
            set: { if !$0 { mailComposerResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mailComposerResultMessage ?? "")
        }
    }
    
    private func populateFromUser() {
        if let user = appState.currentUser {
            if fullName.isEmpty { fullName = user.name }
            if email.isEmpty { email = user.email }
        }
    }
    
    private func send() {
        // Validate inputs
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter your full name"
            showValidationAlert = true
            return
        }
        guard isValidEmail(trimmedEmail) else {
            validationMessage = "Email is incorrect"
            showValidationAlert = true
            return
        }
        guard !trimmedSubject.isEmpty else {
            validationMessage = "Add subject"
            showValidationAlert = true
            return
        }
        guard !trimmedMessage.isEmpty else {
            validationMessage = "Add message"
            showValidationAlert = true
            return
        }
        
        // Open email composer with prefilled fields
        isSending = true
        // Prefer in-app mail composer when available
        if MFMailComposeViewController.canSendMail() {
            fullName = trimmedName
            email = trimmedEmail
            subject = trimmedSubject
            message = trimmedMessage
            showMailComposer = true
        } else {
            // Fallback to mailto:
            let subjectEncoded = trimmedSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let body = """
            Full name: \(trimmedName)
            Email: \(trimmedEmail)
            
            Message:
            \(trimmedMessage)
            """
            let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:evya120@yopmail.com?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
                UIApplication.shared.open(url) { _ in
                    isSending = false
                    showSentAlert = true
                }
            } else {
                isSending = false
                mailComposerResultMessage = "Unable to open email client on this device."
            }
        }
    }
    
    private func isValidEmail(_ string: String) -> Bool {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: string)
    }
    
    @ViewBuilder
    private func formField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
    }
}

// MARK: - Mail Composer Wrapper
struct MailComposerView: UIViewControllerRepresentable {
    enum Result {
        case sent
        case saved
        case cancelled
        case failed(String?)
    }
    
    let recipients: [String]
    let subject: String
    let body: String
    let onFinish: (Result) -> Void
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }
    
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Result) -> Void
        init(onFinish: @escaping (Result) -> Void) {
            self.onFinish = onFinish
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            defer { controller.dismiss(animated: true) }
            if let error {
                onFinish(.failed(error.localizedDescription))
                return
            }
            switch result {
            case .sent:
                onFinish(.sent)
            case .saved:
                onFinish(.saved)
            case .cancelled:
                onFinish(.cancelled)
            case .failed:
                onFinish(.failed(nil))
            @unknown default:
                onFinish(.cancelled)
            }
        }
    }
}


