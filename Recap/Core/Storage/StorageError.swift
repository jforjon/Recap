import Foundation

struct StorageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    static func notFound(_ what: String, id: UUID) -> StorageError {
        StorageError(message: "\(what) not found: \(id)")
    }

    static func notAuthenticated() -> StorageError {
        StorageError(message: "You must be signed in to access notes")
    }

    static func emptyPayload(_ operation: String) -> StorageError {
        StorageError(message: "\(operation) failed: no fields to update")
    }
}
