import SwiftUI

/// One question the signup completion asks; a new one is a new case, its view and its field.
enum SignupStep: CaseIterable, Hashable {
    /// First: Auth0's signup form asks no names.
    case names
    case birthDate

    /// Whether the profile still misses this step's field.
    func isMissing(in profile: UserProfile) -> Bool {
        switch self {
        case .names: SignupAnswers.isBlank(profile.firstName) || SignupAnswers.isBlank(profile.lastName)
        case .birthDate: SignupAnswers.isBlank(profile.birthDate)
        }
    }

    /// The steps whose field the profile misses, whatever registrationCompleted says: a step added
    /// later is asked, alone, of members who never filled it.
    static func pending(for profile: UserProfile?) -> [SignupStep] {
        guard let profile else { return [] }
        return allCases.filter { $0.isMissing(in: profile) }
    }
}

/// The answers collected across the steps, sent together once the last one is done.
struct SignupAnswers: Equatable {
    var firstName = ""
    var lastName = ""
    var birthDate: Date

    /// wely-users' limit for each name.
    static let nameMax = 255

    static func isBlank(_ value: String?) -> Bool {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A name wely-users accepts: 1 to 255 characters once trimmed.
    static func isValidName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= nameMax
    }

    /// Signing up takes 13 to 120 years, as wely-users checks it.
    static func birthDateRange(now: Date = .now, calendar: Calendar = .wely) -> ClosedRange<Date> {
        let oldest = calendar.date(byAdding: .year, value: -120, to: now) ?? now
        let youngest = calendar.date(byAdding: .year, value: -13, to: now) ?? now
        return oldest...youngest
    }

    /// The names the profile already has, prefilled; a birth date of 25 years ago to start the wheel.
    static func initial(for profile: UserProfile? = nil, now: Date = .now, calendar: Calendar = .wely) -> SignupAnswers {
        SignupAnswers(firstName: profile?.firstName ?? "", lastName: profile?.lastName ?? "",
                      birthDate: calendar.date(byAdding: .year, value: -25, to: calendar.startOfDay(for: now)) ?? now)
    }

    /// Whether this step's answer can be sent.
    func isValid(_ step: SignupStep) -> Bool {
        switch step {
        case .names: Self.isValidName(firstName) && Self.isValidName(lastName)
        case .birthDate: true
        }
    }

    /// Only the fields of the pending steps: the others stay as the profile has them.
    func request(for steps: [SignupStep], calendar: Calendar = .wely) -> RegistrationRequest {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return RegistrationRequest(
            birthDate: steps.contains(.birthDate) ? DayString.string(from: birthDate, calendar: calendar) : nil,
            firstName: steps.contains(.names) ? trim(firstName) : nil,
            lastName: steps.contains(.names) ? trim(lastName) : nil)
    }
}

/// « Finalise ton inscription »: shown over the app, without a way out, until the steps are done.
struct SignupCompletionView: View {
    @Environment(AppModel.self) private var app
    let steps: [SignupStep]

    @State private var index = 0
    @State private var answers: SignupAnswers
    @State private var error: String?

    init(steps: [SignupStep], profile: UserProfile?) {
        self.steps = steps
        _answers = State(initialValue: SignupAnswers.initial(for: profile))
    }

    private var step: SignupStep { steps[min(index, steps.count - 1)] }
    private var isLast: Bool { index >= steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .names: namesStep
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

    private var namesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ton prénom et ton nom", systemImage: "person.text.rectangle")
                .font(.wely.headline)
            TextField("Prénom", text: $answers.firstName)
                .textContentType(.givenName)
                .textFieldStyle(.roundedBorder)
            TextField("Nom", text: $answers.lastName)
                .textContentType(.familyName)
                .textFieldStyle(.roundedBorder)
            Label("C'est comme ça que tes amis te trouveront.", systemImage: "person.2")
                .font(.wely.footnote)
                .foregroundStyle(Theme.ink2)
        }
        .welyCard(padding: 16)
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
            .disabled(!answers.isValid(step))
        }
        .padding(20)
    }

    private func submit() async throws {
        let profile = try await app.users.completeRegistration(answers.request(for: steps))
        withAnimation { app.people.setMe(profile) }
    }
}
