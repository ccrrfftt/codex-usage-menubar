import Foundation

enum QuotaError: LocalizedError, Equatable, Sendable {
    case unavailable, disconnected, timedOut, account, malformed

    var errorDescription: String? { message(in: .chinese) }

    func message(in language: AppLanguage) -> String {
        switch self {
        case .unavailable: language.text(.errorUnavailable)
        case .disconnected: language.text(.errorDisconnected)
        case .timedOut: language.text(.errorTimedOut)
        case .account: language.text(.errorAccount)
        case .malformed: language.text(.errorMalformed)
        }
    }
}
