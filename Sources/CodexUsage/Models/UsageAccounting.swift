import Foundation

/// The account endpoint reports dated buckets, with no documented timezone or
/// model split. Keep this distinct from request-level local accounting.
struct AccountTokenActivity: Decodable, Sendable {
    let summary: AccountTokenSummary
    let dailyUsageBuckets: [AccountDailyUsageBucket]?
    let threadUsage: AccountingThreadUsage?
}

struct AccountTokenSummary: Decodable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSec: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct AccountDailyUsageBucket: Decodable, Sendable {
    let startDate: String
    let tokens: Int64
}

struct AccountingThreadUsage: Decodable, Sendable {
    let threadId: String
    let estimatedUsageCreditsMicros: Int64
    let estimatedUsageUsdMicros: Int64?
    let groups: [AccountingTokenGroup]
}

struct AccountingTokenGroup: Decodable, Sendable {
    let model: String?
    let reasoningEffort: String?
    let speed: String?
    let inputTokens: Int64?
    let cachedInputTokens: Int64?
    let netNewInputTokens: Int64?
    let outputTokens: Int64?
    let totalTokens: Int64?
    let estimatedUsageCreditsMicros: Int64
}

enum AccountingRecordQuality: String, Codable, Sendable { case reported, estimated }

struct AccountingUsageRecord: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let threadID: String
    let timestamp: Date
    /// Model from that request's persisted turn context; routing can differ.
    let model: String?
    let serviceTier: String?
    let inputTokens: Int64
    let cachedInputTokens: Int64?
    let cacheWriteInputTokens: Int64?
    let outputTokens: Int64
    let reasoningOutputTokens: Int64?
    let totalTokens: Int64
    let quality: AccountingRecordQuality
}

enum AccountingIssue: String, Sendable, Hashable {
    case scopeRequired, accountUsageUnavailable, threadListUnavailable
    case threadLimitReached, rolloutUnavailable, unsupportedHistory
    case invalidRecord, estimatedUsage, missingModel, missingCacheCounts, historyCatchingUp
    case threadIndexUnavailable, threadIndexUnsupported, recursiveCoverageUnavailable
    case conversationUsageUnavailable
}

struct AccountingThread: Sendable, Identifiable {
    let id: String
    /// Title from scoped Codex metadata. Never substitute a message preview.
    let name: String?
    let updatedAt: Date
    let recencyAt: Date
    let usage: AccountingThreadUsage?
}

struct AccountingSnapshot: Sendable {
    let observedAt: Date
    let account: AccountTokenActivity?
    let recentThreads: [AccountingThread]
    let records: [AccountingUsageRecord]
    let issues: Set<AccountingIssue>
    let scannedThreadCount: Int
    /// Completeness refers only to the explicitly selected local directories.
    /// It never establishes complete account-wide or cross-device coverage.
    let recordsAreComplete: Bool
    var quotaObservations: [RecordedQuotaObservation] = []
}

struct DashboardSnapshot: Sendable {
    let quota: QuotaSnapshot
    let accounting: AccountingSnapshot
}

/// Narrow wire projection deliberately excludes previews, prompts and outputs.
struct AccountingThreadDescriptor: Decodable, Sendable {
    let id: String
    let name: String?
    let cwd: String
    let path: String?
    let createdAt: Double
    let updatedAt: Double
    let recencyAt: Double?
    let forkedFromId: String?
    let parentThreadId: String?
}

struct AccountingThreadPage: Decodable {
    let data: [AccountingThreadDescriptor]
    let nextCursor: String?
}
