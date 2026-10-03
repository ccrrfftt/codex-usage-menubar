# Native usage panel design review

This is a design and code review of the existing macOS menu bar utility. It is
not an award submission, an award score, or proof of visual acceptance.

## Intended experience

The menu bar communicates remaining quota and the current subscription cycle's
estimated API value. Opening it keeps quota and reset information first, then
shows today, since the observed reset, and the subscription cycle in three
aligned rows. Conversation details and accounting configuration use progressive
disclosure. The app remains a native utility without a Dock window.

The review uses clarity, usefulness, interaction quality, accessibility, visual
craft, and technical restraint as lenses relevant to Awwwards, Webby, FWA,
Apple Design Award, and Red Dot discussions. These are internal review criteria,
not a claimed scoring system from those organizations.

## Iteration 1: existing code inspection

- Preserve the small panel, one-click language toggle, existing quota hierarchy,
  full-row disclosure controls, and immediate popover resizing.
- Make the new three-period totals visible immediately. Hide only the secondary
  conversation rows and configuration controls.
- Give tokens and API equivalents separate coverage semantics. A missing value
  is an em dash. A partial total is a known lower bound, marked with `≥`.
- Price ranges are shown only when they describe the full priced scope. For a
  partial priced scope, show the known lower bound instead of a misleading upper
  bound for the entire total.
- Label estimated money as API equivalent in USD. Do not present it as an actual
  charge, an invoice, or proven savings.
- Keep billing day optional for a new installation. Present cycle dates and an
  explicit unconfigured state. Put source selection beside cycle configuration.
- Keep conversation titles to one line with a full-title help label. Show at
  most three records; combine the title and both totals for accessibility.
- Use native system fonts, semantic colors, tabular numeric alignment, and a
  312-point panel. Avoid decorative charts, additional timers, and animation.

## Acceptance checks still requiring the running app

1. Capture the closed menu bar and open panel in both appearance modes. Verify
   two text lines remain legible and centered at the real menu bar height.
2. Inspect Chinese and English with unavailable, partial, full, high-value, and
   long-title synthetic fixtures. Verify no clipping or overlapping columns.
3. Expand both disclosure sections. Verify the popover's top remains anchored,
   its height grows downward, and the footer remains reachable.
4. Change the monthly start day, clear it, select a synthetic fixture folder,
   and clear that folder. Reopen the popover and relaunch to verify persistence.
5. Navigate by keyboard and inspect VoiceOver labels. Check that status is
   understandable without color. A screenshot alone cannot prove accessibility.
6. Inspect the ring at 14.9%, 15%, and unavailable quota, with cycle values below
   and above the threshold and with unavailable pricing.
7. Confirm on battery/AC and during sleep that accounting uses the existing
   refresh cadence instead of adding a separate polling loop.

## Iteration 2: offline native rendering

The offline fixture renderer now uses the real `UsageAccountingView` and real
`StatusItemLabel` with fixed synthetic data. Chinese and English panel images
were rendered in light and dark appearances. Separate native label images cover
14.9%, exactly 15%, partial pricing, and unavailable pricing at a 22-point height.

The first pass revealed that SwiftUI ImageRenderer substitutes an unsupported
placeholder for the native progress view. Rendering was changed to an offscreen
NSHostingView so the actual native control draws. Long conversation names now
end in an explicit ellipsis. Inspected images show aligned totals, readable
coverage labels, full currency ranges, and no clipped footer in these fixtures.
Exactly 15% retains the ordinary color; 14.9% is red. The complete synthetic
selected-source cycle below $200 shows the center mark; partial pricing does not.
The comparison explicitly covers selected records at current Standard API rates;
it does not claim verified whole-account coverage.

Legacy telemetry receives an approximate marker instead of a guaranteed lower
bound. Reset details disclose the observed interval and count records only after
its end. Pricing help specifies current Standard API rates; the subscription
cycle uses local midnight rather than claiming an exact billing instant.

## Iteration 3: scope consistency

A second review found that the fixture footer described service-date tokens
without a model breakdown while its rows demonstrated locally priced records.
The fixture now identifies selected local records consistently. The comparison
flag was renamed to describe its actual selected-source scope, and the cycle
value help explains what the center warning mark means. An unavailable full
account total is never implied to be complete by this comparison.

The settings callbacks are explicitly MainActor and Sendable. A focused Swift 6
type check passed without warnings; callbacks execute immediately without an
extra task or dispatch delay.

