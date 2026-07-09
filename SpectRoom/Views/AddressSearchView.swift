import SwiftUI
import MapKit

enum SwedenLocation {
    static let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 62.0, longitude: 16.0),
        span: MKCoordinateSpan(latitudeDelta: 14.0, longitudeDelta: 14.0)
    )
    static let countryName = "Sweden"
    static let countryCode = "SE"
    
    static func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= 55.3 && latitude <= 69.1 && longitude >= 10.5 && longitude <= 24.2
    }
    
    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    
    static func isSwedenCompletion(_ completion: MKLocalSearchCompletion) -> Bool {
        let combined = "\(completion.title) \(completion.subtitle)".lowercased()
        let excludedCountries = [
            "norway", "norge", "denmark", "danmark", "finland", "suomi",
            "germany", "deutschland", "france", "frankrike", "spain", "spanien",
            "italy", "italien", "united states", "usa", "canada", "united kingdom", "uk"
        ]
        return !excludedCountries.contains { combined.contains($0) }
    }
    
    static func isSwedenPlacemark(_ placemark: MKPlacemark) -> Bool {
        if placemark.isoCountryCode?.uppercased() == countryCode {
            return true
        }
        if let coordinate = placemark.location?.coordinate, contains(coordinate) {
            return true
        }
        let combined = [placemark.country, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return combined.contains("sweden") || combined.contains("sverige")
    }
}

// MARK: - Search Completer Delegate
class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate, ObservableObject {
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { [weak self] in
            self?.searchResults = completer.results
            self?.isSearching = false
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.searchResults = []
            self?.isSearching = false
            print("Address search error: \(error.localizedDescription)")
        }
    }
}

