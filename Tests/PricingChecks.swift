import Foundation

@main
struct PricingChecks {
    static func check(_ success: Bool, _ label: String) {
        precondition(success, "FAILED: " + label)
        print("PASS: " + label)
    }

    static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    static func quote(_ model: String? = "gpt-6-astra", tier: String? = "standard",
                      input: Int64 = 100_000, cached: Int64? = 60_000, writes: Int64? = 20_000,
                      output: Int64 = 10_000, reasoning: Int64? = 4_000, context: Int64? = 100_000,
                      basis: APIPricingBasis = .currentPublishedRates) -> APIValuation {
        APIPricingCatalog.current.estimate(.init(model: model, serviceTier: tier,
            usage: .init(inputTokens: input, cachedInputTokens: cached, cacheWriteTokens: writes,
                         outputTokens: output, reasoningOutputTokens: reasoning),
            contextInputTokens: context, basis: basis))
    }

    static func main() {
        let exact = quote()
        check(exact.totalUSD == decimal("1.01") && exact.lowerBoundUSD == exact.upperBoundUSD,
              "separate ordinary input, cache reads, cache writes, and output sum exactly")
        check(exact.components.uncachedInputUSD == decimal("0.20")
              && exact.components.cachedInputUSD == decimal("0.06")
              && exact.components.cacheWriteUSD == decimal("0.25")
              && exact.components.outputUSD == decimal("0.50"),
              "cache writes replace ordinary input pricing rather than adding a fee")
        check(quote(reasoning: nil).totalUSD == exact.totalUSD,
              "reasoning is already part of output and is never charged twice")
        check(quote("gpt-6.1-sol").totalUSD == decimal("0.196")
              && quote("gpt-6-sol").totalUSD == decimal("0.202"),
              "6.1 Sol and 6 Sol preserve their different cache-read rates")
        check(quote(tier: "fast").totalUSD == decimal("2.02")
              && quote(tier: "priority").totalUSD == decimal("2.02")
              && quote(tier: "ultrafast").totalUSD == decimal("6.06"),
              "observed Fast/Priority and Ultrafast use their own published rates")
        check(quote(tier: "batch").totalUSD == decimal("0.505")
              && quote(tier: "flex").totalUSD == decimal("0.505"),
              "published Astra Batch and Flex rates are half Standard")
        check(quote(input: 272_000, cached: 0, writes: 0, context: 272_000).totalUSD == decimal("3.22"),
              "exactly 272000 input tokens remains short context")
        let long = quote(input: 272_001, cached: 0, writes: 0, context: 272_001)
        check(long.totalUSD == decimal("6.19002"),
              "272001 input tokens changes the entire request including all output")
        let unknownContext = quote(context: nil)
        check(unknownContext.totalUSD == nil && unknownContext.issues == [.unknownContextLength]
              && unknownContext.lowerBoundUSD == decimal("1.01")
              && unknownContext.upperBoundUSD == decimal("1.77")
              && unknownContext.knownSubtotalUSD == 0,
              "missing request length gives bounds rather than an invented exact price")
        let cumulative = quote(input: 1_000_000, cached: 0, writes: 0, context: nil)
        check(cumulative.totalUSD == nil && cumulative.lowerBoundUSD == decimal("10.5")
              && cumulative.upperBoundUSD == decimal("20.75"),
              "cumulative input cannot select a long-context price band")
        let missingWrites = quote(writes: nil)
        check(missingWrites.totalUSD == nil && missingWrites.issues == [.missingCacheWrites]
              && missingWrites.knownSubtotalUSD == decimal("0.56")
              && missingWrites.lowerBoundUSD == decimal("0.96")
              && missingWrites.upperBoundUSD == decimal("1.06"),
              "unknown cache-write split is bounded by ordinary input and write alternatives")
        let missingBoth = quote(cached: nil, writes: nil)
        check(missingBoth.totalUSD == nil && missingBoth.lowerBoundUSD == decimal("0.6")
              && missingBoth.upperBoundUSD == decimal("1.75"),
              "missing both cache categories retains a conservative bounded range")
        for cached in stride(from: Int64(0), through: 100_000, by: 10_000) {
            for writes in stride(from: Int64(0), through: 100_000 - cached, by: 10_000) {
                let actual = quote(cached: cached, writes: writes).totalUSD!
                precondition(actual >= missingBoth.lowerBoundUSD && actual <= missingBoth.upperBoundUSD!)
            }
        }
        print("PASS: all feasible sampled cache partitions fall within uncertainty bounds")
        let unknownModel = quote("gpt-6-astra-future")
        check(unknownModel.issues == [.unknownModel] && unknownModel.totalUSD == nil
              && unknownModel.upperBoundUSD == nil, "unknown model suffixes never inherit guessed prices")
        check(quote(nil).issues == [.missingModel], "missing model is explicitly incomplete")
        check(quote(tier: nil).issues == [.missingServiceTier]
              && quote(tier: "auto").issues == [.unknownServiceTier]
              && quote("gpt-6.1-sol", tier: "ultrafast").issues == [.unsupportedServiceTier],
              "missing, automatic, and unsupported service tiers are never silently Standard")
        check(quote("gpt-5.6", writes: 0).modelID == "gpt-5.6-sol"
              && quote("gpt-5.5-2026-04-23", writes: nil).modelID == "gpt-5.5",
              "only documented aliases map to canonical model rates")
        check(quote("gpt-5.5", tier: "fast", cached: 50_000, writes: nil).totalUSD == decimal("1.4375"),
              "GPT-5.5 Fast costs 2.5 times Standard rather than a blanket 2 times")
        check(quote("gpt-5.5", tier: "fast", writes: nil, context: 300_000).issues == [.unsupportedLongContext]
              && quote("gpt-5.4", tier: "fast", writes: nil, context: nil).upperBoundUSD == nil,
              "legacy Fast long context stays unpriced when no published long rate exists")
        check(quote("gpt-5.3-codex", input: 300_000, cached: 0, writes: nil, output: 100_000,
                    context: 300_000).totalUSD == decimal("1.925"),
              "legacy Codex has no separate cache-write fee or invented long-context multiplier")
        check(quote("gpt-5.4", tier: "flex", writes: nil).totalUSD == decimal("0.1328")
              && quote("gpt-5.4", tier: "flex", input: 300_000, cached: 100_000, writes: nil,
                       context: 300_000).totalUSD == decimal("0.6375"),
              "published GPT-5.4 discount precision and explicit long rate are preserved")
        check(quote(input: 0, cached: nil, writes: nil, output: 0, reasoning: nil, context: 0).totalUSD == 0,
              "explicit zero usage is distinct from unavailable usage")
        check(quote(input: -1).issues == [.invalidTokenCounts]
              && quote(input: Int64.max, cached: Int64.max, writes: Int64.max).issues == [.invalidTokenCounts]
              && quote(reasoning: 10_001).issues == [.invalidTokenCounts],
              "negative, overflowing partition, and impossible reasoning counters fail safely")
        check(quote("gpt-5.3-codex", writes: 1).issues == [.unpricedCacheWrites]
              && quote("gpt-5.3-codex", writes: 1).upperBoundUSD == nil,
              "unexpected legacy write category does not get a guessed price")
        let historical = quote(basis: .historicalAtRequestDate)
        check(historical.issues == [.historicalRateUnavailable] && historical.upperBoundUSD == nil,
              "current published prices are never mislabeled as historical billing")
        check(APIPricingCatalog.current.checkedOn == "2026-10-03", "catalog preserves verification date")
        print("Pricing checks passed.")
    }
}
