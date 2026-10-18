import SwiftUI

/// « Proposer une sortie » with a friend: the week's common free evenings, as a pre-filled form.
enum OutingProposal {
    /// A failed search still opens the form, on the next evening.
    static func draft(with friendId: String, events: EventService, now: Date = .now, calendar: Calendar = .wely) async -> EventFormView.Draft {
        let end = calendar.date(byAdding: .day, value: OutingSlots.searchDays, to: calendar.startOfDay(for: now)) ?? now
        let search = FreeSlotSearch(friendIds: [friendId], start: now, end: end, durationMinutes: OutingSlots.searchMinutes)
        let free = (try? await events.freeSlots(search)) ?? []
        return .outing(slots: OutingSlots.pick(free: free, now: now, calendar: calendar), now: now, calendar: calendar)
    }
}

/// « Ça fait longtemps »: close friends not seen for a while, to see again or to put off.
struct ReunionCard: View {
    let candidates: [ReunionCandidate]
    let onPropose: (ReunionCandidate) async -> Void
    let onDismiss: (ReunionCandidate) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.wave.fill").foregroundStyle(Theme.gradient)
                Text("Ça fait longtemps").font(.wely.headline)
            }
            ForEach(candidates) { candidate in
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink(value: Route.person(candidate.friendId)) {
                        HStack(spacing: 12) {
                            AvatarView(userId: candidate.friendId, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.name).font(.wely.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                Text(candidate.subtitle).font(.wely.caption).foregroundStyle(Theme.ink2).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 10) {
                        AsyncButton { await onPropose(candidate) } label: {
                            Label("Proposer une sortie", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.welyPrimary)
                        AsyncButton("Plus tard") { try await onDismiss(candidate) }
                            .buttonStyle(.welySecondary)
                    }
                }
                if candidate != candidates.last { Divider() }
            }
        }
        .padding(14)
        .welyCard()
    }
}

/// « 3 de tes proches y vont », with their faces.
struct FriendsGoingRow: View {
    let event: FeedEvent

    var body: some View {
        if let label = event.friendsGoingLabel {
            let close = !FriendsGoing.close(event.friendsGoing).isEmpty
            HStack(spacing: 8) {
                let faces = FriendsGoing.faces(event.friendsGoing)
                if !faces.isEmpty { AvatarStack(userIds: faces, limit: 3, size: 22) }
                Text(label)
                    .font(.wely.caption.weight(.semibold))
                    .foregroundStyle(close ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.ink2))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A closeness upgrade just accepted: the new level's glow and a few rising hearts.
struct ClosenessCelebration: View {
    let closeness: Closeness
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let celebration = closeness.celebration
        ZStack {
            Circle()
                .fill(Theme.gradient)
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .opacity(closeness == .intimate ? 0.55 : 0.4)
            if !reduceMotion { RisingHearts(emoji: celebration.emoji).allowsHitTesting(false) }
            VStack(spacing: 10) {
                Text(celebration.emoji).font(.system(size: 54))
                Text("\(name) et toi êtes \(celebration.title)")
                    .font(.wely.title3.bold())
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Text(celebration.message)
                    .font(.wely.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 300)
            .welyCard(radius: 24)
            .overlay {
                if closeness == .intimate {
                    ShimmerRingShape(cornerRadius: 24, paused: reduceMotion)
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.orange.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.6))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

/// A rounded border in the brand gradient whose light goes round; still under reduced motion.
private struct ShimmerRingShape: View {
    let cornerRadius: CGFloat
    var paused = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            let turn = paused ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AngularGradient(colors: Theme.gradientStops + [Theme.gradientStops[0]], center: .center, angle: .degrees(turn * 360)),
                              lineWidth: 2)
        }
    }
}

/// Hearts drifting up once from the bottom, fading as they rise.
private struct RisingHearts: View {
    let emoji: String
    @State private var started = Date.now

    private static let count = 14
    private static let duration: TimeInterval = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { canvas, size in
                let elapsed = context.date.timeIntervalSince(started)
                let heart = canvas.resolve(Text(emoji).font(.system(size: 22)))
                for index in 0..<Self.count {
                    let seed = Double(index)
                    let delay = fraction(seed * 2.3) * 0.8
                    let progress = (elapsed - delay) / Self.duration
                    guard progress > 0, progress < 1 else { continue }
                    let x = fraction(seed * 7.1) * size.width + sin(progress * 6 + seed) * 12
                    let y = size.height * (1 - progress) + 20
                    var piece = canvas
                    piece.opacity = 1 - progress
                    piece.translateBy(x: x, y: y)
                    piece.scaleBy(x: 0.6 + fraction(seed * 3.7) * 0.8, y: 0.6 + fraction(seed * 3.7) * 0.8)
                    piece.draw(heart, at: .zero)
                }
            }
        }
        .onAppear { started = .now }
    }

    /// A stable pseudo-random number in 0..<1.
    private func fraction(_ value: Double) -> Double {
        let x = sin(value * 12.9898) * 43_758.5453
        return x - x.rounded(.down)
    }
}
