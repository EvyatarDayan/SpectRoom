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
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isPasswordVisible = false
    @State private var isConfirmPasswordVisible = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                    // App logo and title
                    VStack(spacing: 16) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("app.name".localized)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("app.tagline".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Toggle between login and signup
                    Picker("Mode", selection: $isLoginMode) {
                        Text("auth.sign.in".localized).tag(true)
                        Text("auth.sign.up".localized).tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Form fields
                    VStack(spacing: 20) {
                        if !isLoginMode {
                            // Name field for signup
                            VStack(alignment: .leading, spacing: 8) {
                                Text("auth.full.name".localized)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("auth.name.placeholder".localized, text: $name)
                                    .textFieldStyle(CustomTextFieldStyle())
                            }
                            
                        }
                        
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("auth.email".localized)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("auth.email.placeholder".localized, text: $email)
                                .textFieldStyle(CustomTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }
                        
                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("auth.password".localized)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            PasswordField(
                                text: $password,
                                placeholder: "auth.password.placeholder".localized,
                                isVisible: $isPasswordVisible
                            )
                        }
                        
                        // Confirm password field for signup
                        if !isLoginMode {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("auth.confirm.password".localized)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                PasswordField(
                                    text: $confirmPassword,
                                    placeholder: "auth.confirm.password.placeholder".localized,
                                    isVisible: $isConfirmPasswordVisible
                                )
                            }
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
                    if isLoginMode {
                        VStack(spacing: 12) {
                            Button("auth.forgot.password".localized) {
                                handleForgotPassword()
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            
                            HStack {
                                Text("auth.no.account".localized)
                                    .foregroundColor(.secondary)
                                
                                Button("auth.sign.up".localized) {
                                    withAnimation {
                                        isLoginMode = false
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    } else {
                        HStack {
                            Text("auth.have.account".localized)
                                .foregroundColor(.secondary)
                            
                            Button("auth.sign.in".localized) {
                                withAnimation {
                                    isLoginMode = true
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    
                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
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
            appState.signUp(name: name, age: 0, email: email, password: password)
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
        
        guard !password.isEmpty, !confirmPassword.isEmpty, password == confirmPassword else {
            errorMessage = "auth.error.password.match".localized
            showingError = true
            return false
        }
        
        name = trimmedName
        email = trimmedEmail
        
        return true
    }
    
    private func isValidEmail(_ string: String) -> Bool {
        let emailFormat = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format:"SELF MATCHES %@", emailFormat)
        return predicate.evaluate(with: string)
    }
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
    
    var body: some View {
        HStack {
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
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
