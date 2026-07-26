import Foundation

extension Error {
    /// True when this error is just SwiftUI/Swift Concurrency cancelling an in-flight
    /// task (e.g. a `.task` modifier restarting because the view's identity changed) —
    /// not a real failure, and should never be shown to the user.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}
