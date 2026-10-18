import PhotosUI
import SwiftUI

// MARK: Avatars

/// A round picture, or initials on a stable colour per person — as wely-web's avatars.
struct AvatarView: View {
    @Environment(AppModel.self) private var app
    let userId: String
    var size: CGFloat = 40

    private static let colors: [Color] = [
        Color(red: 0.145, green: 0.388, blue: 0.922), Color(red: 0.761, green: 0.255, blue: 0.047),
        Color(red: 0.059, green: 0.463, blue: 0.431), Color(red: 0.486, green: 0.227, blue: 0.929),
        Color(red: 0.745, green: 0.094, blue: 0.365), Color(red: 0.302, green: 0.486, blue: 0.059),
    ]

    var body: some View {
        let person = app.people.person(userId)
        ZStack {
            Circle().fill(Self.color(for: userId))
            Text(Person.initials(of: person.name))
                .font(.wely.fixed(size * 0.38, .semibold))
                .foregroundStyle(.white)
            if let url = app.people.picture(userId) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func color(for id: String) -> Color {
        var hash: Int32 = 0
        for scalar in id.unicodeScalars { hash = hash &* 31 &+ Int32(truncatingIfNeeded: scalar.value) }
        return colors[Int(abs(Int(hash))) % colors.count]
    }
}

/// Up to `limit` overlapping avatars and « +N ».
struct AvatarStack: View {
    let userIds: [String]
    var limit = 5
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(userIds.prefix(limit), id: \.self) { id in
                AvatarView(userId: id, size: size)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
            }
            if userIds.count > limit {
                Text("+\(userIds.count - limit)")
                    .font(.wely.caption2.bold())
                    .foregroundStyle(Theme.ink2)
                    .frame(width: size, height: size)
                    .background(Theme.subtle, in: Circle())
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
            }
        }
    }
}

