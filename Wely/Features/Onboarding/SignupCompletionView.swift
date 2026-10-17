import SwiftUI

/// One question the signup completion asks; a new one is a new case, its view and its field.
enum SignupStep: CaseIterable, Hashable {
    case birthDate

    /// What the account still owes: every step until the backend says the signup is complete.
    static func pending(for profile: UserProfile?) -> [SignupStep] {
        guard let profile, !profile.registrationCompleted else { return [] }
        return allCases
    }
}

/// The answers collected across the steps, sent together once the last one is done.
struct SignupAnswers: Equatable {
    var birthDate: Date

    /// Signing up takes 13 to 120 years, as wely-users checks it.
    static func birthDateRange(now: Date = .now, calendar: Calendar = .wely) -> ClosedRange<Date> {
        let oldest = calendar.date(byAdding: .year, value: -120, to: now) ?? now
        let youngest = calendar.date(byAdding: .year, value: -13, to: now) ?? now
        return oldest...youngest
    }

    static func initial(now: Date = .now, calendar: Calendar = .wely) -> SignupAnswers {
        SignupAnswers(birthDate: calendar.date(byAdding: .year, value: -25, to: calendar.startOfDay(for: now)) ?? now)
    }

    func request(calendar: Calendar = .wely) -> RegistrationRequest {
        RegistrationRequest(birthDate: DayString.string(from: birthDate, calendar: calendar))
    }
}

/// « Finalise ton inscription »: shown over the app, without a way out, until the steps are done.
struct SignupCompletionView: View {
    @Environment(AppModel.self) private var app
    let steps: [SignupStep]

    @State private var index = 0
    @State private var answers = SignupAnswers.initial()
    @State private var error: String?

    private var step: SignupStep { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .birthDate: birthDateStep
                    }
                }
                .padding(20)
            }
            footer
        }
        .background(Theme.canvas.ignoresSafeArea())
        .errorAlert($error)
        .transition(.opacity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finalise ton inscription")
                .font(.wely.title.bold())
            Text(steps.count > 1 ? "Étape \(index + 1) sur \(steps.count)" : "Une dernière chose avant de commencer.")
                .font(.wely.subheadline)
                .opacity(0.9)
            if steps.count > 1 {
                ProgressView(value: Double(index + 1), total: Double(steps.count)).tint(.white)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(Theme.gradient.ignoresSafeArea(edges: .top))
    }

    private var birthDateStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ta date de naissance", systemImage: "birthday.cake")
                .font(.wely.headline)
            DatePicker("Date de naissance", selection: $answers.birthDate, in: SignupAnswers.birthDateRange(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.locale, .wely)
            Label("Tes amis verront le jour et le mois, jamais ton année.", systemImage: "eye.slash")
                .font(.wely.footnote)
                .foregroundStyle(Theme.ink2)
        }
        .welyCard(padding: 16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if index > 0 {
                Button("Retour") { withAnimation { index -= 1 } }
                    .buttonStyle(.welySecondary)
                    .controlSize(.large)
            }
            AsyncButton {
                if isLast { try await submit() } else { withAnimation { index += 1 } }
            } label: {
                Text(isLast ? "Terminer" : "Continuer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.welyPrimary)
            .controlSize(.large)
        }
        .padding(20)
    }

    private func submit() async throws {
        let profile = try await app.users.completeRegistration(birthDate: answers.request().birthDate)
        withAnimation { app.people.setMe(profile) }
    }
}
