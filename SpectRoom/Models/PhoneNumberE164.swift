import Foundation

enum PhoneNumberE164 {
    /// Builds an E.164 number (`+46701234567`) from country dial code + national digits.
    /// Strips a leading trunk `0` from the national number when present.
    static func build(country: PhoneCountry, nationalNumber: String) -> String? {
        var digits = nationalNumber.filter(\.isNumber)
        guard digits.count >= 6, digits.count <= 15 else { return nil }
        if digits.hasPrefix("0") {
            digits = String(digits.dropFirst())
        }
        guard !digits.isEmpty else { return nil }
        let dial = country.dialCode.filter { $0 == "+" || $0.isNumber }
        guard dial.hasPrefix("+"), dial.count > 1 else { return nil }
        return dial + digits
    }

    /// Masks for UI, e.g. `+46 ••• ••• 67`.
    static func maskedDisplay(_ e164: String) -> String {
        let trimmed = e164.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return trimmed }
        let suffix = trimmed.suffix(2)
        let prefix = trimmed.prefix(min(3, trimmed.count))
        return "\(prefix) •••••• \(suffix)"
    }
}
