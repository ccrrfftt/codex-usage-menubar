# API-equivalent valuation

Catalogue checked **2026-10-03**, in USD per million tokens. This is a token-only valuation at the published rates checked on that date. It is not a ChatGPT subscription charge, credit balance, refund, saving, or API invoice. Regional/FedRAMP premiums, tools, storage, containers, media, taxes, and negotiated discounts are outside this calculation.

The app can intentionally pass `serviceTier: "standard"` to compare usage consistently against **current Standard API-equivalent prices**. That choice must be labelled. It does not establish the processing tier actually served to a subscription user. Without an intentional comparison tier or observed API processing tier, the calculator leaves the amount incomplete.

## Current catalogue

The following are short-context Standard rates. `—` means there is no separately published cache-write category for that model; it does not mean a modern model's missing cache-write counter is zero.

| Model | Ordinary input | Cached input | Cache write | Output |
| --- | ---: | ---: | ---: | ---: |
| [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) | 10 | 1 | 12.5 | 50 |
| [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol) | 2 | 0.1 | 2.5 | 10 |
| [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol) | 2 | 0.2 | 2.5 | 10 |
| [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna) | 0.1 | 0.01 | 0.125 | 0.5 |
| [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) | 4 | 0.4 | 5 | 20 |
| [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra) | 2 | 0.2 | 2.5 | 12 |
| [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna) | 0.2 | 0.02 | 0.25 | 1.2 |
| [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5) | 5 | 0.5 | — | 30 |
| [GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4) | 2.5 | 0.25 | — | 15 |
| GPT-5.4 mini | 0.75 | 0.075 | — | 4.5 |
| GPT-5.4 nano | 0.2 | 0.02 | — | 1.25 |
| GPT-5.2 | 1.75 | 0.175 | — | 14 |
| GPT-5.1 / GPT-5 | 1.25 | 0.125 | — | 10 |
| GPT-5 mini | 0.25 | 0.025 | — | 2 |
| GPT-5 nano | 0.05 | 0.005 | — | 0.4 |
| [GPT-5.3-Codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex) / [GPT-5.2-Codex](https://developers.openai.com/api/docs/models/gpt-5.2-codex) | 1.75 | 0.175 | — | 14 |
| [GPT-5.1-Codex-Max](https://developers.openai.com/api/docs/models/gpt-5.1-codex-max) / [GPT-5.1-Codex](https://developers.openai.com/api/docs/models/gpt-5.1-codex) / [GPT-5-Codex](https://developers.openai.com/api/docs/models/gpt-5-codex) | 1.25 | 0.125 | — | 10 |
| [GPT-5.1-Codex Mini](https://developers.openai.com/api/docs/models/gpt-5.1-codex-mini) | 0.25 | 0.025 | — | 2 |
| [codex-mini-latest](https://developers.openai.com/api/docs/models/codex-mini-latest) | 1.5 | 0.375 | — | 6 |

Additional base-model rates and tier support are from the official [API pricing catalogue](https://developers.openai.com/api/docs/pricing), including its “All models” tables. Unknown IDs, internal aliases, arbitrary date suffixes, and GPT-5.3-Codex-Spark have no fallback price. Only the documented `gpt-5.6` alias and listed GPT-5.4/GPT-5.5 snapshots are mapped.

## Token accounting

For GPT-5.6 and later, the [prompt-caching guide](https://developers.openai.com/api/docs/guides/prompt-caching) explicitly defines disjoint input categories:

```text
ordinary input = input_tokens - cached_tokens - cache_write_tokens
input cost = ordinary × ordinary rate + cached × cached rate + writes × write rate
```

All terms are divided by 1,000,000. Cache writes replace the ordinary-input price for those tokens; they are not an additive fee. Modern models need the actual write count, including explicit zero, for an exact amount. Earlier supported models have no separate write fee and do not require that counter. Missing cached-input data is also not silently zero.

`output_tokens` already includes reasoning. `reasoningOutputTokens` is an optional subset used only for consistency checking, never an extra charge. See the [reasoning usage example](https://developers.openai.com/api/docs/guides/reasoning).

## Context and processing tiers

GPT-6 and GPT-5.6 use short rates through **272,000 input tokens inclusive**. Above that threshold, all input/cache rates are doubled and all output rates are multiplied by 1.5 for the full request. Their model pages document these rules. GPT-5.4 and GPT-5.5 document the same threshold and multipliers for Standard, Batch, and Flex, with the wording “full session.” The caller must supply the full applicable context length for the billable usage unit; a cumulative counter or token delta cannot establish the applicable band.

The current pricing table publishes Fast long-context rates for GPT-5.6 and GPT-6, but no long Fast rate for GPT-5.4/5.5. Those legacy Fast long-context combinations remain incomplete. No long surcharge is invented for older Codex or smaller base models.

Tier rates are explicit. GPT-5.5 Fast is 2.5× Standard; GPT-5.4, GPT-5.6, GPT-6, and GPT-5.3-Codex Fast are 2×. GPT-5 mini Fast is 1.8×. Astra Ultrafast is 6×. Unsupported tier/model pairs remain unpriced. GPT-5.6 Sol's Ultrafast preview does not establish a public rate. The catalogue implements Batch/Flex only for verified base-model rows. GPT-5.4's published short Batch/Flex cached price is $0.13, while its explicit long price is $0.25; both published values are preserved independently.

[Fast mode](https://developers.openai.com/api/docs/guides/fast-mode) accepts both `fast` and `priority`. The actual returned tier can differ from the requested tier, including a downgrade to `default`; `auto` is unresolved. [Ultrafast](https://developers.openai.com/api/docs/guides/ultrafast-mode) is a separate tier. Neither API multipliers nor token valuation measure subscription quota consumption or actual speed.

## Incomplete estimates and dates

`APIPricingCatalog.current.estimate(_:)` returns Decimal amounts:

- `totalUSD` exists only when all required pricing inputs are known and consistent.
- `components` preserves individually priced categories; `knownSubtotalUSD` omits categories that cannot be priced exactly. Unknown context makes these provisional component rates minimum rates, and `knownSubtotalUSD` is then zero.
- `lowerBoundUSD` and `upperBoundUSD` include feasible cache partitions. Missing writes with known cached input bounds the remaining input between ordinary and write pricing. Unknown context bounds it between short and long pricing when both exist.
- An unknown model/tier or unavailable price has no bounded upper amount. Its lower bound is zero, which must never be displayed as a complete zero cost. Keep its token counts and issue visible.
- Below-budget claims require complete period coverage and a bounded aggregate upper amount below the budget. An incomplete lower amount alone cannot establish that usage was below a subscription fee.

These bounds cover token-price uncertainty only. They do not bound missing requests, unobserved usage, or excluded charges. Malformed token partitions are rejected before arithmetic; input categories cannot exceed input, and reasoning cannot exceed output.

The catalogue date is a **verification date**, not a retroactive effective date. `timestamp` is retained as metadata; current-rate valuation intentionally uses the same snapshot for earlier usage. `historicalAtRequestDate` returns `historicalRateUnavailable` because no complete historical schedule has been verified. Do not relabel it historical billing. The [official changelog](https://developers.openai.com/api/docs/changelog) documents GPT-5.6 Terra/Luna price reductions on July 30, 2026, which demonstrates why current rates cannot reconstruct prior invoices. GPT-5.6 Sol's current promotion is promised at least through November 21, 2026; no later price is invented.

## Verification

The standalone synthetic checks cover disjoint cache accounting, reasoning, the exact long-context boundary, processing tiers, missing counters, conservative ranges across feasible cache partitions, legacy models, unknown IDs, invalid counters, and historical-price refusal. They read no user sessions or account data.

```sh
swiftc -swift-version 6 Sources/CodexUsage/Models/APIPricing.swift Tests/PricingChecks.swift -o /tmp/codex-pricing-checks
/tmp/codex-pricing-checks
```
