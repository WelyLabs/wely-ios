import MapKit
import PhotosUI
import SwiftUI

/// An event and everything one can do with it: join or leave, answer, vote on its date, see
/// who comes, talk in its group, split its costs.
struct EventDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let eventId: String
    let initial: FeedEvent?

    @State private var event: FeedEvent?
    @State private var participants: EventParticipants?
    @State private var conflicts: [FeedEvent] = []
    @State private var loadError: String?
    @State private var error: String?
    @State private var coverItem: PhotosPickerItem?
    @State private var showingParticipants = false
    @State private var leaving = false
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var addingToCalendar = false

    private var myId: String? { app.people.myId }
    private var isOrganizer: Bool { event?.organizerId == myId }
    private var isParticipant: Bool { participants?.participantIds.contains(myId ?? "") == true || isOrganizer }

    var body: some View {
        Group {
            if let event {
                content(event)
            } else if let loadError {
                EmptyStateView(title: "Événement introuvable", systemImage: "calendar.badge.exclamationmark", message: loadError)
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if event != nil { menu } }
        .task { await load() }
        .task(id: event?.isOpenPoll == true && !app.isDemo) { await followPoll() }
        .refreshable { await load() }
        .errorAlert($error)
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task { await uploadCover(item) }
        }
        .sheet(isPresented: $showingParticipants) {
            if let participants { ParticipantsSheet(participants: participants, organizerId: event?.organizerId ?? "") }
        }
        .sheet(isPresented: $leaving) {
            if let event, let participants { LeaveSheet(event: event, participants: participants) { result in handleLeave(result) } }
        }
        .sheet(isPresented: $editing) {
            if let event {
                EventEditSheet(event: event) { updated in
                    self.event = updated
                    app.eventsChanged()
                    Task { conflicts = (try? await app.events.conflicts(of: updated.id)) ?? [] }
                }
            }
        }
        .confirmationDialog("Supprimer l'événement ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Supprimer pour tout le monde", role: .destructive) { Task { await deleteEvent() } }
        } message: {
            Text("Les participants ne le verront plus. Cette action est définitive.")
        }
    }

    // MARK: Content

    private func content(_ event: FeedEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EventCover(event: event, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .bottomTrailing) {
                        if isOrganizer {
                            PhotosPicker(selection: $coverItem, matching: .images) {
                                Label("Couverture", systemImage: "photo.badge.plus")
                                    .font(.wely.caption.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .padding(10)
                        }
                    }

                header(event)
                primaryAction(event)

                if !conflicts.isEmpty, isParticipant {
                    Label("Chevauche \(conflicts.map(\.title).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                        .font(.wely.subheadline)
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                whenAndWhere(event)

                if let poll = event.poll, poll.isOpen {
                    PollView(event: event, poll: poll, isOrganizer: isOrganizer) { updated in
                        self.event = updated
                        app.eventsChanged()
                    } onVote: { poll in
                        self.event = event.with(poll: .some(poll))
                    }
                }

                participantsSection

                if isParticipant { links(event) }

                if !event.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.wely.headline)
                        Text(event.description).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func header(_ event: FeedEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title).font(.wely.title2.bold())
            HStack(spacing: 8) {
                PersonChip(userId: event.organizerId, prefix: "Organisé par")
                if event.kind == .surprise {
                    Text("🤫 Surprise")
                        .font(.wely.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.gradient, in: Capsule())
                        .accessibilityLabel("Surprise : la personne fêtée ne voit pas cet événement")
                }
                if let visibility = event.visibility, visibility != .unknown {
                    Label(visibility.label, systemImage: visibility.systemImage)
                        .font(.wely.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
            if let communityId = event.communityId {
                NavigationLink(value: Route.community(communityId)) {
                    Label("Voir la communauté", systemImage: "person.3")
                        .font(.wely.subheadline.weight(.medium))
                }
            }
        }
    }

    @ViewBuilder
    private func primaryAction(_ event: FeedEvent) -> some View {
        if event.communityId != nil, !isOrganizer, let myId {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vous venez ?").font(.wely.headline)
                Picker("Réponse", selection: Binding(
                    get: { event.responses?.answer(of: myId) },
                    set: { answer in if let answer { Task { await respond(answer) } } }
                )) {
                    ForEach(PollAnswer.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
            }
        } else if isOrganizer {
            Label("Vous organisez", systemImage: "star.fill")
                .font(.wely.subheadline.bold())
                .foregroundStyle(Theme.orange)
        } else if isParticipant {
            HStack {
                Label("Inscrit", systemImage: "checkmark.circle.fill")
                    .font(.wely.headline)
                    .foregroundStyle(.green)
                Spacer()
                AsyncButton("Quitter", role: .destructive) { try await toggle() }
                    .buttonStyle(.welySecondary)
            }
        } else if !event.isPast, event.isJoinable {
            AsyncButton { try await toggle() } label: {
                Label("Rejoindre", systemImage: "person.badge.plus")
                    .font(.wely.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.welyPrimary)
        }
    }

    private func whenAndWhere(_ event: FeedEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if event.isOpenPoll {
                InfoRow(systemImage: "calendar.badge.clock", title: "La date n'est pas encore fixée", subtitle: "Votez pour vos créneaux ci-dessous")
            } else if event.allDay {
                InfoRow(systemImage: "calendar", title: AllDay.label(event.startDate, event.endDate), subtitle: nil)
            } else {
                InfoRow(systemImage: "calendar", title: Date.eventWhen(event.startDate, event.endDate),
                        subtitle: Calendar.wely.isDateInToday(event.startDate) ? "C'est aujourd'hui" : nil)
            }
            if !event.isOpenPoll, !event.isPast {
                addToCalendar(event)
            }
            if !event.location.isEmpty {
                InfoRow(systemImage: "mappin.and.ellipse", title: event.location, subtitle: nil)
            }
            if let coordinates = event.coordinates {
                let point = CLLocationCoordinate2D(latitude: coordinates.latitude, longitude: coordinates.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: point, latitudinalMeters: 800, longitudinalMeters: 800))) {
                    Marker(event.title, coordinate: point).tint(Theme.orange)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
                Button {
                    let item: MKMapItem
                    if #available(iOS 26, *) {
                        item = MKMapItem(location: CLLocation(latitude: point.latitude, longitude: point.longitude), address: nil)
                    } else {
                        item = MKMapItem(placemark: MKPlacemark(coordinate: point))
                    }
                    item.name = event.location
                    item.openInMaps()
                } label: {
                    Label("Itinéraire", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                .buttonStyle(.welySecondary)
            }
        }
    }

    /// A copy into the user's own agenda, once the date is fixed.
    private func addToCalendar(_ event: FeedEvent) -> some View {
        Menu {
            Button { addingToCalendar = true } label: {
                Label("Calendrier de l'iPhone", systemImage: "calendar.badge.plus")
            }
            Link(destination: CalendarExport.googleCalendarURL(event, eventURL: CalendarExport.eventURL(event))) {
                Label("Google Agenda", systemImage: "arrow.up.right.square")
            }
        } label: {
            Label("Ajouter à mon calendrier", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.welySecondary)
        .sheet(isPresented: $addingToCalendar) {
            AddToCalendarSheet(event: event).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var participantsSection: some View {
        if let participants {
            Button { showingParticipants = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(participants.count == 1 ? "1 participant" : "\(participants.count) participants").font(.wely.headline)
                        if !participants.friendsGoingIds.isEmpty {
                            Text("dont \(participants.friendsGoingIds.map { app.people.name($0) }.prefix(3).joined(separator: ", "))")
                                .font(.wely.caption).foregroundStyle(.secondary)
                        } else if participants.participantIds.isEmpty {
                            Text("Rejoignez pour voir qui vient").font(.wely.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    AvatarStack(userIds: participants.participantIds.isEmpty ? participants.friendsGoingIds : participants.participantIds)
                    Image(systemName: "chevron.right").font(.wely.caption).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private func links(_ event: FeedEvent) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: Route.eventChat(eventId: event.id, title: event.title)) {
                LinkRow(systemImage: "bubble.left.and.bubble.right.fill", title: "Fil du groupe", subtitle: "Discutez avec les participants")
            }
            Divider().padding(.leading, 52)
            NavigationLink(value: Route.expenses(event)) {
                LinkRow(systemImage: "eurosign.circle.fill", title: "Dépenses", subtitle: "Qui a payé quoi, qui doit combien")
            }
        }
        .buttonStyle(.plain)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        if isOrganizer {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { editing = true }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if let event {
                    ShareLink(item: AppConfig.current.webURL.appending(path: "event/\(event.id)")) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                }
                if isOrganizer {
                    if event?.image != nil {
                        Button(role: .destructive) { Task { await removeCover() } } label: { Label("Retirer la couverture", systemImage: "photo.badge.minus") }
                    }
                    Button { leaving = true } label: { Label("Quitter l'événement", systemImage: "rectangle.portrait.and.arrow.right") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Supprimer", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    private func load() async {
        if event == nil, let initial { event = initial }
        do {
            async let fresh = app.events.event(eventId)
            async let who = app.events.participants(eventId)
            event = try await fresh
            participants = try? await who
            loadError = nil
            if let event, !event.isOpenPoll { conflicts = (try? await app.events.conflicts(of: event.id)) ?? [] }
        } catch {
            if event == nil { loadError = error.localizedDescription }
        }
    }

    /// The poll's live votes, until it closes.
    private func followPoll() async {
        guard event?.isOpenPoll == true else { return }
        let stream = SSEClient.stream(url: app.events.pollStreamURL(eventId), session: app.session, finalStatuses: [403, 404, 410])
        for await message in stream where message.event == "poll" || message.event == "message" {
            guard let poll = try? JSONDecoder.wely.decode(Poll.self, from: Data(message.data.utf8)), let event else { continue }
            self.event = event.with(poll: .some(poll))
            if !poll.isOpen { await load(); break }
        }
    }

    private func toggle() async throws {
        event = try await app.events.toggleSubscription(eventId)
        participants = try? await app.events.participants(eventId)
        app.eventsChanged()
    }

    private func respond(_ answer: PollAnswer) async {
        do {
            event = try await app.events.respond(eventId, answer: answer)
            participants = try? await app.events.participants(eventId)
            app.eventsChanged()
        } catch { self.error = error.localizedDescription }
    }

    private func uploadCover(_ item: PhotosPickerItem) async {
        do {
            let jpeg = try await PhotoLoader.jpeg(from: item, maxSide: 1600)
            event = try await app.events.uploadCover(eventId, jpeg: jpeg)
        } catch { self.error = error.localizedDescription }
        coverItem = nil
    }

    private func removeCover() async {
        do {
            try await app.events.removeCover(eventId)
            event = event?.with(image: .some(nil))
        } catch { self.error = error.localizedDescription }
    }

    private func deleteEvent() async {
        do {
            try await app.events.delete(eventId)
            app.eventsChanged()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func handleLeave(_ result: LeaveResult) {
        app.eventsChanged()
        if result.deleted { dismiss() } else {
            event = result.event ?? event
            Task { participants = try? await app.events.participants(eventId) }
        }
    }
}

// MARK: Pieces

struct InfoRow: View {
    let systemImage: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.wely.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LinkRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.wely.title3)
                .foregroundStyle(Theme.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.wely.body.weight(.medium))
                Text(subtitle).font(.wely.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.wely.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

/// The proposed slots: each one's votes, the user's answers, and for the organizer the
/// button that fixes the date.
private struct PollView: View {
    @Environment(AppModel.self) private var app
    let event: FeedEvent
    let poll: Poll
    let isOrganizer: Bool
    let onFixed: (FeedEvent) -> Void
    let onVote: (Poll) -> Void
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sondage en cours", systemImage: "chart.bar.doc.horizontal")
                .font(.wely.headline)
            Text("Indiquez vos disponibilités pour chaque créneau.")
                .font(.wely.caption).foregroundStyle(.secondary)
            ForEach(poll.slots) { slot in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.start.dayLabel()).font(.wely.subheadline.weight(.semibold))
                            Text(Date.timeRange(slot.start, slot.end)).font(.wely.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("\(slot.yes.count)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Label("\(slot.maybe.count)", systemImage: "questionmark.circle.fill").foregroundStyle(Theme.orange)
                    }
                    .font(.wely.subheadline)
                    Picker("Ma réponse", selection: Binding(
                        get: { answer(for: slot) },
                        set: { vote(slot: slot, answer: $0) }
                    )) {
                        Text("—").tag(PollAnswer?.none)
                        ForEach(PollAnswer.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    if !slot.yes.isEmpty {
                        AvatarStack(userIds: slot.yes, limit: 6, size: 22)
                    }
                    if isOrganizer {
                        // A slot gone by while the poll stayed open: the date is fixed on one to come.
                        if slot.start < Date.now.addingTimeInterval(-PastDate.grace) {
                            Label("Créneau passé", systemImage: "clock.arrow.circlepath")
                                .font(.wely.caption.bold())
                                .foregroundStyle(Theme.ink2)
                        } else {
                            AsyncButton {
                                onFixed(try await app.events.fixDate(event.id, slotId: slot.id))
                            } label: {
                                Label("Fixer cette date", systemImage: "pin.fill").font(.wely.caption.bold())
                            }
                            .buttonStyle(.welySecondary)
                        }
                    }
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .errorAlert($error)
    }

    private func answer(for slot: PollSlot) -> PollAnswer? {
        guard let me = app.people.myId else { return nil }
        if slot.yes.contains(me) { return .yes }
        if slot.maybe.contains(me) { return .maybe }
        if slot.no.contains(me) { return .no }
        return nil
    }

    /// The ballot is the whole set of answers: the others are sent again with the new one.
    private func vote(slot: PollSlot, answer: PollAnswer?) {
        var answers: [String: PollAnswer] = [:]
        for other in poll.slots where other.id != slot.id {
            if let existing = self.answer(for: other) { answers[other.id] = existing }
        }
        if let answer { answers[slot.id] = answer }
        Task {
            do { onVote(try await app.events.vote(event.id, answers: answers)) } catch { self.error = error.localizedDescription }
        }
    }
}

private struct ParticipantsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let participants: EventParticipants
    let organizerId: String

    var body: some View {
        WelyNavigationStack {
            List {
                if participants.participantIds.isEmpty {
                    Section {
                        Text("Rejoignez l'événement pour voir qui vient.").foregroundStyle(.secondary)
                    }
                    if !participants.friendsGoingIds.isEmpty {
                        Section("Vos amis") {
                            ForEach(participants.friendsGoingIds, id: \.self) { id in
                                NavigationLink(value: Route.person(id)) { PersonRow(userId: id) }
                            }
                        }
                    }
                } else {
                    ForEach(participants.participantIds, id: \.self) { id in
                        NavigationLink(value: Route.person(id)) {
                            PersonRow(userId: id, subtitle: id == organizerId ? "Organisateur" : nil)
                        }
                    }
                }
            }
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .withRoutes()
        }
        .presentationDetents([.medium, .large])
    }
}

/// The organizer leaves: someone takes over, or the event goes when they were the last.
private struct LeaveSheet: View {
    @State private var failure: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let event: FeedEvent
    let participants: EventParticipants
    let onDone: (LeaveResult) -> Void
    @State private var successor: String?

    private var others: [String] { participants.participantIds.filter { $0 != event.organizerId } }

    var body: some View {
        WelyNavigationStack {
            Form {
                if others.isEmpty {
                    Section {
                        Text("Vous êtes le dernier participant : quitter supprimera l'événement.")
                    }
                    Section {
                        AsyncButton("Quitter et supprimer", role: .destructive) {
                            onDone(try await app.events.leave(event.id, choice: LeaveChoice(deleteIfLast: true)))
                            dismiss()
                        }
                    }
                } else {
                    Section("Qui reprend l'organisation ?") {
                        Picker("Nouvel organisateur", selection: $successor) {
                            Text("Choisir…").tag(String?.none)
                            ForEach(others, id: \.self) { Text(app.people.name($0)).tag(Optional($0)) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section {
                        AsyncButton("Passer la main et quitter", role: .destructive) {
                            onDone(try await app.events.leave(event.id, choice: LeaveChoice(newOrganizerId: successor)))
                            dismiss()
                        }
                        .disabled(successor == nil)
                    }
                }
            }
            .navigationTitle("Quitter")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The organizer rewrites the event: what, where, who sees it, and — once the date is fixed —
/// when. The details go through `PUT /events/{id}`, a new time through `/schedule`, which tells
/// the others in the group.
private struct EventEditSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    let event: FeedEvent
    let onSaved: (FeedEvent) -> Void

    @State private var title: String
    @State private var location: String
    @State private var coordinates: Coordinates?
    @State private var details: String
    @State private var visibility: Visibility
    @State private var start: Date
    @State private var end: Date
    @State private var conflicts: [FeedEvent] = []

    init(event: FeedEvent, onSaved: @escaping (FeedEvent) -> Void) {
        self.event = event
        self.onSaved = onSaved
        _title = State(initialValue: event.title)
        _location = State(initialValue: event.location)
        _coordinates = State(initialValue: event.coordinates)
        _details = State(initialValue: event.description)
        _visibility = State(initialValue: event.visibility ?? .friends)
        // An all-day event is edited by its days, read in UTC.
        _start = State(initialValue: event.allDay ? AllDay.localDay(of: event.startDate, calendar: .wely) : event.startDate)
        _end = State(initialValue: event.allDay ? AllDay.localDay(of: event.endDate.addingTimeInterval(-86_400), calendar: .wely) : event.endDate)
    }

    /// What the dates send: whole UTC days for an all-day event.
    private var range: (start: Date, end: Date) {
        event.allDay ? AllDay.range(from: start, through: end, calendar: .wely) : (start, end)
    }

    private var datesChanged: Bool { range.start != event.startDate || range.end != event.endDate }

    /// New dates already behind: said under them, and the save stays off.
    private var movesIntoPast: Bool {
        datesChanged && PastDate.isPast(start: start, end: end, allDay: event.allDay, calendar: .wely)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (event.kind == .surprise || !location.trimmingCharacters(in: .whitespaces).isEmpty)
            && (event.allDay || end > start)
            && !movesIntoPast
    }

    var body: some View {
        WelyNavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title).font(.wely.headline)
                }

                Section {
                    if event.isOpenPoll {
                        Label("La date se décide par le sondage : fixez un créneau depuis l'événement.", systemImage: "chart.bar.doc.horizontal")
                            .font(.wely.subheadline)
                            .foregroundStyle(.secondary)
                    } else if event.allDay {
                        DatePicker("Du", selection: $start, displayedComponents: .date)
                        DatePicker("Au", selection: $end, in: start..., displayedComponents: .date)
                    } else {
                        DatePicker("Début", selection: $start, in: Date.now...)
                        DatePicker("Fin", selection: $end, in: start...)
                    }
                } header: {
                    Text("Quand")
                } footer: {
                    if movesIntoPast {
                        Label(PastDate.message, systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.red)
                    } else if !conflicts.isEmpty {
                        Label("Chevauche \(conflicts.map(\.title).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if datesChanged {
                        Text("Les participants seront prévenus dans le fil du groupe.")
                    }
                }

                Section {
                    LocationField(label: $location, coordinates: $coordinates)
                } header: {
                    Text("Où")
                } footer: {
                    if event.kind != .surprise, location.trimmingCharacters(in: .whitespaces).isEmpty { Text("Le lieu est obligatoire.") }
                }

                Section("Description") {
                    TextField("Ce qui est prévu, quoi apporter…", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }

                if event.communityId == nil {
                    Section("Qui le voit") {
                        Picker("Visible par", selection: $visibility) {
                            ForEach(FeedEvent.choosableVisibilities, id: \.self) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                        }
                    }
                }
            }
            .environment(\.locale, .wely)
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Enregistrer") { try await save() }
                        .disabled(!isValid)
                }
            }
            .onChange(of: start) { old, new in end = end.addingTimeInterval(new.timeIntervalSince(old)) }
            .task(id: [start, end]) {
                guard datesChanged, !event.allDay else { conflicts = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                conflicts = (try? await app.events.conflicts(start: start, end: end, excluding: event.id)) ?? []
            }
        }
    }

    private func save() async throws {
        var updated = try await app.events.update(event.id, EventUpdateRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            location: location.trimmingCharacters(in: .whitespaces),
            coordinates: coordinates,
            description: details.isEmpty ? nil : details,
            visibility: event.communityId == nil ? visibility : nil
        ))
        if !event.isOpenPoll, datesChanged {
            updated = try await app.events.reschedule(event.id, start: range.start, end: range.end)
        }
        onSaved(updated)
        dismiss()
    }
}
