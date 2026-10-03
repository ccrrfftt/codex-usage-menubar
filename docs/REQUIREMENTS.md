# Token accounting upgrade

Status: implemented; final native verification and release checklist are recorded in the design review.

## Requested behavior

| Surface | Requirement | Acceptance |
| --- | --- | --- |
| Menu bar | Remaining ring and percentage, cycle API-equivalent USD below it | Small system type; vertically centered; no application-name text |
| Menu bar | Red when remaining quota is strictly below 15% | 14.9% red; 15% neutral; unknown neutral |
| Ring | Center `!` when current subscription-cycle API equivalent is below USD 200 | Uses the user-confirmed local project scope; a full tracked cycle and price bounds must support the comparison |
| Panel | Today, since the observed or explicitly estimated reset, current subscription cycle | Tokens and API-equivalent USD for each; expose missing records and uncertain boundaries |
| Panel | Latest three conversations | Tokens accumulated since tracking began, and model-specific equivalents, for the latest conversations in the selected local scope |
| Settings | Monthly renewal day | Configurable 1–31, month-end clamping, local timezone; no private billing date in public defaults |
| Sources | Historical per-model accounting | Start at local midnight on first activation and persist that start; selected roots include descendants; no message preview or authentication-file access |

The value is a comparison with current published Standard API prices, not an invoice, a subscription charge or a savings claim. Cached input and cache writes must be distinguished. Reasoning tokens already included in output are not billed again. Request context thresholds must never be applied to accumulated session totals.

## Confirmed scope and start boundary

The accepted scope is usage recorded on this Mac for selected project roots and
their descendants. Records from other devices or outside those roots are not
required. Complete historical backfill is not required: tracking starts at local
midnight on initial activation, and that timestamp persists across later launches.
An existing conversation resumed after the start contributes only its new usage.

The first subscription cycle may start before tracking. Its known subtotal is
marked partial, so it cannot assert the full cycle is below $200. The first fully
tracked cycle can enable the comparison when coverage and prices are sufficient.
Recent conversations show their accumulated usage since tracking began, not old
lifetime totals from the service. Missing records or unknown prices remain visible.

The quota API reports the next reset but no authoritative historical last-reset
instant. A reset observed after tracking begins supplies a polling interval;
records after its upper bound form a disclosed subtotal. If no observation exists, a valid active quota window can provide an explicitly
estimated boundary. The row uses ≈ until stronger evidence exists; missing or
expired window context remains unavailable.

## Existing behavior to preserve

- Native macOS menu-bar app without a browser dashboard or Dock icon.
- Compact popover; full disclosure rows are clickable and keyboard accessible.
- Expanding grows downward from the menu-bar anchor, without recentering animation.
- One-click Chinese/English switch, persisted independently of system language.
- Reset-card count and individual expiry dates; missing expiry stays unknown.
- No Pause, Show in Finder, open-panel frequency menu or automatic reset redemption.
- Refresh every 60 seconds on AC and 300 seconds on battery; opening the panel does not alter the cadence.
- Pause querying offline, asleep, screen off or inactive; one timer, bounded retries, owned child-process cleanup.

## Evidence and delivery gates

1. Synthetic checks: date boundaries, period rollover, unknown and partial data, duplicate responses, forks, per-model prices, missing cache writes, numeric overflow and cancelled reads.
2. Native rendering: normal/low/unknown quota, warning/unknown value, bilingual and appearance variants, compact two-line menu bar.
3. Native runtime checks: disclosures, language, billing-day changes, source picker, refresh, stale recovery, quit and relaunch. The user explicitly waived the dedicated Computer-tool requirement on 2026-10-03. Native runtime evidence and any limits must still be reported accurately.
4. Design review: clarity, visual hierarchy, interaction, accessibility, restrained feedback, consistency, usefulness and efficient implementation. Award criteria are a review framework, not certification.
5. Full release: documentation, version/build, changelog, tests, privacy review, commit/tag, downloadable app and checksum, actual GitHub Release, remote re-download verification.

Do not present static fixtures as live testing, and do not publish while accounting correctness remains unresolved.
