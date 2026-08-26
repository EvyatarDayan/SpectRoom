import Foundation

struct PhoneCountry: Identifiable, Hashable {
    let id: String
    let name: String
    let flag: String
    let dialCode: String

    var displayLabel: String { "\(flag) \(dialCode)" }

    /// Common signup options; Sweden first (app default).
    static let all: [PhoneCountry] = [
        PhoneCountry(id: "SE", name: "Sweden", flag: "🇸🇪", dialCode: "+46"),
        PhoneCountry(id: "NO", name: "Norway", flag: "🇳🇴", dialCode: "+47"),
        PhoneCountry(id: "DK", name: "Denmark", flag: "🇩🇰", dialCode: "+45"),
        PhoneCountry(id: "FI", name: "Finland", flag: "🇫🇮", dialCode: "+358"),
        PhoneCountry(id: "DE", name: "Germany", flag: "🇩🇪", dialCode: "+49"),
        PhoneCountry(id: "NL", name: "Netherlands", flag: "🇳🇱", dialCode: "+31"),
        PhoneCountry(id: "BE", name: "Belgium", flag: "🇧🇪", dialCode: "+32"),
        PhoneCountry(id: "FR", name: "France", flag: "🇫🇷", dialCode: "+33"),
        PhoneCountry(id: "ES", name: "Spain", flag: "🇪🇸", dialCode: "+34"),
        PhoneCountry(id: "IT", name: "Italy", flag: "🇮🇹", dialCode: "+39"),
        PhoneCountry(id: "PT", name: "Portugal", flag: "🇵🇹", dialCode: "+351"),
        PhoneCountry(id: "GB", name: "United Kingdom", flag: "🇬🇧", dialCode: "+44"),
        PhoneCountry(id: "IE", name: "Ireland", flag: "🇮🇪", dialCode: "+353"),
        PhoneCountry(id: "AT", name: "Austria", flag: "🇦🇹", dialCode: "+43"),
        PhoneCountry(id: "CH", name: "Switzerland", flag: "🇨🇭", dialCode: "+41"),
        PhoneCountry(id: "PL", name: "Poland", flag: "🇵🇱", dialCode: "+48"),
        PhoneCountry(id: "US", name: "United States", flag: "🇺🇸", dialCode: "+1"),
        PhoneCountry(id: "CA", name: "Canada", flag: "🇨🇦", dialCode: "+1"),
        PhoneCountry(id: "AU", name: "Australia", flag: "🇦🇺", dialCode: "+61"),
        PhoneCountry(id: "IL", name: "Israel", flag: "🇮🇱", dialCode: "+972"),
        PhoneCountry(id: "IN", name: "India", flag: "🇮🇳", dialCode: "+91"),
        PhoneCountry(id: "BR", name: "Brazil", flag: "🇧🇷", dialCode: "+55"),
        PhoneCountry(id: "MX", name: "Mexico", flag: "🇲🇽", dialCode: "+52"),
        PhoneCountry(id: "JP", name: "Japan", flag: "🇯🇵", dialCode: "+81"),
        PhoneCountry(id: "KR", name: "South Korea", flag: "🇰🇷", dialCode: "+82"),
        PhoneCountry(id: "SG", name: "Singapore", flag: "🇸🇬", dialCode: "+65"),
        PhoneCountry(id: "AE", name: "United Arab Emirates", flag: "🇦🇪", dialCode: "+971"),
        PhoneCountry(id: "ZA", name: "South Africa", flag: "🇿🇦", dialCode: "+27"),
        PhoneCountry(id: "TR", name: "Turkey", flag: "🇹🇷", dialCode: "+90"),
        PhoneCountry(id: "GR", name: "Greece", flag: "🇬🇷", dialCode: "+30"),
    ]

    static let `default` = all.first { $0.id == "SE" } ?? all[0]
}
