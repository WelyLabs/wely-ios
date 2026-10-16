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
    let app: AppModel
    @State private var model: CalendarModel
    @State private var path = NavigationPath()
    @State private var creating = false

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
                    DayAgendaView(model: model)
                }
            }
            .refreshable { await model.load() }
            .navigationTitle("Calendrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Aujourd'hui") { withAnimation { model.goToToday() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Nouvel événement")
                }
            }
            .notificationsToolbar()
            .withRoutes()
            .sheet(isPresented: $creating) {
                EventFormView(day: model.selectedDay) { created in
                    app.eventsChanged()
                    model.select(created.startDate)
                }
            }
            .task(id: app.eventsVersion) { await model.load() }
            .task(id: app.people.myId) { if app.people.myId != nil { await model.load() } }
            .handlesDestinations(on: .calendar, path: $path)
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
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.day()))
                .font(.wely.callout.weight(isToday || isSelected ? .bold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(isToday ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary))
                    } else if isToday {
                        Circle().strokeBorder(Theme.blue, lineWidth: 1.5)
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
        switch entries.count {
        case 0: return date
        case 1: return "\(date), 1 événement"
        default: return "\(date), \(entries.count) événements"
        }
    }
}

/// The selected day's events, or why there are none.
private struct DayAgendaView: View {
    let model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.wely)).capitalized)
                .font(.wely.headline)
                .padding(.horizontal)
                .padding(.top, 12)

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
                    Text("Rien de prévu ce jour-là.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 8) {
                        ForEach(entries) { entry in
                            NavigationLink(value: Route.event(entry.event)) {
                                EventRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 24)
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
                Text(Date.timeRange(entry.start, entry.end))
                    .font(.wely.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.tentative ? "? \(entry.title)" : entry.title)
                    .font(.wely.body.weight(.semibold))
                    .italic(entry.tentative)
                    .lineLimit(2)
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