/// An avatar, a name and a line under it.
struct PersonRow<Trailing: View>: View {
    @Environment(AppModel.self) private var app
    let userId: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(userId: userId, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.people.person(userId).name).font(.wely.body.weight(.medium))
                Text(subtitle ?? app.people.person(userId).handle)
                    .font(.wely.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension PersonRow where Trailing == EmptyView {
    init(userId: String, subtitle: String? = nil) {
        self.init(userId: userId, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: Events

/// An event as a card: cover or gradient, date block, title, where, who.
struct EventCard: View {
    @Environment(AppModel.self) private var app
    let event: FeedEvent
    var participants: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                EventCover(event: event, height: 130)
                DateBadge(date: event.startDate, tentative: event.isOpenPoll)
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.wely.title3)
                    .lineLimit(2)
                Label(event.isOpenPoll ? "Date en cours de sondage" : event.startDate.formatted(.dateTime.weekday(.wide).hour().minute().locale(.wely)).capitalized,
                      systemImage: event.isOpenPoll ? "chart.bar.doc.horizontal" : "clock")
                    .font(.wely.subheadline)
                    .foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse")
                        .font(.wely.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                FriendsGoingRow(event: event)
                HStack {
                    PersonChip(userId: event.organizerId, prefix: "par")
                    Spacer()
                    if let visibility = event.visibility, visibility != .unknown {
                        Image(systemName: visibility.systemImage)
                            .font(.wely.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(visibility.label)
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

/// « par Léa » with her avatar.
struct PersonChip: View {
    @Environment(AppModel.self) private var app
    let userId: String
    var prefix: String?

    var body: some View {
        HStack(spacing: 6) {
            AvatarView(userId: userId, size: 20)
            Text([prefix, userId == app.people.myId ? (prefix == nil ? "Vous" : "vous") : app.people.name(userId)].compactMap { $0 }.joined(separator: " "))
                .font(.wely.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct EventCover: View {
    let event: FeedEvent
    var height: CGFloat = 180

    var body: some View {
        Group {
            if let url = AppConfig.current.imageURL(event.image) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    EventTint.gradient(for: event.id).opacity(0.4)
                }
            } else {
                EventTint.gradient(for: event.id)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: EventTint.symbol(for: event.title))
                            .font(.system(size: height * 0.35, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(12)
                    }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// A coverless event's colours, stable per event, and a symbol guessed from its title.
enum EventTint {
    private static let pairs: [(Color, Color)] = [
        (Theme.gradientStops[0], Theme.gradientStops[4]), (Color(red: 0.06, green: 0.46, blue: 0.43), Color(red: 0.40, green: 0.80, blue: 0.60)),
        (Color(red: 0.49, green: 0.23, blue: 0.93), Color(red: 0.93, green: 0.36, blue: 0.62)),
        (Color(red: 0.76, green: 0.25, blue: 0.05), Color(red: 0.98, green: 0.70, blue: 0.20)),
    ]

    static func gradient(for id: String) -> LinearGradient {
        let pair = pairs[Int(abs(Int(AvatarView.hash(id)))) % pairs.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func symbol(for title: String) -> String {
        let t = title.lowercased()
        let table: [(String, String)] = [
            ("ciné", "film"), ("film", "film"), ("concert", "music.note"), ("musique", "music.note"), ("escalade", "figure.climbing"),
            ("rando", "figure.hiking"), ("vélo", "bicycle"), ("foot", "soccerball"), ("brunch", "cup.and.saucer"), ("café", "cup.and.saucer"),
            ("resto", "fork.knife"), ("dîner", "fork.knife"), ("pique-nique", "basket"), ("jeux", "dice"), ("afterwork", "wineglass"),
            ("bar", "wineglass"), ("anniv", "gift"), ("voyage", "airplane"), ("week-end", "suitcase"), ("plage", "beach.umbrella"),
            ("rallye", "car"), ("auto", "car"), ("sport", "figure.run"),
        ]
        return table.first { t.contains($0.0) }?.1 ?? "sparkles"
    }
}

extension AvatarView {
    static func hash(_ id: String) -> Int32 {
        var hash: Int32 = 0
        for scalar in id.unicodeScalars { hash = hash &* 31 &+ Int32(truncatingIfNeeded: scalar.value) }
        return hash
    }
}

/// « 15 OCT » in a white tile.
struct DateBadge: View {
    let date: Date
    var tentative = false

    var body: some View {
        VStack(spacing: 0) {
            Text(tentative ? "?" : date.formatted(.dateTime.day()))
                .font(.wely.fixed(20, .bold))
                .foregroundStyle(Theme.ink)
            Text(tentative ? "SONDAGE" : date.formatted(.dateTime.month(.abbreviated).locale(.wely)).uppercased().replacingOccurrences(of: ".", with: ""))
                .font(.wely.fixed(9, .bold))
                .foregroundStyle(Theme.orange)
        }
        .frame(minWidth: 46, minHeight: 46)
        .padding(.horizontal, 4)
        .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

// MARK: States

/// Wely's empty or failed screen: the symbol in a soft gradient disc, a title, a line, actions.
struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.gradient)
                .frame(width: 76, height: 76)
                .background(Theme.gradient.opacity(0.12), in: Circle())
            Text(title)
                .font(.wely.title3)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.wely.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
            }
            actions().padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, systemImage: String, message: String? = nil) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// A section's title above its card, as wely-web's: small, semibold, in the soft ink.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.wely.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink2)
            .textCase(.uppercase)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A screen's load: loading, the value, or why not.
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// Shows a `Loadable`: a spinner, the content, or the error with a retry.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var retry: (() async -> Void)?
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 40)
        case .loaded(let value):
            content(value)
        case .failed(let message):
            EmptyStateView(title: "Impossible de charger", systemImage: "wifi.exclamationmark", message: message) {
                if let retry {
                    Button("Réessayer") { Task { await retry() } }.buttonStyle(.welyPrimary)
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Where a nested `AsyncButton` reports its failure: the screen's alert. Without it, the
    /// button shows its own — which never appears from a toolbar item.
    @Entry var reportError: ReportErrorAction?
}

/// What `reportError` holds: a closure in a struct, compared by the screen that set it, so the
/// buttons reading it are not invalidated on every update.
struct ReportErrorAction: Equatable {
    let id: UUID
    let handler: (String) -> Void

    func callAsFunction(_ message: String) { handler(message) }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

/// A failed action's message, shown as an alert; nested `AsyncButton`s report here.
struct ErrorAlert: ViewModifier {
    @Binding var message: String?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.reportError, ReportErrorAction(id: id) { message = $0 })
            .alert("Oups", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View { modifier(ErrorAlert(message: message)) }
}

/// A button that runs async work, shows a spinner meanwhile and reports a failure.
struct AsyncButton<Label: View>: View {
    var role: ButtonRole?
    let action: () async throws -> Void
    @ViewBuilder let label: () -> Label
    @State private var running = false
    @State private var error: String?
    @Environment(\.reportError) private var reportError

    var body: some View {
        Button(role: role) {
            running = true
            Task {
                defer { running = false }
                do {
                    try await action()
                } catch {
                    if let reportError { reportError(error.localizedDescription) } else { self.error = error.localizedDescription }
                }
            }
        } label: {
            if running { ProgressView() } else { label() }
        }
        .disabled(running)
        .errorAlert($error)
    }
}

extension AsyncButton where Label == Text {
    init(_ title: String, role: ButtonRole? = nil, action: @escaping () async throws -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

/// A capsule of text: an interest, a tag.
struct TagView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.wely.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.blue.opacity(0.1), in: Capsule())
            .foregroundStyle(Theme.primary)
    }
}

/// Lays out tags in lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: Photos

enum PhotoLoader {
    /// A picked photo as a JPEG at most `maxSide` pixels wide or high.
    static func jpeg(from item: PhotosPickerItem, maxSide: CGFloat = 1600) async throws -> Data {
        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { throw CocoaError(.fileWriteUnknown) }
        return jpeg
    }
}

// MARK: Dates

extension Date {
    /// « il y a 5 min », « 14:32 », « hier », « 12 oct. ».
    func relativeShort(now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(self) / 60)
        let calendar = Calendar.wely
        if minutes < 1 { return "À l'instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        if calendar.isDateInToday(self) { return formatted(.dateTime.hour().minute().locale(.wely)) }
        if calendar.isDateInYesterday(self) { return "Hier" }
        return formatted(.dateTime.day().month(.abbreviated).locale(.wely))
    }

    /// « Aujourd'hui », « Hier », « Lundi 12 octobre ».
    func dayLabel(now: Date = .now) -> String {
        let calendar = Calendar.wely
        if calendar.isDate(self, inSameDayAs: now) { return "Aujourd'hui" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(self, inSameDayAs: yesterday) { return "Hier" }
        let sameYear = calendar.isDate(self, equalTo: now, toGranularity: .year)
        let style = sameYear ? formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.wely))
                             : formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.wely))
        return style.prefix(1).uppercased() + style.dropFirst()
    }

    /// « Samedi 17 octobre · 18:30 – 20:30 ».
    static func eventWhen(_ start: Date, _ end: Date) -> String {
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.wely))
        return "\(day.prefix(1).uppercased() + day.dropFirst()) · \(timeRange(start, end))"
    }
}
