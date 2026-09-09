//
//  AuthenticationView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLoginMode = true
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var phoneCountry = PhoneCountry.default
    @State private var phoneNumber = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var focusedField: AuthFormField?
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed header — does not scroll with the form.
            VStack(spacing: 0) {
                Text("app.name".localized)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                Picker("Mode", selection: $isLoginMode) {
                    Text("auth.sign.in".localized).tag(true)
                    Text("auth.sign.up".localized).tag(false)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 24)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // Form fields
                        VStack(spacing: 20) {
                            if !isLoginMode {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("auth.full.name".localized)
                                        .font(.headline)
                                        .foregroundColor(SpectRoomTheme.text)

                                    TextField("auth.name.placeholder".localized, text: $name)
                                        .textFieldStyle(CustomTextFieldStyle())
                                        .autocorrectionDisabled(true)
                                        .textInputAutocapitalization(.words)
                                        .focused($focusedField, equals: .name)
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .email }
                                }
                                .id(AuthFormField.name)
                            }

                            // Email field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("auth.email".localized)
                                    .font(.headline)
                                    .foregroundColor(SpectRoomTheme.text)

                                TextField("auth.email.placeholder".localized, text: $email)
                                    .textFieldStyle(CustomTextFieldStyle())
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = isLoginMode ? .password : .phone }
                            }
                            .id(AuthFormField.email)

                            if !isLoginMode {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("auth.phone".localized)
                                        .font(.headline)
                                        .foregroundColor(SpectRoomTheme.text)

                                    PhoneNumberInputView(
                                        country: $phoneCountry,
                                        nationalNumber: $phoneNumber,
                                        isFocused: $focusedField,
                                        focusValue: .phone
                                    )

                                    Text("auth.phone.helper".localized)
                                        .font(.caption)
                                        .foregroundColor(SpectRoomTheme.secondaryText)
                                }
                                .id(AuthFormField.phone)
                            }

                            // Password field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("auth.password".localized)
                                    .font(.headline)
                                    .foregroundColor(SpectRoomTheme.text)

                                PasswordField(
                                    text: $password,
                                    placeholder: "auth.password.placeholder".localized,
                                    isVisible: $isPasswordVisible,
                                    focusedField: $focusedField,
                                    focusValue: .password,
                                    submitLabel: isLoginMode ? .go : .next,
                                    onSubmit: {
                                        if isLoginMode {
                                            handleAuthentication()
                                        } else {
                                            focusedField = .confirmPassword
                                        }
                                    }
                                )
                            }
                            .id(AuthFormField.password)

                            if !isLoginMode {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("auth.confirm.password".localized)
                                        .font(.headline)
                                        .foregroundColor(SpectRoomTheme.text)

                                    PasswordField(
                                        text: $confirmPassword,
                                        placeholder: "auth.confirm.password.placeholder".localized,
                                        isVisible: $isConfirmPasswordVisible,
                                        focusedField: $focusedField,
                                        focusValue: .confirmPassword,
                                        submitLabel: .go,
                                        onSubmit: { handleAuthentication() }
                                    )
                                }
                                .id(AuthFormField.confirmPassword)
                            }
                        }
                        .padding(.horizontal)

                        // Action button
                        Button(action: {
                            handleAuthentication()
                        }) {
                            HStack {
                                if appState.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                Text(isLoginMode ? "auth.sign.in".localized : "auth.sign.up".localized)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(buttonBackgroundColor)
                            .cornerRadius(12)
                        }
                        .disabled(buttonIsDisabled)
                        .padding(.horizontal)

                        // Additional options
                        VStack(spacing: 12) {
                            if isLoginMode {
                                Button("auth.forgot.password".localized) {
                                    handleForgotPassword()
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)

                                HStack {
                                    Text("auth.no.account".localized)
                                        .foregroundColor(SpectRoomTheme.secondaryText)

                                    Button("auth.sign.up".localized) {
                                        isLoginMode = false
                                    }
                                    .foregroundColor(.blue)
                                }
                            } else {
                                HStack {
                                    Text("auth.have.account".localized)
                                        .foregroundColor(SpectRoomTheme.secondaryText)

                                    Button("auth.sign.in".localized) {
                                        isLoginMode = true
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    // Extra room so the focused field can scroll fully above the keyboard.
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 24 : 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    scrollFocusedField(field, using: proxy)
                }
                .onChange(of: keyboardHeight) { _, height in
                    guard height > 0 else { return }
                    scrollFocusedField(focusedField, using: proxy)
                }
                .onChange(of: isLoginMode) { _, _ in
                    focusedField = nil
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                    guard
                        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                        let window = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .flatMap(\.windows)
                            .first(where: \.isKeyWindow)
                    else { return }
                    let overlap = max(0, window.bounds.maxY - frame.origin.y)
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = overlap
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        keyboardHeight = 0
                    }
                }
            }
        }
        // Fill the screen so the parent cannot vertically center a short ScrollView.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .authFlowPreferenceControls()
        .spectRoomScreenBackground()
        .alert(isPresented: $showingError) {
            Alert(
                title: Text(errorMessage).fontWeight(.bold),
                dismissButton: .default(Text("auth.ok".localized))
            )
        }
        .onChange(of: appState.authErrorMessage) { _, newValue in
            if let message = newValue {
                errorMessage = message
                showingError = true
                appState.authErrorMessage = nil
            }
        }
    }
    
    private var buttonIsDisabled: Bool {
        // Sign in button is always enabled (only disabled when loading)
        return appState.isLoading
    }
    
    private var buttonBackgroundColor: Color {
        // Sign in button is always blue (only gray when loading)
        if appState.isLoading {
            return Color.gray
        }
        return Color.blue
    }
    
    private func handleAuthentication() {
        // Clear any previous errors
        errorMessage = ""
        showingError = false
        
        if isLoginMode {
            // Always call signIn - empty fields will be treated as invalid credentials
            appState.signIn(email: email, password: password)
        } else {
            guard validateSignUpInputs() else { return }
            guard let phoneE164 = PhoneNumberE164.build(country: phoneCountry, nationalNumber: phoneNumber) else {
                errorMessage = "auth.error.phone.invalid".localized
                showingError = true
                return
            }
            appState.signUp(name: name, age: 18, email: email, password: password, phoneE164: phoneE164)
        }
    }
    
    private func handleForgotPassword() {
        if email.isEmpty {
            errorMessage = "auth.email.required".localized
            showingError = true
        } else {
            appState.resetPassword(email: email)
            errorMessage = String(format: "auth.password.reset.sent".localized, email)
            showingError = true
        }
    }
    
    private func validateSignUpInputs() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmedName.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount >= 2 else {
            errorMessage = "auth.error.fullname".localized
            showingError = true
            return false
        }
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmedEmail) else {
            errorMessage = "auth.error.email.format".localized
            showingError = true
            return false
        }

        let digitsOnly = phoneNumber.filter(\.isNumber)
        guard digitsOnly.count >= 6, digitsOnly.count <= 15 else {
            errorMessage = "auth.error.phone.invalid".localized
            showingError = true
            return false
        }
        
        guard !password.isEmpty, !confirmPassword.isEmpty, password == confirmPassword else {
            errorMessage = "auth.error.password.match".localized
            showingError = true
            return false
        }
        
        name = trimmedName
        email = trimmedEmail
        phoneNumber = digitsOnly
        
        return true
    }
    
    private func isValidEmail(_ string: String) -> Bool {
        let emailFormat = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format:"SELF MATCHES %@", emailFormat)
        return predicate.evaluate(with: string)
    }

    private func scrollFocusedField(_ field: AuthFormField?, using proxy: ScrollViewProxy) {
        guard let field else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(field, anchor: UnitPoint(x: 0.5, y: 0.35))
            }
        }
    }
}

enum AuthFormField: Hashable {
    case name
    case email
    case phone
    case password
    case confirmPassword
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

struct PasswordField: View {
    @Binding var text: String
    let placeholder: String
    @Binding var isVisible: Bool
    var focusedField: FocusState<AuthFormField?>.Binding
    var focusValue: AuthFormField
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .textContentType(.password)
            .focused(focusedField, equals: focusValue)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
            .padding(.leading)
            .padding(.vertical)
            
            Button(action: {
                isVisible.toggle()
            }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.gray)
                    .padding(.trailing, 12)
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    AuthenticationView()
}
