import SwiftUI

/// Creating an event: a fixed date or a date poll, a place, who sees it.
struct EventFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// What a form opens with when something else prepared the event (a birthday surprise).
    struct Draft: Hashable, Identifiable {
        var kind: EventKind = .standard
        var honoreeId: String?
        var honoreeName: String?
        var title = ""
        var details = ""
        var start: Date
        var end: Date
        var visibility: Visibility = .friends

        var id: String { "\(kind.rawValue)#\(honoreeId ?? "")#\(start.timeIntervalSince1970)" }

        /// The surprise for a friend's birthday: 19:00 to 23:00 that day, place left to choose.
        static func surprise(for honoreeId: String, name: String, on day: Date, calendar: Calendar = .wely) -> Draft {
            let start = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? day
            let end = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day) ?? start.addingTimeInterval(4 * 3600)
            return Draft(kind: .surprise, honoreeId: honoreeId, honoreeName: name, title: "Anniversaire surprise de \(name) 🎉",
                         details: "🤫 \(name) ne voit pas cet événement. Invite ses amis et choisis le lieu.",
                         start: start, end: end, visibility: .friends)
        }
    }

    /// Publishing in a community: set by the community screen, not chosen here.
    var communityId: String?
    let onCreated: (FeedEvent) -> Void
    private let kind: EventKind
    private let honoreeId: String?
    private let honoreeName: String?

    @State private var title = ""
    @State private var isPoll = false
    @State private var allDay = false
    @State private var start: Date
    @State private var end: Date
    @State private var slots: [EventCreateRequest.Slot]
    @State private var location = ""
    @State private var coordinates: Coordinates?
    @State private var details = ""
    @State private var visibility: Visibility = .friends
    /// The surprise someone already prepares, after a 409.
    @State private var existingSurprise: String?
    @State private var publishIn: String?
    @State private var myCommunities: [Community] = []
    @State private var conflicts: [FeedEvent] = []
    @State private var findingSlot = false
    @State private var error: String?

    init(day: Date = .now, communityId: String? = nil, onCreated: @escaping (FeedEvent) -> Void) {
        self.communityId = communityId
        self.onCreated = onCreated
        kind = .standard
        honoreeId = nil
        honoreeName = nil
        let calendar = Calendar.wely
        // The chosen day at 19:00, or the next round hour when that is already past.
        var start = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day) ?? day
        if start < .now { start = calendar.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now }
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(2 * 3600))
        _slots = State(initialValue: [0, 1].map { offset in
            let s = calendar.date(byAdding: .day, value: offset, to: start)!
            return .init(start: s, end: s.addingTimeInterval(2 * 3600))
        })
        _publishIn = State(initialValue: communityId)
    }

    /// A pre-filled form: one press on « Créer » is enough.
    init(draft: Draft, onCreated: @escaping (FeedEvent) -> Void) {
        communityId = nil
        self.onCreated = onCreated
        kind = draft.kind
        honoreeId = draft.honoreeId
        honoreeName = draft.honoreeName
        _title = State(initialValue: draft.title)
        _details = State(initialValue: draft.details)
        _start = State(initialValue: draft.start)
        _end = State(initialValue: draft.end)
        _visibility = State(initialValue: draft.visibility)
        _slots = State(initialValue: [0, 1].map { offset in
            let s = draft.start.addingTimeInterval(Double(offset) * 86_400)
            return .init(start: s, end: s.addingTimeInterval(draft.end.timeIntervalSince(draft.start)))
        })
        _publishIn = State(initialValue: nil)
    }

    private var isSurprise: Bool { kind == .surprise }
    /// A surprise may go without a place for now: friends choose it together.
    private var needsLocation: Bool { !isSurprise }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (!needsLocation || !location.trimmingCharacters(in: .whitespaces).isEmpty)
            && (isPoll ? (2...5).contains(slots.count) && slots.allSatisfy { $0.end > $0.start } : allDay || end > start)
    }

    var body: some View {
        WelyNavigationStack {
            Form {
                Section {
                    TextField("Titre (ex. Afterwork, Rando…)", text: $title)
                        .font(.wely.headline)
                }

                if isSurprise {
                    Section {
                        Label("🤫 Surprise : \(honoreeName ?? "la personne fêtée") ne verra pas cet événement.", systemImage: "eye.slash")
                            .font(.wely.subheadline)
                            .foregroundStyle(Theme.ink2)
                    }
                }

                Section {
                    if !isSurprise {
                        Picker("Date", selection: $isPoll) {
                            Text("Date fixe").tag(false)
                            Text("Sondage de dates").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }

                    if isPoll {
                        // By position: editing a slot changes its value, so it cannot be its own id.
                        ForEach(slots.indices, id: \.self) { index in
                            VStack(alignment: .leading) {
                                DatePicker("Créneau \(index + 1)", selection: $slots[index].start)
                                DatePicker("Fin", selection: $slots[index].end, in: slots[index].start...)
                                    .font(.wely.caption)
                            }
                        }
                        .onDelete { indexSet in if slots.count > 2 { slots.remove(atOffsets: indexSet) } }
                        if slots.count < 5 {
                            Button {
                                let last = slots.last!
                                slots.append(.init(start: last.start.addingTimeInterval(86_400), end: last.end.addingTimeInterval(86_400)))
                            } label: {
                                Label("Proposer un autre créneau", systemImage: "plus.circle")
                            }
                        }
                    } else {
                        Toggle("Toute la journée", isOn: $allDay.animation())
                        if allDay {
                            DatePicker("Du", selection: $start, displayedComponents: .date)
                            DatePicker("Au", selection: $end, in: start..., displayedComponents: .date)
                        } else {
                            DatePicker("Début", selection: $start)
                            DatePicker("Fin", selection: $end, in: start...)
                            if !isSurprise {
                                Button { findingSlot = true } label: {
                                    Label("Trouver un créneau avec des amis", systemImage: "person.2.badge.gearshape")
                                }
                            }
                        }
                    }
                } footer: {
                    if isPoll {
                        Text("Proposez 2 à 5 créneaux : les invités votent, vous fixez la date ensuite.")
                    } else if !conflicts.isEmpty {
                        Label("Vous avez déjà : \(conflicts.map(\.title).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    LocationField(label: $location, coordinates: $coordinates)
                } header: {
                    Text("Où")
                } footer: {
                    if isSurprise {
                        Text("Facultatif : vous pourrez le choisir plus tard avec les autres.")
                    } else if location.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Le lieu est obligatoire : une adresse, un bar, « chez moi »…")
                    }
                }

                Section("Description") {
                    TextField("Ce qui est prévu, quoi apporter…", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                }

                if communityId == nil {
                    Section {
                        Picker("Publier", selection: $publishIn) {
                            Text("Mon cercle").tag(String?.none)
                            ForEach(myCommunities) { Text($0.name).tag(Optional($0.communityId)) }
                        }
                        if publishIn == nil {
                            Picker("Visible par", selection: $visibility) {
                                ForEach(FeedEvent.choosableVisibilities, id: \.self) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                            }
                        }
                    } header: {
                        Text("Qui le voit")
                    } footer: {
                        Text(publishIn != nil ? "Réservé aux membres de la communauté." : visibilityHint)
                    }
                }
            }
            .environment(\.locale, .wely)
            .navigationTitle(isSurprise ? "Anniversaire surprise" : "Nouvel événement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Créer") { try await create() }
                        .disabled(!isValid)
                }
            }
            .onChange(of: start) { old, new in end = end.addingTimeInterval(new.timeIntervalSince(old)) }
            .task { myCommunities = (try? await app.social.myCommunities()) ?? [] }
            .task(id: [start, end]) {
                guard !isPoll, !allDay else { conflicts = []; return }
                try? await Task.sleep(for: .milliseconds(300))
                conflicts = (try? await app.events.conflicts(start: start, end: end)) ?? []
            }
            .sheet(isPresented: $findingSlot) {
                FreeSlotFinder(duration: end.timeIntervalSince(start)) { range in
                    let duration = end.timeIntervalSince(start)
                    start = range.start
                    end = range.start.addingTimeInterval(duration)
                }
            }
            .errorAlert($error)
            .alert("Une surprise se prépare déjà", isPresented: Binding(get: { existingSurprise != nil }, set: { if !$0 { existingSurprise = nil } })) {
                Button("Rejoindre la surprise") { Task { await joinExisting() } }
                Button("Voir la surprise") { openExisting() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Un ami organise déjà l'anniversaire de \(honoreeName ?? "cette personne"). Rejoins-le, \(honoreeName ?? "la personne fêtée") n'en saura rien.")
            }
        }
    }

    private var visibilityHint: String {
        switch visibility {
        case .public: "Tout le monde peut le voir et le rejoindre."
        case .private: "Seuls les participants le voient."
        default: "Vos amis le voient dans leur fil."
        }
    }

    private func create() async throws {
        let wholeDays = !isPoll && allDay
        let days = AllDay.range(from: start, through: end, calendar: .wely)
        let request = EventCreateRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: isPoll ? slots[0].start : (wholeDays ? days.start : start),
            endDate: isPoll ? slots[0].end : (wholeDays ? days.end : end),
            location: location.trimmingCharacters(in: .whitespaces),
            coordinates: coordinates,
            description: details.isEmpty ? nil : details,
            visibility: publishIn == nil ? visibility : nil,
            candidateSlots: isPoll ? slots : nil,
            communityId: publishIn,
            allDay: wholeDays ? true : nil,
            kind: kind == .standard ? nil : kind,
            honoreeId: honoreeId
        )
        do {
            let created = try await app.events.create(request)
            onCreated(created)
            dismiss()
        } catch let error as APIError where isSurprise && error.status == 409 && error.eventId != nil {
            existingSurprise = error.eventId
        }
    }

    /// Joins the surprise a friend already created, then shows it.
    private func joinExisting() async {
        guard let id = existingSurprise else { return }
        do {
            let participants = try? await app.events.participants(id)
            if participants?.participantIds.contains(app.people.myId ?? "") != true {
                _ = try await app.events.toggleSubscription(id)
            }
            app.eventsChanged()
            openExisting()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openExisting() {
        guard let id = existingSurprise else { return }
        existingSurprise = nil
        dismiss()
        app.open(.event(id))
    }
}

/// Picks friends, a period and a duration, then lists when everyone is free.
private struct FreeSlotFinder: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let duration: TimeInterval
    let onPick: (FreeRange) -> Void

    @State private var friends: [UserNode] = []
    @State private var selected: Set<String> = []
    @State private var from = Calendar.wely.startOfDay(for: .now)
    @State private var to = Calendar.wely.date(byAdding: .day, value: 14, to: .now)!
    @State private var ranges: [FreeRange]?

    var body: some View {
        WelyNavigationStack {
            Form {
                Section("Avec qui") {
                    ForEach(friends) { friend in
                        Button {
                            if selected.contains(friend.userId) { selected.remove(friend.userId) } else { selected.insert(friend.userId) }
                        } label: {
                            PersonRow(userId: friend.userId) {
                                Image(systemName: selected.contains(friend.userId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(friend.userId) ? Theme.blue : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Quand") {
                    DatePicker("Du", selection: $from, displayedComponents: .date)
                    DatePicker("Au", selection: $to, in: from..., displayedComponents: .date)
                }
                Section {
                    AsyncButton("Chercher les créneaux libres") {
                        ranges = try await app.events.freeSlots(FreeSlotSearch(friendIds: Array(selected), start: from, end: to,
                                                                               durationMinutes: max(30, Int(duration / 60))))
                    }
                    .disabled(selected.isEmpty)
                }
                if let ranges {
                    Section("Tout le monde est libre") {
                        if ranges.isEmpty { Text("Aucun créneau commun sur cette période.").foregroundStyle(.secondary) }
                        ForEach(ranges, id: \.self) { range in
                            Button {
                                onPick(range)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(range.start.dayLabel())
                                    Text(Date.timeRange(range.start, range.end)).font(.wely.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .environment(\.locale, .wely)
            .navigationTitle("Trouver un créneau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task {
                friends = (try? await app.social.friends()) ?? []
                app.people.remember(friends.map(\.person))
            }
        }
    }
}
