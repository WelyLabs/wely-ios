import SwiftUI

/// An event's shared costs: the total, who is owed or owes, the transfers that settle it, and
/// every expense.
struct ExpensesView: View {
    @Environment(AppModel.self) private var app
    let event: FeedEvent

    @State private var ledger: Ledger?
    @State private var expenses: [Expense] = []
    @State private var members: [String] = []
    @State private var loadError: String?
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        List {
            if let ledger {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total dépensé").font(.wely.subheadline).foregroundStyle(.secondary)
                        Text(Money.format(cents: ledger.totalCents, currency: ledger.currency))
                            .font(.wely.largeTitle.bold())
                    }
                    .padding(.vertical, 4)
                }

                if !ledger.balances.isEmpty {
                    Section("Soldes") {
                        ForEach(ledger.balances, id: \.userId) { balance in
                            PersonRow(userId: balance.userId, subtitle: balance.netCents >= 0 ? "doit recevoir" : "doit") {
                                Text(Money.format(cents: abs(balance.netCents), currency: ledger.currency))
                                    .font(.wely.body.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(balance.netCents >= 0 ? .green : .red)
                            }
                        }
                    }
                }

                if !ledger.transfers.isEmpty {
                    Section {
                        ForEach(ledger.transfers, id: \.self) { transfer in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    AvatarView(userId: transfer.fromUserId, size: 28)
                                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    AvatarView(userId: transfer.toUserId, size: 28)
                                    Text("\(app.people.name(transfer.fromUserId)) → \(app.people.name(transfer.toUserId))")
                                        .font(.wely.subheadline)
                                    Spacer()
                                    Text(Money.format(cents: transfer.amountCents, currency: ledger.currency))
                                        .font(.wely.subheadline.monospacedDigit().bold())
                                }
                                if transfer.fromUserId == app.people.myId || transfer.toUserId == app.people.myId {
                                    AsyncButton {
                                        _ = try await app.events.settle(event.id, SettlementRequest(fromUserId: transfer.fromUserId, toUserId: transfer.toUserId,
                                                                                                     amountCents: transfer.amountCents))
                                        await load()
                                    } label: {
                                        Label("Marquer comme remboursé", systemImage: "checkmark.circle").font(.wely.caption.bold())
                                    }
                                    .buttonStyle(.welySecondary)
                                }
                            }
                        }
                    } header: {
                        Text("Pour équilibrer")
                    } footer: {
                        Text("Le moins de virements possible pour que tout le monde soit quitte.")
                    }
                }
            }

            Section("Dépenses") {
                if expenses.isEmpty {
                    Text("Aucune dépense pour l'instant.").foregroundStyle(.secondary)
                }
                ForEach(expenses.sorted { ($0.spentAt ?? .distantPast) > ($1.spentAt ?? .distantPast) }) { expense in
                    ExpenseRow(expense: expense)
                        .swipeActions {
                            if expense.createdBy == app.people.myId || expense.paidBy == app.people.myId {
                                Button(role: .destructive) { Task { await delete(expense) } } label: { Label("Supprimer", systemImage: "trash") }
                            }
                        }
                }
            }
        }
        .overlay { if ledger == nil, loadError == nil { ProgressView() } }
        .overlay {
            if let loadError, ledger == nil {
                EmptyStateView(title: "Dépenses indisponibles", systemImage: "eurosign.circle", message: loadError)
            }
        }
        .navigationTitle("Dépenses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Ajouter une dépense")
                    .disabled(members.isEmpty)
            }
        }
        .sheet(isPresented: $adding) {
            ExpenseFormView(eventId: event.id, members: members) { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($error)
    }

    private func load() async {
        do {
            async let ledger = app.events.ledger(event.id)
            async let expenses = app.events.expenses(event.id)
            async let participants = app.events.participants(event.id)
            self.ledger = try await ledger
            self.expenses = try await expenses
            members = (try? await participants)?.participantIds ?? []
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ expense: Expense) async {
        do {
            try await app.events.deleteExpense(event.id, expense.id)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ExpenseRow: View {
    @Environment(AppModel.self) private var app
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.isSettlement ? "arrow.left.arrow.right.circle.fill" : "cart.fill")
                .font(.wely.title3)
                .foregroundStyle(expense.isSettlement ? .green : Theme.orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.isSettlement ? "Remboursement" : expense.title).font(.wely.body.weight(.medium))
                Text(expense.isSettlement
                     ? "\(app.people.name(expense.paidBy)) → \(expense.owedCents?.keys.first.map { app.people.name($0) } ?? "")"
                     : "Payé par \(app.people.name(expense.paidBy))")
                    .font(.wely.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(cents: expense.amountCents, currency: expense.currency))
                .font(.wely.body.monospacedDigit().weight(.semibold))
        }
    }
}

/// Adds an expense: what, how much, who paid, and how it splits.
struct ExpenseFormView: View {
    @State private var failure: String?
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let eventId: String
    let members: [String]
    let onSaved: () -> Void

    @State private var title = ""
    @State private var amount = ""
    @State private var paidBy: String = ""
    @State private var split: SplitMode = .equal
    @State private var included: Set<String> = []
    @State private var values: [String: String] = [:]

    private var cents: Int? { Money.cents(from: amount) }

    private var shares: [ExpenseShare]? {
        let people = members.filter { included.contains($0) }
        guard !people.isEmpty else { return nil }
        switch split {
        case .equal:
            return people.map { ExpenseShare(userId: $0, value: 1) }
        case .shares:
            let parts = people.map { ExpenseShare(userId: $0, value: Int(values[$0] ?? "1") ?? 0) }
            return parts.allSatisfy { $0.value >= 0 } && parts.contains { $0.value > 0 } ? parts : nil
        case .exact:
            let parts = people.map { ExpenseShare(userId: $0, value: Money.cents(from: values[$0] ?? "") ?? 0) }
            return parts.map(\.value).reduce(0, +) == cents ? parts : nil
        }
    }

    var body: some View {
        WelyNavigationStack {
            Form {
                Section {
                    TextField("Quoi (ex. Courses, Essence…)", text: $title)
                    TextField("Montant en €", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Payé par", selection: $paidBy) {
                        ForEach(members, id: \.self) { Text(app.people.name($0)).tag($0) }
                    }
                }
                Section {
                    Picker("Partage", selection: $split) {
                        ForEach(SplitMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ForEach(members, id: \.self) { id in
                        HStack {
                            Button {
                                if included.contains(id) { included.remove(id) } else { included.insert(id) }
                            } label: {
                                Image(systemName: included.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(included.contains(id) ? Theme.blue : .secondary)
                            }
                            .buttonStyle(.plain)
                            AvatarView(userId: id, size: 28)
                            Text(app.people.name(id))
                            Spacer()
                            if split != .equal, included.contains(id) {
                                TextField(split == .shares ? "1" : "0,00", text: Binding(get: { values[id] ?? "" }, set: { values[id] = $0 }))
                                    .keyboardType(split == .shares ? .numberPad : .decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                    }
                } header: {
                    Text("Pour qui")
                } footer: {
                    if split == .exact { Text("La somme des montants doit égaler le total.") }
                    if split == .shares { Text("Ex. 2 pour quelqu'un qui compte double.") }
                }
            }
            .navigationTitle("Nouvelle dépense")
            .navigationBarTitleDisplayMode(.inline)
            .errorAlert($failure)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    AsyncButton("Ajouter") {
                        guard let cents, let shares else { return }
                        _ = try await app.events.addExpense(eventId, ExpenseRequest(title: title.trimmingCharacters(in: .whitespaces), amountCents: cents,
                                                                                    paidBy: paidBy, split: split, shares: shares))
                        onSaved()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || cents == nil || shares == nil || paidBy.isEmpty)
                }
            }
            .onAppear {
                paidBy = app.people.myId ?? members.first ?? ""
                included = Set(members)
            }
        }
    }
}
