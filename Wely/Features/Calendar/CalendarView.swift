import SwiftUI

/// The month at a glance, with the selected day's events underneath — the phone layout of
/// wely-web's calendar.
struct CalendarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        CalendarScreen(app: app)
    }
}

private struct CalendarScreen: View {
    /// One sheet at a time: a birthday turns into its surprise form in place.
    enum Sheet: Identifiable {
        case create(Date)
        case birthday(BirthdayOccurrence)
        case surprise(EventFormView.Draft)

        var id: String {
            switch self {
            case .create(let day): "create-\(day.timeIntervalSince1970)"
            case .birthday(let occurrence): "birthday-\(occurrence.id)"
            case .surprise(let draft): "surprise-\(draft.id)"
            }
        }
    }

    let app: AppModel
    @State private var model: CalendarModel
    @State private var path = NavigationPath()
    @State private var sheet: Sheet?

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: CalendarModel(events: app.events, myId: { [weak app] in app?.people.myId }))
    }

    var body: some View {
        WelyNavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    MonthHeader(model: model)
                    MonthGridView(model: model)
                        .padding(.horizontal, 8)
                        .gesture(swipeBetweenMonths)
                    Divider().padding(.top, 8)
                    DayAgendaView(model: model) { sheet = .birthday($0) }
                }
            }
            .refreshable {
                async let birthdays: Void = model.loadBirthdays()
                await model.load()
                await birthdays
            }
            .navigationTitle("Calendrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Aujourd'hui") { withAnimation { model.goToToday() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .create(model.selectedDay) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Nouvel événement")
                }
            }
            .notificationsToolbar()
            .withRoutes()
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .create(let day):
                    EventFormView(day: day) { created in
                        app.eventsChanged()
                        model.select(created.allDay ? AllDay.localDay(of: created.startDate, calendar: model.calendar) : created.startDate)
                    }
                case .birthday(let occurrence):
                    BirthdaySheet(occurrence: occurrence) { action in handle(action, for: occurrence) }
                case .surprise(let draft):
                    EventFormView(draft: draft) { created in
                        app.eventsChanged()
                        model.select(created.startDate)
                        path.append(Route.event(created))
                    }
                }
            }
            .task(id: app.eventsVersion) {
                async let birthdays: Void = model.loadBirthdays()
                await model.load()
                await birthdays
            }
            .task(id: app.people.myId) { if app.people.myId != nil { await model.load() } }
            .task(id: model.displayedMonth) { await model.loadBirthdays() }
            .onChange(of: app.calendarRequest, initial: true) { _, request in
                guard let request else { return }
                app.calendarRequest = nil
                Task { await open(request) }
            }
            .handlesDestinations(on: .calendar, path: $path)
        }
    }

    private func handle(_ action: BirthdaySheet.Action, for occurrence: BirthdayOccurrence) {
        switch action {
        case .organize:
            guard let day = occurrence.day(in: model.calendar) else { return }
            sheet = .surprise(.surprise(for: occurrence.userId, name: occurrence.name, on: day, calendar: model.calendar))
        case .open(let eventId):
            sheet = nil
            path.append(Route.eventId(eventId))
        case .message(let friendId):
            sheet = nil
            path.append(Route.directChat(friendId: friendId))
        }
    }

    /// A link to a day, or to the surprise for a friend's birthday.
    private func open(_ request: AppDestination) async {
        switch request {
        case .calendarDay(let date):
            path = NavigationPath()
            withAnimation { model.select(dayString: date) }
        case .surprise(let honoreeId, let date):
            path = NavigationPath()
            model.select(dayString: date)
            guard let day = DayString.date(from: date, calendar: model.calendar) else { return }
            await model.loadBirthdays()
            let birthday = model.birthdays(on: day).first { $0.userId == honoreeId }
            // Someone was quicker: show their surprise rather than a form that would 409.
            if let surprise = birthday?.surprise {
                path.append(Route.eventId(surprise.eventId))
                return
            }
            let name = birthday?.name ?? app.people.person(honoreeId).name
            sheet = .surprise(.surprise(for: honoreeId, name: name, on: day, calendar: model.calendar))
        default:
            break
        }
    }

    private var swipeBetweenMonths: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            withAnimation { model.showMonth(offset: value.translation.width < 0 ? 1 : -1) }
        }
    }
}

/// « Octobre 2026 » with the arrows to move between months.
private struct MonthHeader: View {
    let model: CalendarModel

