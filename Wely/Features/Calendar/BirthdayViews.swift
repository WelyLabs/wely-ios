import SwiftUI

/// What sits behind a day's number when someone celebrates: a warm glow for the user's own
/// birthday, a shimmering gradient ring for an intimate friend, an orange tint for a close one.
struct BirthdayDayMark: View {
    let style: BirthdayStyle
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch style {
        case .mine:
            Circle()
                .fill(Theme.gradient)
                .opacity(isSelected ? 0.5 : 0.35)
                .blur(radius: 5)
                .padding(-4)
        case .intimate:
            ShimmerRing(lineWidth: 2, paused: reduceMotion)
                .padding(-2.5)
        case .close:
            Circle().fill(Theme.orange.opacity(0.16))
        case .friend:
            Circle().fill(Color.secondary.opacity(0.08))
        }
    }
}

/// A ring in the brand gradient whose light slowly goes round; still under reduced motion.
struct ShimmerRing: View {
    var lineWidth: CGFloat = 2
    var paused = false
    var period: TimeInterval = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            let turn = paused ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            Circle()
                .strokeBorder(
                    AngularGradient(colors: Theme.gradientStops + [Theme.gradientStops[0]], center: .center, angle: .degrees(turn * 360)),
                    lineWidth: lineWidth
                )
        }
    }
}

/// A birthday at the top of the day's agenda.
struct BirthdayCard: View {
    let occurrence: BirthdayOccurrence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = occurrence.style
        HStack(spacing: 12) {
            Text(style.emoji)
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(badgeFill(style), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.mine ? "Ton anniversaire" : "Anniversaire de \(occurrence.name)")
                    .font(.wely.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.wely.caption)
                    .foregroundStyle(style == .close ? Theme.orange : Theme.ink2)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if !occurrence.mine {
                Image(systemName: "chevron.right")
                    .font(.wely.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(background(style), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            switch style {
            case .mine:
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.gradient, lineWidth: 1.5)
            case .intimate:
                ShimmerBorder(cornerRadius: 12, paused: reduceMotion)
            case .close, .friend:
                EmptyView()
            }
        }
        .shadow(color: style == .mine ? Theme.orange.opacity(0.25) : .clear, radius: 10, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityHint(occurrence.mine ? "" : "Ouvre l'anniversaire")
    }

    private var subtitle: String {
        if occurrence.mine { return "🎂 \(occurrence.dayLabel)" }
        if let surprise = occurrence.surprise {
            return surprise.joined ? "🤫 Tu fais partie de la surprise" : "🤫 Une surprise se prépare, rejoins-la"
        }
        if occurrence.canOrganize { return "Organise-lui une surprise, \(occurrence.name) n'en saura rien" }
        return "Un petit mot lui ferait plaisir."
    }

    private func badgeFill(_ style: BirthdayStyle) -> AnyShapeStyle {
        switch style {
        case .mine, .intimate: AnyShapeStyle(Theme.gradient.opacity(0.2))
        case .close: AnyShapeStyle(Theme.orange.opacity(0.18))
        case .friend: AnyShapeStyle(Color.secondary.opacity(0.1))
        }
    }

    private func background(_ style: BirthdayStyle) -> AnyShapeStyle {
        switch style {
        case .close: AnyShapeStyle(Theme.orange.opacity(0.08))
        case .mine, .intimate, .friend: AnyShapeStyle(Theme.card)
        }
    }
}

/// A rounded border in the brand gradient with a slow travelling light.
private struct ShimmerBorder: View {
    let cornerRadius: CGFloat
    var paused = false
    var period: TimeInterval = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            let turn = paused ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    AngularGradient(colors: Theme.gradientStops + [Theme.gradientStops[0]], center: .center, angle: .degrees(turn * 360)),
                    lineWidth: 1.5
                )
        }
    }
}

/// « Joyeux anniversaire », on the user's own day, with a few confetti falling.
struct BirthdayBanner: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Joyeux anniversaire, \(name) ! 🎂")
                .font(.wely.title3.bold())
            Text("Toute la bande Wely te souhaite une magnifique journée.")
                .font(.wely.subheadline)
                .opacity(0.92)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16))
        .overlay { ConfettiView().clipShape(RoundedRectangle(cornerRadius: 16)).allowsHitTesting(false) }
        .shadow(color: Theme.orange.opacity(0.3), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }
}

