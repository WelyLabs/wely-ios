import MapKit
import Observation
import SwiftUI

/// Place suggestions as the user types, from Apple Maps (the web uses Photon for the same).
@Observable
final class LocationSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet { completer.queryFragment = query }
    }
    private(set) var suggestions: [MKLocalSearchCompletion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Delivered on the main thread; read through our own completer, which lives there.
        MainActor.assumeIsolated { suggestions = Array(self.completer.results.prefix(6)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }

    /// The picked suggestion as a label and coordinates.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (label: String, coordinates: Coordinates?) {
        let label = completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle)"
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        let item = response?.mapItems.first
        let location: CLLocationCoordinate2D?
        if #available(iOS 26, *) { location = item?.location.coordinate } else { location = item?.placemark.coordinate }
        return (label, location.map { Coordinates(latitude: $0.latitude, longitude: $0.longitude) })
    }
}

/// A text field for a place, with suggestions under it; picking one sets the coordinates.
struct LocationField: View {
    @Binding var label: String
    @Binding var coordinates: Coordinates?
    @State private var search = LocationSearch()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: coordinates == nil ? "mappin" : "mappin.circle.fill")
                    .foregroundStyle(coordinates == nil ? Color.secondary : Theme.orange)
                TextField("Lieu", text: $label)
                    .focused($focused)
                    .onChange(of: label) { _, text in
                        if focused { coordinates = nil; search.query = text }
                    }
            }
            if focused, !search.suggestions.isEmpty, !label.isEmpty {
                ForEach(search.suggestions, id: \.self) { suggestion in
                    Button {
                        Task {
                            let place = await search.resolve(suggestion)
                            focused = false
                            label = place.label
                            coordinates = place.coordinates
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).font(.wely.subheadline)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.wely.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
