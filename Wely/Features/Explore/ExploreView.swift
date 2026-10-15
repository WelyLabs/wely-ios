import MapKit
import SwiftUI

/// What friends and the public are up to: as a feed, or on a map.
struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var mode = Mode.feed
    @State private var path = NavigationPath()

    enum Mode { case feed, map }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .feed: FeedList()
                case .map: EventsMap()
                }
            }
            .navigationTitle("Explorer")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Affichage", selection: $mode) {
                        Label("Fil", systemImage: "list.bullet").tag(Mode.feed)
                        Label("Carte", systemImage: "map").tag(Mode.map)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .notificationsToolbar()
            .withRoutes()
            .handlesDestinations(on: .feed, path: $path)
        }
    }
}

/// The upcoming events the user may join, soonest first, grouped by day.
private struct FeedList: View {
    @Environment(AppModel.self) private var app
    @State private var state: Loadable<[FeedEvent]> = .loading
    @State private var joined: Set<String> = []

    var body: some View {
        LoadableView(state: state, retry: load) { events in
            if events.isEmpty {
                ContentUnavailableView("Rien de prévu pour l'instant", systemImage: "sparkles",
                                       description: Text("Quand vos amis organisent des sorties, elles apparaissent ici."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                        ForEach(grouped(events), id: \.0) { day, items in
                            Section {
                                ForEach(items) { event in
                                    NavigationLink(value: Route.event(event)) {
                                        EventCard(event: event)
                                            .overlay(alignment: .topTrailing) { joinBadge(event) }
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text(day)
                                    .font(.headline)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGroupedBackground))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .refreshable { await load() }
        .task(id: app.eventsVersion) { await load() }
    }

    @ViewBuilder
    private func joinBadge(_ event: FeedEvent) -> some View {
        if event.organizerId == app.people.myId {
            Label("Vous organisez", systemImage: "star.fill")
                .font(.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        } else if joined.contains(event.id) {
            Label("Inscrit", systemImage: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.green, in: Capsule())
                .padding(10)
        } else {
            AsyncButton {
                _ = try await app.events.toggleSubscription(event.id)
                joined.insert(event.id)
                app.eventsChanged()
            } label: {
                Label("Rejoindre", systemImage: "plus")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.blue, in: Capsule())
            }
            .padding(10)
        }
    }

    private func load() async {
        do {
            async let feed = app.events.feed()
            async let mine = app.events.subscribed()
            let events = try await feed
            joined = Set((try? await mine)?.map(\.id) ?? [])
            state = .loaded(events.filter { !$0.isPast })
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }

    private func grouped(_ events: [FeedEvent]) -> [(String, [FeedEvent])] {
        var result: [(String, [FeedEvent])] = []
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            let label = event.isOpenPoll ? "Date à fixer" : event.startDate.dayLabel()
            if let index = result.firstIndex(where: { $0.0 == label }) { result[index].1.append(event) } else { result.append((label, [event])) }
        }
        return result
    }
}

/// Upcoming events on a map; moving the map loads its area.
private struct EventsMap: View {
    @Environment(AppModel.self) private var app
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.764, longitude: 4.8357), latitudinalMeters: 20_000, longitudinalMeters: 20_000))
    @State private var events: [FeedEvent] = []
    @State private var selected: FeedEvent?
    @State private var region: MKCoordinateRegion?

    var body: some View {
        Map(position: $position, selection: Binding(get: { selected?.id }, set: { id in selected = events.first { $0.id == id } })) {
            ForEach(events.filter { $0.coordinates != nil }) { event in
                let c = event.coordinates!
                Marker(event.title, systemImage: EventTint.symbol(for: event.title),
                       coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude))
                    .tint(event.organizerId == app.people.myId ? Theme.blue : Theme.orange)
                    .tag(event.id)
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in region = context.region }
        .task(id: region.map { "\($0.center.latitude),\($0.center.longitude),\($0.span.latitudeDelta)" }) {
            guard let region else { return }
            try? await Task.sleep(for: .milliseconds(250))
            let south = region.center.latitude - region.span.latitudeDelta / 2
            let north = region.center.latitude + region.span.latitudeDelta / 2
            let west = region.center.longitude - region.span.longitudeDelta / 2
            let east = region.center.longitude + region.span.longitudeDelta / 2
            if let found = try? await app.events.map(south: south, west: west, north: north, east: east) { events = found }
        }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                NavigationLink(value: Route.event(selected)) {
                    HStack(spacing: 12) {
                        DateBadge(date: selected.startDate, tentative: selected.isOpenPoll)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.title).font(.headline).lineLimit(1)
                            Text(selected.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
                .buttonStyle(.plain)
            }
        }
    }
}
