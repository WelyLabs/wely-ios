import Foundation

enum SplitMode: String, Codable, CaseIterable, Sendable {
    case equal = "EQUAL"
    case shares = "SHARES"
    case exact = "EXACT"

    var label: String {
        switch self {
        case .equal: "À parts égales"
        case .shares: "Par parts"
        case .exact: "Montants exacts"
        }
    }
}

struct ExpenseShare: Codable, Hashable, Sendable {
    let userId: String
    /// A weight for SHARES, cents for EXACT, ignored (1) for EQUAL.
    var value: Int
}

struct Expense: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let amountCents: Int
    let currency: String?
    let paidBy: String
    let createdBy: String?
    /// EXPENSE, or SETTLEMENT for a repayment.
    let kind: String?
    let split: SplitMode?
    @DefaultEmpty var shares: [ExpenseShare] = []
    let owedCents: [String: Int]?
    let spentAt: Date?
    let version: Int?
    let receiptUrl: String?

    var isSettlement: Bool { kind == "SETTLEMENT" }
}

struct ExpenseRequest: Codable, Sendable {
    var title: String
    var amountCents: Int
    var paidBy: String
    var split: SplitMode
    var shares: [ExpenseShare]
    var version: Int?
}

struct SettlementRequest: Codable, Sendable {
    let fromUserId: String
    let toUserId: String
    let amountCents: Int
}

struct Balance: Codable, Hashable, Sendable {
    let userId: String
    let netCents: Int
}

struct Transfer: Codable, Hashable, Sendable {
    let fromUserId: String
    let toUserId: String
    let amountCents: Int
}

struct Ledger: Codable, Hashable, Sendable {
    let currency: String?
    let totalCents: Int
    @DefaultEmpty var balances: [Balance] = []
    @DefaultEmpty var transfers: [Transfer] = []
}

enum Money {
    /// « 12,50 € ».
    static func format(cents: Int, currency: String? = "EUR") -> String {
        (Double(cents) / 100).formatted(.currency(code: currency ?? "EUR").locale(.wely))
    }

    /// « 12,5 » or « 12.50 » typed by the user, in cents; nil when unreadable or not positive.
    static func cents(from text: String) -> Int? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: nil).intValue
    }
}