/// Light confetti drifting down for a few seconds; scattered and still under reduced motion.
struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date.now
    @State private var finished = false

    private static let count = 26
    private static let duration: TimeInterval = 8
    private static let colors: [Color] = [.white, .white.opacity(0.8), Color(hex: 0xFDE68A), Color(hex: 0xBFDBFE), Color(hex: 0xFBCFE8)]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || finished)) { context in
            Canvas { canvas, size in
                let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(started)
                for index in 0..<Self.count {
                    let seed = Double(index)
                    let speed = 22 + fraction(seed * 3.1) * 26
                    let x = fraction(seed * 7.3) * size.width + sin(elapsed * 1.4 + seed) * 6
                    let span = size.height + 20
                    let y = (fraction(seed * 1.7) * span + elapsed * speed).truncatingRemainder(dividingBy: span) - 10
                    let side = 3 + fraction(seed * 5.9) * 4
                    var piece = canvas
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(elapsed * 90 * (index.isMultiple(of: 2) ? 1 : -1) + seed * 40))
                    piece.opacity = finished ? 0.55 : 0.9
                    piece.fill(Path(CGRect(x: -side / 2, y: -side / 4, width: side, height: side / 2)),
                               with: .color(Self.colors[index % Self.colors.count]))
                }
            }
        }
        .task {
            started = .now
            try? await Task.sleep(for: .seconds(Self.duration))
            finished = true
        }
    }

    /// A stable pseudo-random number in 0..<1.
    private func fraction(_ value: Double) -> Double {
        let x = sin(value * 12.9898) * 43_758.5453
        return x - x.rounded(.down)
    }
}

/// A birthday, tapped: whose it is, and the surprise to organise or to join.
struct BirthdaySheet: View {
    enum Action {
        case organize
        case open(eventId: String)
        case message(friendId: String)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let occurrence: BirthdayOccurrence
    let onAction: (Action) -> Void

    var body: some View {
        let style = occurrence.style
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(userId: occurrence.userId, size: 76)
                    .padding(4)
                    .overlay {
                        if style == .intimate || style == .mine { ShimmerRing(lineWidth: 3, paused: true) }
                    }
                Text(style.emoji)
                    .font(.system(size: 24))
                    .offset(x: 4, y: 4)
            }
            .padding(.top, 28)

            VStack(spacing: 6) {
                Text(occurrence.mine ? "Ton anniversaire · \(occurrence.dayLabel)" : "Anniversaire de \(occurrence.name) · \(occurrence.dayLabel)")
                    .font(.wely.title3.bold())
                    .multilineTextAlignment(.center)
                if let closeness = occurrence.closeness {
                    Text(closeness.label)
                        .font(.wely.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Text(hint)
                    .font(.wely.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(spacing: 10) { actions }
                .padding(.horizontal)
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    private var hint: String {
        if occurrence.mine { return "Toute la bande Wely te souhaite une magnifique journée." }
        if occurrence.surprise != nil { return "🤫 Une surprise se prépare. \(occurrence.name) n'en saura rien." }
        if occurrence.canOrganize { return "Lance l'anniversaire surprise en un clic : tout est déjà prêt." }
        return "Un petit mot lui ferait plaisir."
    }

    @ViewBuilder
    private var actions: some View {
        if !occurrence.mine {
            if let surprise = occurrence.surprise {
                if surprise.joined {
                    Button { onAction(.open(eventId: surprise.eventId)) } label: { wide("Voir la surprise", "party.popper") }
                        .buttonStyle(.welyPrimary)
                } else {
                    AsyncButton {
                        _ = try await app.events.toggleSubscription(surprise.eventId)
                        app.eventsChanged()
                        onAction(.open(eventId: surprise.eventId))
                    } label: { wide("Rejoindre la surprise", "person.badge.plus") }
                        .buttonStyle(.welyPrimary)
                    Button { onAction(.open(eventId: surprise.eventId)) } label: { wide("Voir la surprise", "eye") }
                        .buttonStyle(.welySecondary)
                }
            } else if occurrence.canOrganize {
                Button { onAction(.organize) } label: { wide("Organiser une surprise", "gift") }
                    .buttonStyle(.welyPrimary)
            }
            Button { onAction(.message(friendId: occurrence.userId)) } label: { wide("Écrire à \(occurrence.name)", "bubble.left") }
                .buttonStyle(.welySecondary)
        } else {
            Button("Fermer") { dismiss() }
                .buttonStyle(.welySecondary)
        }
    }

    private func wide(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 28)
    }
}
