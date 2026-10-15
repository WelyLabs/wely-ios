import SwiftUI

/// The sign-in screen, or the app once signed in.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.session.state {
            case .signedOut:
                LoginView()
            case .signedIn:
                MainTabView()
            }
        }
        .animation(.default, value: app.session.state)
        .task(id: app.session.state) {
            if app.session.state == .signedIn { await app.start() } else { app.stop() }
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Calendrier", systemImage: "calendar", value: AppTab.calendar) {
                CalendarView()
            }
            Tab("Explorer", systemImage: "sparkles", value: AppTab.feed) {
                ExploreView()
            }
            Tab("Messages", systemImage: "bubble.left.and.bubble.right", value: AppTab.messages) {
                ConversationsView()
            }
            Tab("Social", systemImage: "person.2", value: AppTab.social) {
                SocialView()
            }
            Tab("Profil", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileView()
            }
        }
        .overlay(alignment: .top) { NotificationBanner() }
    }
}

/// A live notification, shown a few seconds at the top; a tap opens it.
private struct NotificationBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let notification = app.notifications.arrival {
            Button {
                app.notifications.markRead(notification)
                if let destination = notification.destination { app.open(destination) }
                app.notifications.arrival = nil
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: notification.systemImage)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.gradient, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title).font(.subheadline.bold()).lineLimit(1)
                        Text(notification.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: notification.id) {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { app.notifications.arrival = nil }
            }
        }
    }
}

#Preview {
    #if DEBUG
    let app = AppModel.demo()
    MainTabView().environment(app).environment(app.session)
    #endif
}
