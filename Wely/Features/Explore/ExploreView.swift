import MapKit
import SwiftUI

/// What friends and the public are up to: as a feed, or on a map.
struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var mode = Mode.feed
    @State private var path = NavigationPath()

    enum Mode { case feed, map }

    var body: some View {
        WelyNavigationStack(path: $path) {
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

/// Close friends to see again, then the upcoming events the user may join: those with the
/// closest friends first, the rest by day.
private struct FeedList: View {
    @Environment(AppModel.self) private var app
    @State private var state: Loadable<[FeedEvent]> = .loading
    @State private var joined: Set<String> = []
    @State private var reunions: [ReunionCandidate] = []
    @State private var outing: EventFormView.Draft?
    @State private var outingFriend: String?

    var body: some View {
        LoadableView(state: state, retry: load) { events in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                    if !reunions.isEmpty {
                        ReunionCard(candidates: reunions, onPropose: propose, onDismiss: dismiss)
                            .padding(.top, 8)
                            .transition(.opacity)
                    }
                    if events.isEmpty {
                        EmptyStateView(title: "Rien de prévu pour l'instant", systemImage: "sparkles", message: "Quand vos amis organisent des sorties, elles apparaissent ici.")
                    }
                    ForEach(FeedRanking.sections(events), id: \.title) { section in
                        Section {
                            ForEach(section.events) { event in
                                NavigationLink(value: Route.event(event)) {
                                    EventCard(event: event)
                                        .overlay(alignment: .topTrailing) { joinBadge(event) }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(section.title)
                                .font(.wely.headline)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.canvas)
                        }
                    }
                }
                .padding(.horizontal)
                .animation(.default, value: reunions)
            }
            .background(Theme.canvas)
        }
        .refreshable { await load() }
        .task(id: app.eventsVersion) { await load() }
        .sheet(item: $outing) { draft in
            EventFormView(draft: draft) { created in
                // Planned: no need to suggest them again here.
                if let friend = outingFriend { reunions.removeAll { $0.friendId == friend } }
                app.eventsChanged()
                app.open(.event(created.id))
            }
        }
    }

    private func propose(_ candidate: ReunionCandidate) async {
        outingFriend = candidate.friendId
        outing = await OutingProposal.draft(with: candidate.friendId, events: app.events)
    }

    private func dismiss(_ candidate: ReunionCandidate) async throws {
        try await app.events.dismissReunion(candidate.friendId)
        reunions.removeAll { $0.friendId == candidate.friendId }
    }

    @ViewBuilder
    private func joinBadge(_ event: FeedEvent) -> some View {
        if event.organizerId == app.people.myId {
            Label("Vous organisez", systemImage: "star.fill")
                .font(.wely.caption.bold())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        } else if joined.contains(event.id) {
            Label("Inscrit", systemImage: "checkmark")
                .font(.wely.caption.bold())
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
                    .font(.wely.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.blue, in: Capsule())
            }
            .padding(10)
        }
    }

    private func load() async {
        do {
            async let feed = app.events.feed(byAffinity: true)
            async let mine = app.events.subscribed()
            // Without them, the feed shows as before.
            async let reunions = app.events.reunions()
            let events = try await feed
            joined = Set((try? await mine)?.map(\.id) ?? [])
            self.reunions = Array(((try? await reunions) ?? []).prefix(3))
            state = .loaded(events.filter { !$0.isPast })
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
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
    // The map's location button stays inert until the app has asked for location access.
    @State private var locationManager = CLLocationManager()

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
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
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
                            Text(selected.title).font(.wely.headline).lineLimit(1)
                            Text(selected.location).font(.wely.caption).foregroundStyle(.secondary).lineLimit(1)
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
