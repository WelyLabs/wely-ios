import Foundation

/// Decodes a value, or nil instead of failing the surrounding array.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// An array that may be missing or null on the wire: empty then.
@propertyWrapper
struct DefaultEmpty<Element: Codable & Hashable>: Codable, Hashable {
    var wrappedValue: [Element]
    init(wrappedValue: [Element] = []) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        wrappedValue = (try? decoder.singleValueContainer().decode([Element].self)) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// A flag that may be missing or null on the wire: false then.
@propertyWrapper
struct DefaultFalse: Codable, Hashable, Sendable {
    var wrappedValue: Bool
    init(wrappedValue: Bool = false) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        wrappedValue = (try? decoder.singleValueContainer().decode(Bool.self)) ?? false
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// A flag that may be missing or null on the wire: true then.
@propertyWrapper
struct DefaultTrue: Codable, Hashable, Sendable {
    var wrappedValue: Bool
    init(wrappedValue: Bool = true) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        wrappedValue = (try? decoder.singleValueContainer().decode(Bool.self)) ?? true
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

/// A string the backend sends as a string or a number (a user's `hashtag`); empty when missing.
@propertyWrapper
struct LossyString: Codable, Hashable, Sendable {
    var wrappedValue: String
    init(wrappedValue: String = "") { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            wrappedValue = string
        } else if let int = try? container.decode(Int.self) {
            wrappedValue = String(int)
        } else {
            wrappedValue = ""
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    func decode<T>(_ type: DefaultEmpty<T>.Type, forKey key: Key) throws -> DefaultEmpty<T> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmpty()
    }
    func decode(_ type: DefaultFalse.Type, forKey key: Key) throws -> DefaultFalse {
        try decodeIfPresent(type, forKey: key) ?? DefaultFalse()
    }
    func decode(_ type: DefaultTrue.Type, forKey key: Key) throws -> DefaultTrue {
        try decodeIfPresent(type, forKey: key) ?? DefaultTrue()
    }
    func decode(_ type: LossyString.Type, forKey key: Key) throws -> LossyString {
        try decodeIfPresent(type, forKey: key) ?? LossyString()
    }
}

extension DefaultEmpty: Sendable where Element: Sendable {}