    var body: some View {
        HStack {
            Text(model.displayedMonth.formatted(.dateTime.month(.wide).year().locale(.wely)).capitalized)
                .font(.wely.title2.bold())
                .contentTransition(.numericText())
            Spacer()
            Button { withAnimation { model.showMonth(offset: -1) } } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Mois précédent")
            Button { withAnimation { model.showMonth(offset: 1) } } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Mois suivant")
        }
        .font(.wely.body.weight(.semibold))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// Seven columns of days; each marks up to three events with a dot.
private struct MonthGridView: View {
    let model: CalendarModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let grid = model.grid
        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 0) {
                // By position: « M » is both mardi and mercredi.
                let symbols = MonthGrid.weekdaySymbols(calendar: model.calendar)
                ForEach(symbols.indices, id: \.self) { index in
                    Text(symbols[index].uppercased())
                        .font(.wely.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(grid.days) { day in
                    DayCell(
                        day: day,
                        entries: model.entries(on: day.date),
                        birthdays: model.birthdays(on: day.date),
                        isToday: model.calendar.isDateInToday(day.date),
                        isSelected: model.calendar.isDate(day.date, inSameDayAs: model.selectedDay)
                    )
                    .onTapGesture { withAnimation(.snappy) { model.select(day.date) } }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: MonthGrid.Day
    let entries: [CalendarEntry]
    let birthdays: [BirthdayOccurrence]
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        let style = BirthdayStyle.strongest(of: birthdays)
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.wely.callout.weight(isToday || isSelected || style == .mine ? .bold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(isToday ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary))
                    } else if isToday {
                        Circle().strokeBorder(Theme.blue, lineWidth: 1.5)
                    }
                }
                // Behind the selection: the glow and the ring show around it.
                .background {
                    if let style { BirthdayDayMark(style: style, isSelected: isSelected) }
                }
                .overlay(alignment: .topTrailing) {
                    if let style {
                        Text(style.emoji)
                            .font(.system(size: 11))
                            .opacity(style == .friend ? 0.7 : 1)
                            .offset(x: 6, y: -4)
                    }
                }
            HStack(spacing: 3) {
                ForEach(entries.prefix(3)) { entry in
                    Circle()
                        .fill(Theme.color(for: entry))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(Rectangle())
        .opacity(day.isCurrentMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var numberColor: Color {
        if isSelected { return Color(.systemBackground) }
        return isToday ? Theme.blue : .primary
    }

    private var accessibilityText: String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.wely))
        let names = birthdays.map { $0.mine ? "votre anniversaire" : "anniversaire de \($0.name)" }
        let parts = [date] + names
        switch entries.count {
        case 0: return parts.joined(separator: ", ")
        case 1: return (parts + ["1 événement"]).joined(separator: ", ")
        default: return (parts + ["\(entries.count) événements"]).joined(separator: ", ")
        }
    }
}

/// The selected day's birthdays and events, or why there are none.
private struct DayAgendaView: View {
    let model: CalendarModel
    let onBirthday: (BirthdayOccurrence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.wely)).capitalized)
                .font(.wely.headline)
                .padding(.horizontal)
                .padding(.top, 12)

            let birthdays = model.selectedBirthdays
            if !birthdays.isEmpty {
                VStack(spacing: 8) {
                    ForEach(birthdays) { birthday in
                        if birthday.mine, model.calendar.isDateInToday(model.selectedDay) {
                            BirthdayBanner(name: birthday.name)
                        } else {
                            Button { onBirthday(birthday) } label: { BirthdayCard(occurrence: birthday) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
            }

            switch model.phase {
            case .loading where model.entries.isEmpty:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
            case .failed(let message) where model.entries.isEmpty:
                EmptyStateView(title: "Calendrier indisponible", systemImage: "wifi.exclamationmark", message: message) {
                    Button("Réessayer") { Task { await model.load() } }
                        .buttonStyle(.welyPrimary)
                }
            default:
                let entries = model.selectedEntries
                if entries.isEmpty {
                    if birthdays.isEmpty {
                        Text("Rien de prévu ce jour-là.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                } else {
                    let allDay = entries.filter(\.isAllDay)
                    let timed = entries.filter { !$0.isAllDay }
                    VStack(alignment: .leading, spacing: 8) {
                        if !allDay.isEmpty {
                            Text("Toute la journée")
                                .font(.wely.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            rows(allDay)
                            if !timed.isEmpty { Divider().padding(.vertical, 4) }
                        }
                        rows(timed)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func rows(_ entries: [CalendarEntry]) -> some View {
        ForEach(entries) { entry in
            NavigationLink(value: Route.event(entry.event)) {
                EventRow(entry: entry)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One event of the day: a colour bar, the time, the title and where.
struct EventRow: View {
    let entry: CalendarEntry

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.color(for: entry))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.isAllDay ? "Toute la journée" : Date.timeRange(entry.start, entry.end))
                    .font(.wely.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(entry.tentative ? "? \(entry.title)" : entry.title)
                        .font(.wely.body.weight(.semibold))
                        .italic(entry.tentative)
                        .lineLimit(2)
                    if entry.event.kind == .surprise {
                        Text("🤫 Surprise")
                            .font(.wely.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.gradient, in: Capsule())
                    }
                }
                if !entry.event.location.isEmpty {
                    Label(entry.event.location, systemImage: "mappin.and.ellipse")
                        .font(.wely.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if entry.tentative {
                    Text("Date proposée · sondage en cours")
                        .font(.wely.caption2.weight(.medium))
                        .foregroundStyle(Theme.orange)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.wely.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if entry.tentative {
                RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    #if DEBUG
    let app = AppModel.demo()
    CalendarView().environment(app).environment(app.session)
    #endif
}