These are offline layout images, not live desktop screenshots. Live Computer
tool interaction, popover anchoring, settings persistence, keyboard navigation,
VoiceOver, and power behavior remain pending. The dark/light native progress
view may use an inactive-window appearance in offscreen renders. Compilation and
these images are not substitutes for runtime checks. All fixtures contain only
fictional values and conversation names, with no private account information.

## Current verification checkpoint

The integrated build and synthetic checks pass, including period boundaries,
pricing, scoped incremental parsing, process cancellation, source replacement,
settings persistence and waiting for retired queries during shutdown. Native
bilingual light/dark fixtures were visually inspected. They are explicitly
marked fictional and are not desktop-interaction evidence.

Actual click, anchoring, focus and relaunch verification remains pending because
no Computer/CUA tool is callable in the development session. No stable release
or claim of interactive acceptance is made at this checkpoint. The user has now authorized a recursive project root; its matching and import
logic have been tested with synthetic SQLite databases and log fixtures. Actual
historical-source coverage has not yet been accepted in the running app.


## Iteration 4: recursive history and reset provenance

The selected source now includes descendant project directories, using a
read-only index query with exact path-component boundaries. It does not walk
project contents. Index checks cover archived records, WAL visibility,
Unicode paths, cancellation, unavailable schemas and explicit coverage limits.
The query does not retrieve conversation messages, previews or titles; recent
conversations receive a localized date-and-time label when no name is supplied.

Historical numeric quota observations can bootstrap an estimated last-reset
boundary. Stronger live observations take precedence. The row names its quota
window, and its tooltip distinguishes historical inference from an observed
interval. The offline light fixture demonstrates the approximate marker; the
dark fixture demonstrates a partial post-reset total.

The source picker starts at its existing selection. Menu-bar label drawing now
skips tooltip-only changes. The separate interactive QA harness compiles the
production store, scheduler, status item and views, with a synthetic data reader
and an isolated preference domain. Its build does not launch an app. See
[UI testing](UI_TESTING.md) for scenarios and the outstanding Computer checks.

Verification on 2026-10-03: `script/check.sh` completed with 330 passing
synthetic checks. `script/run_ui_fixture.sh --build-only` compiled the
interactive harness; plist, ad-hoc signature and embedded-path checks passed.
`script/render_demo.sh` produced the updated four bilingual light/dark panels
and both status-boundary strips. These results still do not establish desktop
interaction or actual personal-history coverage.


## Iteration 5: prospective tracking

The accepted scope now starts on the first activation day within the chosen
local roots. Complete earlier history and other-device usage are not required.
The saved date survives relaunch. A compact tracking-date label shares the cycle
line; Chinese and English light/dark offline fixtures were inspected without
adding height. Light fixtures show the first partial cycle, with no center mark;
dark fixtures show a fully tracked cycle. Hover text explains both the fixed
start and the recent-conversation totals.

Calendar and summary checks cover known zero after a successful empty scan,
exclusion of earlier records and lifetime service totals, an incomplete initial
cycle, and enabling the comparison in the next complete cycle. Store checks
verify that the start is persisted before any request and restored on later days.
These additions do not replace the pending Computer-tool acceptance.

Final prospective checkpoint: all 364 synthetic checks pass, including 53 parser,
38 scoped-index, 34 store and 33 aggregation checks. The interactive QA bundle
compiles and its local signature verifies. Its controls have not been exercised
with the required Computer tool. The README image is an inspected fictional
fixture with non-pixel metadata removed; it is not a live account screenshot.


## Release verification: 1.7.0

The user waived the dedicated Computer-tool requirement on 2026-10-03. A bounded
native self-test then exercised the actual status button, popover, language
switch, blank portions of both disclosure rows, and refresh action. It completed
with 36 passing checks, zero failures and 15 explicit inspection limitations.
Both expansions preserved the top edge with zero displacement. Own-view captures
were inspected after transparent pixels were composited onto white; all rows and
the footer remained legible and unclipped. This is native view/event evidence,
not a full-desktop screenshot or a VoiceOver certification.

The 364 synthetic checks cover the production accounting, date, pricing,
settings, cancellation and energy policies. Production source did not change
after that run. A real read-only check passed with CLI 0.160.0 on desktop
26.930.31730 (build 12947), including the presence of reset-tracking identity and
window fields. The required local SQLite column types also match; that schema
check did not query conversation rows.

The remaining native inspection limits are the settings/date/folder controls,
physical input and VoiceOver, as detailed in [UI testing](UI_TESTING.md). Settings
persistence and source replacement are covered by store tests. No private account
values, conversation content or personal project paths appear in public fixtures.
The distributable is ad-hoc signed and is not Apple-notarized.
