import Foundation

/// A partial update: only the keys present are changed. Mirrors `Partial<T>` on
/// the web side, and keeps the Postgres column names as keys so the shapes still
/// line up if the data ever moves back to a server.
///
/// This used to be supabase-swift's `AnyJSON`. Call sites only ever set a string
/// or clear a value, so those are the only two cases.
enum JSONValue: Hashable, Sendable {
    case string(String)
    case null

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}

typealias JSONObject = [String: JSONValue]
