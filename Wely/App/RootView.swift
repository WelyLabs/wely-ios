import SwiftUI

/// The sign-in screen, or the app once signed in.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.lock.didBecomeActive()
            case .inactive: app.lock.didResignActive()
            case .background: app.lock.didEnterBackground()
            @unknown default: break
            }
        }
    }
}

/// The five tabs, under Wely's own bar rather than the system's — the bottom navigation of
/// wely-web on a phone. A tab is built the first time it is shown, then kept with its stack.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var opened: Set<AppTab> = []
    @State private var keyboardShown = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    if opened.contains(tab) || app.selectedTab == tab {
                        let selected = app.selectedTab == tab
                        screen(for: tab)
                            .opacity(selected ? 1 : 0)
                            .allowsHitTesting(selected)
                            .accessibilityHidden(!selected)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if app.tabBarHiders == 0 && !keyboardShown {
                WelyTabBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: app.tabBarHiders == 0 && !keyboardShown)
        .onChange(of: app.selectedTab, initial: true) { _, tab in opened.insert(tab) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
        .overlay(alignment: .top) { NotificationBanner() }
        .overlay { AppLockOverlay() }
        // Above the lock: a call answered from the lock screen shows without Face ID.
        .overlay { CallOverlay() }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .calendar: CalendarView()
        case .feed: ExploreView()
        case .messages: ConversationsView()
        case .social: SocialView()
        case .profile: ProfileView()
        }
    }
}

/// Wely's tab bar: the selected tab in the brand gradient, under a small gradient bar; the
/// profile tab is the user's own avatar.
private struct WelyTabBar: View {
    @Environment(AppModel.self) private var app
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            item(.calendar, "Calendrier", "calendar")
            item(.feed, "Explorer", "sparkles")
            item(.messages, "Messages", "bubble.left.and.bubble.right")
            item(.social, "Social", "person.2")
            item(.profile, "Moi", nil)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background {
            Theme.card.opacity(0.97)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Theme.border.frame(height: 1) }
                .shadow(color: .black.opacity(0.04), radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: AppTab, _ title: String, _ symbol: String?) -> some View {
        let selected = app.selectedTab == tab
        return Button {
            withAnimation(.snappy(duration: 0.25)) { app.selectedTab = tab }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if selected {
                        Capsule().fill(Theme.horizontalGradient)
                            .frame(width: 22, height: 3)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
                .frame(height: 3)

                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .symbolVariant(selected ? .fill : .none)
                            .font(.system(size: 20, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.ink2))
                    } else if let myId = app.people.myId {
                        AvatarView(userId: myId, size: 24)
                            .overlay(Circle().stroke(selected ? Theme.primary : .clear, lineWidth: 2).padding(-2))
                    } else {
                        Image(systemName: "person.crop.circle").font(.system(size: 20)).foregroundStyle(Theme.ink2)
                    }
                }
                .frame(height: 26)
                .overlay(alignment: .topTrailing) {
                    if tab == .profile, app.notifications.unread > 0 {
                        Text(app.notifications.unread > 9 ? "9+" : "\(app.notifications.unread)")
                            .font(.wely.fixed(10, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Theme.orange, in: Capsule())
                            .offset(x: 10, y: -4)
                    }
                }

                Text(title)
                    .font(.wely.fixed(10.5, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    /// Takes Wely's tab bar away while this screen shows (a conversation, whose composer sits at
    /// the bottom).
    func hidesWelyTabBar() -> some View { modifier(HidesWelyTabBar()) }
}

private struct HidesWelyTabBar: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .onAppear { app.tabBarHiders += 1 }
            .onDisappear { app.tabBarHiders = max(0, app.tabBarHiders - 1) }
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
                        Text(notification.title).font(.wely.subheadline.bold()).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(notification.body).font(.wely.caption).foregroundStyle(Theme.ink2).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .welyCard(radius: 20)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
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
