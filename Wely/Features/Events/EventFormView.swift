import SwiftUI

/// Creating an event: a fixed date or a date poll, a place, who sees it.
struct EventFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// Publishing in a community: set by the community screen, not chosen here.
    var communityId: String?
    let onCreated: (FeedEvent) -> Void

    @State private var title = ""
    @State private var isPoll = false
    @State private var start: Date
    @State private var end: Date
    @State private var slots: [EventCreateRequest.Slot]
    @State private var location = ""
    @State private var coordinates: Coordinates?
    @State private var details = ""
    @State private var visibility: Visibility = .friends
    @State private var publishIn: String?
    @State private var myCommunities: [Community] = []
    @State private var conflicts: [FeedEvent] = []
    @State private var findingSlot = false
    @State private var error: String?

    init(day: Date = .now, communityId: String? = nil, onCreated: @escaping (FeedEvent) -> Void) {
        self.communityId = communityId
        self.onCreated = onCreated
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

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !location.trimmingCharacters(in: .whitespaces).isEmpty && (isPoll ? (2...5).contains(slots.count) && slots.allSatisfy { $0.end > $0.start } : end > start)
    }

    var body: some View {
        WelyNavigationStack {
            Form {
                Section {
                    TextField("Titre (ex. Afterwork, Rando…)", text: $title)
                        .font(.wely.headline)
                }

                Section {
                    Picker("Date", selection: $isPoll) {
                        Text("Date fixe").tag(false)
                        Text("Sondage de dates").tag(true)
                    }
                    .pickerStyle(.segmented)

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
                        DatePicker("Début", selection: $start)
                        DatePicker("Fin", selection: $end, in: start...)
                        Button { findingSlot = true } label: {
                            Label("Trouver un créneau avec des amis", systemImage: "person.2.badge.gearshape")
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
                    if location.trimmingCharacters(in: .whitespaces).isEmpty {
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
            .navigationTitle("Nouvel événement")
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
                guard !isPoll else { return }
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
        let request = EventCreateRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: isPoll ? slots[0].start : start,
            endDate: isPoll ? slots[0].end : end,
            location: location.trimmingCharacters(in: .whitespaces),
            coordinates: coordinates,
            description: details.isEmpty ? nil : details,
            visibility: publishIn == nil ? visibility : nil,
            candidateSlots: isPoll ? slots : nil,
            communityId: publishIn
        )
        let created = try await app.events.create(request)
        onCreated(created)
        dismiss()
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
