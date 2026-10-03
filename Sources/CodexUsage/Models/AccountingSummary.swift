import Foundation

enum AccountingSummary {
    static func make(snapshot: AccountingSnapshot?, calendar: AccountingCalendar,
                     reset: AccountingResetTracker, now: Date, folderCount: Int,
                     language: AppLanguage) -> AccountingPresentation {
        var result = AccountingPresentation()
        result.billingDay = calendar.renewalDay
        result.sourceFolderCount = folderCount
        let cycle = calendar.subscriptionCycle(containing: now)
        result.cycleStart = cycle?.start
        result.cycleEnd = cycle?.end
        guard let snapshot else { return result }
        let tokenGaps: Set<AccountingIssue> = [.scopeRequired, .threadListUnavailable,
            .threadLimitReached, .rolloutUnavailable, .unsupportedHistory, .invalidRecord, .historyCatchingUp]
        let scopeComplete = snapshot.recordsAreComplete && snapshot.issues.isDisjoint(with: tokenGaps)
        let hasLocal = snapshot.scannedThreadCount > 0
        if hasLocal {
            result.tokenSource = .local
            let today = calendar.today(containing: now)
            result.today = metric(records: snapshot.records.filter { $0.timestamp >= today.start && $0.timestamp <= now },
                                  complete: scopeComplete)
            if let cycle {
                result.cycle = metric(records: snapshot.records.filter { $0.timestamp >= cycle.start && $0.timestamp <= now },
                                      complete: scopeComplete)
            }
            // A manual reset is observed between two polls, not at an invented instant.
            // Count only the records after the upper bound and label that a partial total.
            if let upper = reset.resetUpperBound, upper <= now {
                result.lastReset = upper
                result.lastResetLowerBound = reset.resetLowerBound
                result.sinceReset = metric(records: snapshot.records.filter { $0.timestamp >= upper && $0.timestamp <= now },
                                           complete: false)
            }
            result.coverage = snapshot.issues.contains(.historyCatchingUp) ? .loading :
                (scopeComplete && !snapshot.records.contains(where: { $0.quality == .estimated }) ? .complete : .partial)
        } else if let buckets = snapshot.account?.dailyUsageBuckets, !buckets.isEmpty {
            // Service-date buckets have no published timezone. Approximation is visible;
            // they are never converted to USD without a model/category breakdown.
            let date = DateFormatter()
            date.calendar = calendar.calendar
            date.timeZone = calendar.timeZone
            date.locale = Locale(identifier: "en_US_POSIX")
            date.dateFormat = "yyyy-MM-dd"
            let today = date.string(from: now)
            result.today = serviceMetric(buckets.filter { $0.startDate == today })
            if let cycle {
                let start = date.string(from: cycle.start)
                result.cycle = serviceMetric(buckets.filter { $0.startDate >= start && $0.startDate <= today })
            }
            result.tokenSource = .account
            result.coverage = .partial
        }
        result.conversations = snapshot.recentThreads.prefix(3).map { thread in
            let value: AccountingMetricPresentation
            if let usage = thread.usage, !usage.groups.isEmpty {
                value = groupMetric(usage.groups)
            } else {
                value = metric(records: snapshot.records.filter { $0.threadID == thread.id }, complete: scopeComplete)
            }
            return AccountingConversationPresentation(id: thread.id,
                title: thread.name ?? language.accountingText(.untitledConversation), updatedAt: thread.updatedAt, metric: value)
        }
        // The comparison explicitly describes selected sources, never whole-account coverage.
        result.canCompareSelectedCycle = hasLocal && scopeComplete && cycle != nil &&
            !result.cycle.isEstimated && !result.cycle.costIsPartial && result.cycle.apiUSD != nil
        return result
    }

