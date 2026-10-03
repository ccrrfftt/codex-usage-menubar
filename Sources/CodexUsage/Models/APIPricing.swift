import Foundation

/// API-equivalent token valuation, never a subscription charge or an API invoice.
struct APITokenUsage: Equatable, Sendable {
    let inputTokens: Int64
    let cachedInputTokens: Int64?
    let cacheWriteTokens: Int64?
    let outputTokens: Int64
    /// A subset of outputTokens; it must never be added to output again.
    let reasoningOutputTokens: Int64?

    init(inputTokens: Int64, cachedInputTokens: Int64?, cacheWriteTokens: Int64?,
         outputTokens: Int64, reasoningOutputTokens: Int64? = nil) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
    }
}

enum APIServiceTier: String, CaseIterable, Sendable {
    case standard, fast, ultrafast, batch, flex

    /// Supply the observed processing tier. A requested "auto" tier is unresolved.
    init?(observedValue: String?) {
        switch observedValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "standard", "default": self = .standard
        case "fast", "priority": self = .fast
        case "ultrafast": self = .ultrafast
        case "batch": self = .batch
        case "flex": self = .flex
        default: return nil
        }
    }
}

enum APIPricingBasis: String, Sendable {
    case currentPublishedRates
    case historicalAtRequestDate
}

struct APIPricingRequest: Sendable {
    let model: String?
    let serviceTier: String?
    let usage: APITokenUsage
    /// Input length of the complete request, never a cumulative session/day counter.
    let contextInputTokens: Int64?
    let timestamp: Date?
    let basis: APIPricingBasis

    init(model: String?, serviceTier: String?, usage: APITokenUsage,
         contextInputTokens: Int64? = nil, timestamp: Date? = nil,
         basis: APIPricingBasis = .currentPublishedRates) {
        self.model = model
        self.serviceTier = serviceTier
        self.usage = usage
        self.contextInputTokens = contextInputTokens
        self.timestamp = timestamp
        self.basis = basis
    }
}

struct APITokenRates: Equatable, Sendable {
    let uncachedInput: Decimal
    let cachedInput: Decimal
    /// Nil means the model does not publish a separate cache-write category.
    let cacheWrite: Decimal?
    let output: Decimal

    fileprivate init(_ input: String, _ cached: String, _ write: String?, _ output: String) {
        uncachedInput = Self.decimal(input)
        cachedInput = Self.decimal(cached)
        cacheWrite = write.map(Self.decimal)
        self.output = Self.decimal(output)
    }

    fileprivate static func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    fileprivate func scaled(input: Decimal, output: Decimal) -> Self {
        Self(uncachedInput: uncachedInput * input, cachedInput: cachedInput * input,
             cacheWrite: cacheWrite.map { $0 * input }, output: self.output * output)
    }

    private init(uncachedInput: Decimal, cachedInput: Decimal, cacheWrite: Decimal?, output: Decimal) {
        self.uncachedInput = uncachedInput
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
        self.output = output
    }
}

struct APIModelPricing: Sendable {
    let modelID: String
    let aliases: [String]
    let shortContextRates: [APIServiceTier: APITokenRates]
    let longContextRates: [APIServiceTier: APITokenRates]
    let longContextThreshold: Int64?
    let sourceURLs: [String]

    var hasSeparateCacheWrites: Bool { shortContextRates[.standard]?.cacheWrite != nil }
}

enum APIPricingIssue: String, CaseIterable, Sendable {
    case missingModel, unknownModel, missingServiceTier, unknownServiceTier
    case unsupportedServiceTier, unknownContextLength, unsupportedLongContext
    case missingCachedInput, missingCacheWrites, unpricedCacheWrites, invalidTokenCounts
    case historicalRateUnavailable
}

struct APIValuationComponents: Equatable, Sendable {
    var uncachedInputUSD: Decimal?
    var cachedInputUSD: Decimal?
    var cacheWriteUSD: Decimal?
    var outputUSD: Decimal?

    var subtotalUSD: Decimal {
        [uncachedInputUSD, cachedInputUSD, cacheWriteUSD, outputUSD]
            .compactMap { $0 }.reduce(Decimal.zero, +)
    }
}

struct APIValuation: Sendable {
    let modelID: String?
    let tier: APIServiceTier?
    let components: APIValuationComponents
    let issues: [APIPricingIssue]
    let catalogCheckedOn: String
    /// True when unknown context required short-context rates as a conservative floor.
    let componentsUseMinimumRates: Bool

    var isComplete: Bool { issues.isEmpty }
    var totalUSD: Decimal? { isComplete ? components.subtotalUSD : nil }
    var knownSubtotalUSD: Decimal { componentsUseMinimumRates ? .zero : components.subtotalUSD }
    /// Bounds include every token category that can be bounded from published rates.
    let lowerBoundUSD: Decimal
    let upperBoundUSD: Decimal?
}

struct APIPricingCatalog: Sendable {
    let checkedOn: String
    let models: [APIModelPricing]