struct AddressSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedAddress: String
    @Binding var selectedLatitude: Double?
    @Binding var selectedLongitude: Double?
    @State private var searchText = ""
    @StateObject private var searchDelegate = SearchCompleterDelegate()
    @State private var searchCompleter = MKLocalSearchCompleter()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isGeocoding = false
    @State private var mapRegion = SwedenLocation.region
    @State private var mapAnnotations: [PlaceAnnotation] = []
    @State private var selectedCompletion: MKLocalSearchCompletion?
    @State private var previewCoordinate: CLLocationCoordinate2D?
    @State private var previewAddressText: String = ""
    @State private var showingSwedenOnlyAlert = false
    
    private var filteredSearchResults: [MKLocalSearchCompletion] {
        searchDelegate.searchResults.filter { SwedenLocation.isSwedenCompletion($0) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("address.search.placeholder".localized, text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($isSearchFieldFocused)
                        .onChange(of: searchText) { _, newValue in
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                searchDelegate.searchResults = []
                                selectedCompletion = nil
                                previewAddressText = ""
                                mapAnnotations = []
                                previewCoordinate = nil
                            } else {
                                searchDelegate.isSearching = true
                            }
                            searchCompleter.queryFragment = newValue
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            selectedCompletion = nil
                            previewAddressText = ""
                            mapAnnotations = []
                            previewCoordinate = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(
                    Color(
                        colorScheme == .dark ? .secondarySystemBackground : .systemGray6
                    )
                )
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top)
                
                Text("address.search.privacy.notice".localized)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                Text("address.search.sweden.only.notice".localized)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                // Search Results
                Group {
                    if searchDelegate.isSearching && filteredSearchResults.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView("address.search.searching".localized)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else if filteredSearchResults.isEmpty && !searchText.isEmpty {
                        Text("address.search.no.results.sweden".localized)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12, pinnedViews: []) {
                                ForEach(filteredSearchResults, id: \.self) { result in
                                    AddressResultRow(
                                        result: result,
                                        isSelected: selectedCompletion.map { isSameCompletion($0, result) } ?? false,
                                        onTap: {
                                            previewSelection(for: result)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                
                if let _ = selectedCompletion {
                    VStack(spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            Map(coordinateRegion: $mapRegion, annotationItems: mapAnnotations) { annotation in
                                MapAnnotation(coordinate: annotation.coordinate) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                        if !annotation.title.isEmpty {
                                            Text(annotation.title)
                                                .font(.caption2)
                                                .padding(4)
                                                .background(.thinMaterial)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                            
                            if previewAddressText.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("address.search.map.placeholder".localized)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(12)
                                        .background(.thinMaterial)
                                        .cornerRadius(12)
                                        .padding(12)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(previewAddressText)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.85)
                                }
                                .padding(12)
                                .background(.thinMaterial)
                                .cornerRadius(12)
                                .padding(12)
                            }
                        }
                        .padding(.horizontal)
                        
                        if isGeocoding {
                            ProgressView("address.search.geocoding".localized)
                                .padding(.horizontal)
                        }
                        
                        Button(action: confirmSelection) {
                            Label("address.search.use.address".localized, systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isGeocoding)
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .navigationTitle("address.search.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
        .alert("address.search.title".localized, isPresented: $showingSwedenOnlyAlert) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("address.search.outside.sweden".localized)
        }
        .onAppear {
            setupSearchCompleter()
            // Focus the search field immediately when the view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }
    
    private func setupSearchCompleter() {
        searchCompleter.delegate = searchDelegate
        searchCompleter.resultTypes = [.address]
        searchCompleter.region = SwedenLocation.region
    }
    
    private func formatAddress(_ completion: MKLocalSearchCompletion) -> String {
        let title = completion.title
        let subtitle = completion.subtitle
        
        if subtitle.isEmpty {
            return title
        } else {
            return "\(title), \(subtitle)"
        }
    }
    
    private func previewSelection(for completion: MKLocalSearchCompletion) {
        selectedCompletion = completion
        previewAddressText = formatAddress(completion)
        isGeocoding = true
        
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        search.start { response, error in
            DispatchQueue.main.async {
                isGeocoding = false
                
                if let error = error {
                    print("Geocoding error: \(error.localizedDescription)")
                    previewCoordinate = nil
                    mapAnnotations = []
                    return
                }
                
                if let response = response, let mapItem = response.mapItems.first {
                    let placemark = mapItem.placemark
                    guard SwedenLocation.isSwedenPlacemark(placemark) else {
                        selectedCompletion = nil
                        previewCoordinate = nil
                        mapAnnotations = []
                        previewAddressText = ""
                        showingSwedenOnlyAlert = true
                        return
                    }
                    
                    let coordinate = placemark.coordinate
                    previewCoordinate = coordinate
                    mapRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    mapAnnotations = [
                        PlaceAnnotation(
                            coordinate: coordinate,
                            title: completion.title,
                            subtitle: completion.subtitle
                        )
                    ]
                } else {
                    previewCoordinate = nil
                    mapAnnotations = []
                }
            }
        }
    }
    
    private func confirmSelection() {
        guard let completion = selectedCompletion else { return }
        guard let coordinate = previewCoordinate, SwedenLocation.contains(coordinate) else {
            showingSwedenOnlyAlert = true
            return
        }
        
        let formatted = formatAddress(completion)
        selectedAddress = formatted
        selectedLatitude = coordinate.latitude
        selectedLongitude = coordinate.longitude
        dismiss()
    }
    
    private func isSameCompletion(_ lhs: MKLocalSearchCompletion, _ rhs: MKLocalSearchCompletion) -> Bool {
        lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }
}

// MARK: - Address Result Row
struct AddressResultRow: View {
    let result: MKLocalSearchCompletion
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "mappin.circle.fill" : "mappin.circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                        .transition(.scale)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct PlaceAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String
}


#Preview {
    AddressSearchView(
        selectedAddress: .constant(""),
        selectedLatitude: .constant(nil),
        selectedLongitude: .constant(nil)
    )
}