    static func metric(records: [AccountingUsageRecord], complete: Bool) -> AccountingMetricPresentation {
        guard !records.isEmpty else {
            return complete ? AccountingMetricPresentation(tokens: 0, apiUSD: 0) : AccountingMetricPresentation()
        }
        let estimated = records.contains { $0.quality == .estimated }
        let tokens = sum(records.map(\.totalTokens))
        let estimates = records.map { record in
            APIPricingCatalog.current.estimate(APIPricingRequest(model: record.model, serviceTier: "standard",
                usage: APITokenUsage(inputTokens: record.inputTokens, cachedInputTokens: record.cachedInputTokens,
                    cacheWriteTokens: record.cacheWriteInputTokens, outputTokens: record.outputTokens,
                    reasoningOutputTokens: record.reasoningOutputTokens),
                contextInputTokens: record.quality == .reported ? record.inputTokens : nil,
                timestamp: record.timestamp))
        }
        return pricedMetric(tokens: tokens, estimates: estimates, complete: complete,
                            tokenPartial: !complete, estimated: estimated)
    }

    private static func groupMetric(_ groups: [AccountingTokenGroup]) -> AccountingMetricPresentation {
        var tokenCounts: [Int64] = []
        var estimates: [APIValuation] = []
        var tokenPartial = false, costPartial = false
        for group in groups {
            if let total = group.totalTokens, total >= 0 { tokenCounts.append(total) }
            else { tokenPartial = true }
            guard let input = group.inputTokens, let output = group.outputTokens else { costPartial = true; continue }
            estimates.append(APIPricingCatalog.current.estimate(APIPricingRequest(model: group.model, serviceTier: "standard",
                usage: APITokenUsage(inputTokens: input, cachedInputTokens: group.cachedInputTokens,
                                     cacheWriteTokens: nil, outputTokens: output), contextInputTokens: nil)))
        }
        return pricedMetric(tokens: tokenCounts.isEmpty ? nil : sum(tokenCounts), estimates: estimates,
                            complete: !costPartial, tokenPartial: tokenPartial, estimated: false)
    }

    private static func pricedMetric(tokens: Int64?, estimates: [APIValuation], complete: Bool,
                                     tokenPartial: Bool, estimated: Bool) -> AccountingMetricPresentation {
        let invalid: Set<APIPricingIssue> = [.missingModel, .unknownModel, .invalidTokenCounts,
            .unsupportedServiceTier, .unsupportedLongContext, .historicalRateUnavailable]
        let priced = estimates.filter { Set($0.issues).isDisjoint(with: invalid) }
        guard !priced.isEmpty else {
            return AccountingMetricPresentation(tokens: tokens, tokensArePartial: tokenPartial, isEstimated: estimated)
        }
        let lower = priced.reduce(Decimal.zero) { $0 + $1.lowerBoundUSD }
        let hasUpper = estimates.count == priced.count && priced.allSatisfy { $0.upperBoundUSD != nil }
        let upper = hasUpper ? priced.reduce(Decimal.zero) { $0 + ($1.upperBoundUSD ?? 0) } : nil
        return AccountingMetricPresentation(tokens: tokens, apiUSD: NSDecimalNumber(decimal: lower).doubleValue,
            costUpperBoundUSD: upper.map { NSDecimalNumber(decimal: $0).doubleValue },
            tokensArePartial: tokenPartial, costIsPartial: !complete || !hasUpper, isEstimated: estimated)
    }

    private static func serviceMetric(_ buckets: [AccountDailyUsageBucket]) -> AccountingMetricPresentation {
        guard !buckets.isEmpty else { return AccountingMetricPresentation() }
        // Repeated dates are malformed coverage, not additional usage.
        let grouped = Dictionary(grouping: buckets, by: \.startDate)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { return AccountingMetricPresentation() }
        return AccountingMetricPresentation(tokens: sum(buckets.map(\.tokens)), tokensArePartial: true, isEstimated: true)
    }

    private static func sum(_ values: [Int64]) -> Int64? {
        var total: Int64 = 0
        for value in values {
            guard value >= 0 else { return nil }
            let added = total.addingReportingOverflow(value)
            guard !added.overflow else { return nil }
            total = added.partialValue
        }
        return total
    }
}
