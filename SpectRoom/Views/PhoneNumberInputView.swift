import SwiftUI

/// Country dial-code picker (with flags) + digits-only national number field.
struct PhoneNumberInputView<FocusValue: Hashable>: View {
    @Binding var country: PhoneCountry
    @Binding var nationalNumber: String
    var isFocused: FocusState<FocusValue?>.Binding
    var focusValue: FocusValue
    @State private var showingCountryPicker = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showingCountryPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(country.flag)
                        .font(.title3)
                    Text(country.dialCode)
                        .font(.body.weight(.medium))
                        .foregroundColor(SpectRoomTheme.text)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            TextField("auth.phone.placeholder".localized, text: $nationalNumber)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused(isFocused, equals: focusValue)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .onChange(of: nationalNumber) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue {
                        nationalNumber = digits
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            isFocused.wrappedValue = nil
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.blue)
                        }
                        .accessibilityLabel("common.done".localized)
                    }
                }
        }
        .sheet(isPresented: $showingCountryPicker) {
            PhoneCountryPickerSheet(selectedCountry: $country)
        }
    }
}

private struct PhoneCountryPickerSheet: View {
    @Binding var selectedCountry: PhoneCountry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    private var filteredCountries: [PhoneCountry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return PhoneCountry.all }
        return PhoneCountry.all.filter { country in
            country.name.localizedCaseInsensitiveContains(query)
                || country.dialCode.contains(query)
                || country.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationView {
            List(filteredCountries) { country in
                Button {
                    selectedCountry = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.name)
                                .foregroundColor(SpectRoomTheme.text)
                            Text(country.dialCode)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                        }
                        Spacer()
                        if country == selectedCountry {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "auth.phone.country.search".localized)
            .navigationTitle("auth.phone.country.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) { dismiss() }
                }
            }
        }
    }
}