    func model(named value: String) -> APIModelPricing? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return models.first { $0.modelID == name || $0.aliases.contains(name) }
    }

    func estimate(_ request: APIPricingRequest) -> APIValuation {
        var issues: [APIPricingIssue] = []
        var components = APIValuationComponents()
        var minimumRates = false
        var lowerBound = Decimal.zero
        var upperBound: Decimal?
        let model = request.model.flatMap { self.model(named: $0) }
        let tier = APIServiceTier(observedValue: request.serviceTier)
        func result() -> APIValuation {
            APIValuation(modelID: model?.modelID, tier: tier, components: components,
                         issues: issues, catalogCheckedOn: checkedOn, componentsUseMinimumRates: minimumRates,
                         lowerBoundUSD: lowerBound, upperBoundUSD: upperBound)
        }
        if request.basis == .historicalAtRequestDate {
            issues.append(.historicalRateUnavailable)
            return result()
        }
        guard let model else {
            issues.append(request.model == nil ? .missingModel : .unknownModel)
            return result()
        }
        guard let tier else {
            issues.append(request.serviceTier == nil ? .missingServiceTier : .unknownServiceTier)
            return result()
        }
        guard var rates = model.shortContextRates[tier] else {
            issues.append(.unsupportedServiceTier)
            return result()
        }
        let usage = request.usage
        let cached = usage.cachedInputTokens ?? (usage.inputTokens == 0 ? 0 : nil)
        let writes = usage.cacheWriteTokens ?? (model.hasSeparateCacheWrites && usage.inputTokens != 0 ? nil : 0)
        // Subtract before comparing to avoid overflowing on hostile or damaged counters.
        guard usage.inputTokens >= 0, usage.outputTokens >= 0,
              (cached ?? 0) >= 0, (writes ?? 0) >= 0,
              (cached ?? 0) <= usage.inputTokens,
              (writes ?? 0) <= usage.inputTokens - (cached ?? 0),
              (usage.reasoningOutputTokens ?? 0) >= 0,
              (usage.reasoningOutputTokens ?? 0) <= usage.outputTokens,
              (request.contextInputTokens ?? 0) >= 0 else {
            issues.append(.invalidTokenCounts)
            return result()
        }
        var upperRates: APITokenRates? = rates
        if let threshold = model.longContextThreshold {
            if let context = request.contextInputTokens {
                if context > threshold {
                    guard let longRates = model.longContextRates[tier] else {
                        issues.append(.unsupportedLongContext)
                        return result()
                    }
                    rates = longRates
                    upperRates = longRates
                }
            } else {
                issues.append(.unknownContextLength)
                minimumRates = true
                upperRates = model.longContextRates[tier]
            }
        }
        func cost(_ tokens: Int64, _ price: Decimal) -> Decimal {
            Decimal(tokens) * price / Decimal(1_000_000)
        }
        components.outputUSD = cost(usage.outputTokens, rates.output)
        if let cached { components.cachedInputUSD = cost(cached, rates.cachedInput) }
        else { issues.append(.missingCachedInput) }
        if let writes {
            if writes == 0 { components.cacheWriteUSD = .zero }
            else if let price = rates.cacheWrite { components.cacheWriteUSD = cost(writes, price) }
            else { issues.append(.unpricedCacheWrites) }
        } else { issues.append(.missingCacheWrites) }
        if let cached, let writes {
            components.uncachedInputUSD = cost(usage.inputTokens - cached - writes, rates.uncachedInput)
        }
        func boundedCost(at boundRates: APITokenRates, upper: Bool) -> Decimal? {
            let inputRate = boundRates.uncachedInput
            let cachedRate = boundRates.cachedInput
            let writeRate = boundRates.cacheWrite
            var value = cost(usage.outputTokens, boundRates.output)
            if let cached { value += cost(cached, cachedRate) }
            if let writes, writes > 0 {
                if let writeRate { value += cost(writes, writeRate) }
                else if upper { return nil }
            }
            let remaining = usage.inputTokens - (cached ?? 0) - (writes ?? 0)
            var possibleRates = [inputRate]
            if cached == nil { possibleRates.append(cachedRate) }
            if writes == nil {
                guard let writeRate else { return upper ? nil : value }
                possibleRates.append(writeRate)
            }
            let remainingRate = upper ? possibleRates.max()! : possibleRates.min()!
            return value + cost(remaining, remainingRate)
        }
        lowerBound = boundedCost(at: rates, upper: false) ?? .zero
        upperBound = upperRates.flatMap { boundedCost(at: $0, upper: true) }
        return result()
    }

    static let current: Self = {
        let pricing = "https://developers.openai.com/api/docs/pricing"
        let modelURL = "https://developers.openai.com/api/docs/models/"
        let half = APITokenRates.decimal("0.5")
        let oneAndHalf = APITokenRates.decimal("1.5")
        var models: [APIModelPricing] = []
        func add(_ id: String, _ input: String, _ cached: String, _ write: String?, _ output: String,
                 aliases: [String] = [], fast: APITokenRates? = nil, discount: Bool = false,
                 longContext: Bool = false, longFast: Bool = false, ultrafast: APITokenRates? = nil,
                 discountOverride: APITokenRates? = nil, longDiscountOverride: APITokenRates? = nil) {
            let standard = APITokenRates(input, cached, write, output)
            var short: [APIServiceTier: APITokenRates] = [.standard: standard]
            var long: [APIServiceTier: APITokenRates] = [:]
            if let fast { short[.fast] = fast }
            if let ultrafast { short[.ultrafast] = ultrafast }
            if discount {
                let rates = discountOverride ?? standard.scaled(input: half, output: half)
                short[.batch] = rates; short[.flex] = rates
            }
            if longContext {
                for (tier, rates) in short where tier != .fast || longFast {
                    long[tier] = (tier == .batch || tier == .flex) && longDiscountOverride != nil
                        ? longDiscountOverride : rates.scaled(input: 2, output: oneAndHalf)
                }
            }
            models.append(APIModelPricing(modelID: id, aliases: aliases, shortContextRates: short,
                                          longContextRates: long, longContextThreshold: longContext ? 272_000 : nil,
                                          sourceURLs: [pricing, modelURL + id]))
        }
        // Values are USD per million tokens, checked 2026-10-03. See docs/PRICING.md.
        add("gpt-6-astra", "10", "1", "12.5", "50", fast: .init("20", "2", "25", "100"),
            discount: true, longContext: true, longFast: true, ultrafast: .init("60", "6", "75", "300"))
        add("gpt-6.1-sol", "2", "0.1", "2.5", "10", fast: .init("4", "0.2", "5", "20"),
            discount: true, longContext: true, longFast: true)
        add("gpt-6-sol", "2", "0.2", "2.5", "10", fast: .init("4", "0.4", "5", "20"),
            discount: true, longContext: true, longFast: true)
        add("gpt-6-luna", "0.1", "0.01", "0.125", "0.5", fast: .init("0.2", "0.02", "0.25", "1"),
            discount: true, longContext: true, longFast: true)
        add("gpt-5.6-sol", "4", "0.4", "5", "20", aliases: ["gpt-5.6"],
            fast: .init("8", "0.8", "10", "40"), discount: true, longContext: true, longFast: true)
        add("gpt-5.6-terra", "2", "0.2", "2.5", "12", fast: .init("4", "0.4", "5", "24"),
            discount: true, longContext: true, longFast: true)
        add("gpt-5.6-luna", "0.2", "0.02", "0.25", "1.2", fast: .init("0.4", "0.04", "0.5", "2.4"),
            discount: true, longContext: true, longFast: true)
        add("gpt-5.5", "5", "0.5", nil, "30", aliases: ["gpt-5.5-2026-04-23"],
            fast: .init("12.5", "1.25", nil, "75"), discount: true, longContext: true)
        // Preserve the published short discount precision and explicit long rate independently.
        add("gpt-5.4", "2.5", "0.25", nil, "15", aliases: ["gpt-5.4-2026-03-05"],
            fast: .init("5", "0.5", nil, "30"), discount: true, longContext: true,
            discountOverride: .init("1.25", "0.13", nil, "7.5"),
            longDiscountOverride: .init("2.5", "0.25", nil, "11.25"))
        add("gpt-5.4-mini", "0.75", "0.075", nil, "4.5", fast: .init("1.5", "0.15", nil, "9"), discount: true)
        add("gpt-5.4-nano", "0.2", "0.02", nil, "1.25", discount: true)
        add("gpt-5.2", "1.75", "0.175", nil, "14", fast: .init("3.5", "0.35", nil, "28"), discount: true)
        add("gpt-5.1", "1.25", "0.125", nil, "10", fast: .init("2.5", "0.25", nil, "20"), discount: true)
        add("gpt-5", "1.25", "0.125", nil, "10", fast: .init("2.5", "0.25", nil, "20"), discount: true)
        add("gpt-5-mini", "0.25", "0.025", nil, "2", fast: .init("0.45", "0.045", nil, "3.6"), discount: true)
        add("gpt-5-nano", "0.05", "0.005", nil, "0.4", discount: true)
        add("gpt-5.3-codex", "1.75", "0.175", nil, "14", fast: .init("3.5", "0.35", nil, "28"))
        add("gpt-5.2-codex", "1.75", "0.175", nil, "14")
        add("gpt-5.1-codex-max", "1.25", "0.125", nil, "10")
        add("gpt-5.1-codex", "1.25", "0.125", nil, "10")
        add("gpt-5-codex", "1.25", "0.125", nil, "10")
        add("gpt-5.1-codex-mini", "0.25", "0.025", nil, "2")
        add("codex-mini-latest", "1.5", "0.375", nil, "6")
        return Self(checkedOn: "2026-10-03", models: models)
    }()
}
