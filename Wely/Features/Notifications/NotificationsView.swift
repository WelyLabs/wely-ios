import SwiftUI

/// The notification center, by day; a tap marks it read and opens what it is about.
struct NotificationsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let center = app.notifications
        List {
            if center.items.isEmpty {
                EmptyStateView(title: "Aucune notification", systemImage: "bell.slash", message: "Les demandes d'amis, messages et changements de date arrivent ici.")
                    .listRowBackground(Color.clear)
            }
            ForEach(groups(center.items), id: \.0) { day, items in
                Section(day) {
                    ForEach(items) { notification in
                        Button { open(notification) } label: { NotificationRow(notification: notification) }
                            .buttonStyle(.plain)
                            .onAppear {
                                if notification.id == center.items.last?.id { Task { await center.loadMore() } }
                            }
                    }
                }
            }
            if center.isLoading { ProgressView().frame(maxWidth: .infinity) }
        }
        .navigationTitle("Notifications")
        .toolbar {
            if center.unread > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tout lire") { center.markAllRead() }
                }
            }
        }
        .refreshable { await center.refresh() }
    }

    private func open(_ notification: AppNotification) {
        app.notifications.markRead(notification)
        if let destination = notification.destination { app.open(destination) }
    }

    private func groups(_ items: [AppNotification]) -> [(String, [AppNotification])] {
        var result: [(String, [AppNotification])] = []
        for item in items {
            let label = item.createdAt.dayLabel()
            if result.last?.0 == label { result[result.count - 1].1.append(item) } else { result.append((label, [item])) }
        }
        return result
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let actor = notification.actorId {
                    AvatarView(userId: actor, size: 42)
                } else {
                    Circle().fill(Theme.gradient).frame(width: 42, height: 42)
                }
                Image(systemName: notification.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Theme.blue, in: Circle())
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(notification.title).font(.wely.subheadline.weight(notification.isRead ? .regular : .semibold))
                if !notification.body.isEmpty {
                    Text(notification.body).font(.wely.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(notification.createdAt.relativeShort()).font(.wely.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !notification.isRead {
                Circle().fill(Theme.blue).frame(width: 9, height: 9).padding(.top, 6)
                    .accessibilityLabel("Non lue")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
