# Token accounting upgrade

Status: implementation in progress; desktop acceptance and release are pending.

## Requested behavior

| Surface | Requirement | Acceptance |
| --- | --- | --- |
| Menu bar | Remaining ring and percentage, cycle API-equivalent USD below it | Small system type; vertically centered; no application-name text |
| Menu bar | Red when remaining quota is strictly below 15% | 14.9% red; 15% neutral; unknown neutral |
| Ring | Center `!` when current subscription-cycle API equivalent is below USD 200 | Must represent the subscription account, not just selected folders; complete coverage and price bounds must support the comparison |
| Panel | Today, since last actual quota reset, current subscription cycle | Tokens and API-equivalent USD for each; expose missing records and uncertain boundaries |
| Panel | Latest three conversations | Cumulative tokens and model-specific equivalent for the latest conversations in the requested account scope |
| Settings | Monthly renewal day | Configurable 1–31, month-end clamping, local timezone; no private billing date in public defaults |
| Sources | Historical per-model accounting | Explicit folder scope; no global conversation scan; no authentication-file access |

The value is a comparison with current published Standard API prices, not an invoice, a subscription charge or a savings claim. Cached input and cache writes must be distinguished. Reasoning tokens already included in output are not billed again. Request context thresholds must never be applied to accumulated session totals.

## Current implementation is partial

Selected-folder accounting is an explicit partial-data mode, not a replacement
for the requested whole-account subscription statistics. It cannot prove the
account-wide $200 comparison or the latest three conversations across devices.
Those requirements remain open until an authoritative account-level source or
an explicitly agreed coverage definition is available. The original objective
must not be marked complete solely because scoped fixtures pass.

The quota API reports the next reset but no authoritative historical last-reset
instant. The current observed interval is useful evidence with a visible gap;
it does not reconstruct an unavailable past reset.

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
3. Interactive desktop checks: disclosures, language, billing-day changes, source picker, refresh, stale recovery, quit and relaunch. Static tests and offscreen images do not substitute for this gate.
4. Design review: clarity, visual hierarchy, interaction, accessibility, restrained feedback, consistency, usefulness and efficient implementation. Award criteria are a review framework, not certification.
5. Full release: documentation, version/build, changelog, tests, privacy review, commit/tag, downloadable app and checksum, actual GitHub Release, remote re-download verification.

Do not publish a stable release while the required interactive checks or accounting correctness remain unresolved.
