# Interactive native UI acceptance fixture

`script/run_ui_fixture.sh` builds a separate **Codex Usage QA.app** from the
production models, services, store, and views, excluding the production app
entrypoint. Its bundle ID and UserDefaults suite are
`local.codexusage.acceptance`; its process is `CodexUsageQA`. It is an accessory
app without a Dock icon and has a small, explicitly labeled QA control window.

## Build and launch boundaries

```bash
./script/run_ui_fixture.sh --build-only
```

The default is also `--build-only`. The bundle is built and ad-hoc signed under
`/private/tmp/codex-usage-acceptance/ui-fixture/`, or under the supplied
`CODEX_USAGE_BUILD_ROOT`. Building does not launch the app, read account data,
change preferences, stop another app, or restart Codex or the computer.

For an interactive test run:

```bash
./script/run_ui_fixture.sh --launch
```

Use **Quit QA** or the real panel's quit button when finished. The script never
kills a process. Quit the QA app before rebuilding if a new executable must be
loaded. The production Codex Usage app and its preferences are separate.

## Synthetic data boundary

The injected `DashboardReading` implementation returns in-memory fixtures. It
checks only whether selected source paths are empty; it never opens or scans
those paths. No CLI, SQLite index, conversation history, or network request is
used. Production connection and reader sources are compiled but never created
by the fixture. The system monitor is explicitly disabled; power and network
states are sent through the store's normal state-update method.

On first QA launch, only the QA preference domain receives renewal day 5,
Chinese language, and the bundle sibling directory `Synthetic Sources/Project A`.
The QA app creates `Project A` and `Project B` there, with no private content.
Later launches preserve the QA language, day, and selected-folder settings. A
QA-only `accountingTrackingStart` preference is seeded to the current day-5
subscription cycle start on each launch. This deliberately makes the $150/$200/
$250 scenarios cover a complete synthetic period. The production tracking start
and preferences are never changed. A
synthetic reset observation is seeded through two real reset-tracker observations
eight and six hours before launch, with a stable weekly reset window. It is
loaded through the same preference decoder as the production store. This seeded
history does not prove a live reset transition was observed in a real account.

Each control action advances an injected monotonic uptime by six seconds, then
uses the store's normal refresh or energy-state transition. The real refresh
scheduler is retained. No view state, presented totals, or status label is edited
directly, and no additional polling loop is introduced.

## Fixture scenarios

The normal scenario contains 50 Astra requests with 100,000 input and 20,000
output tokens and 50 Sol requests with 100,000 input and 80,000 output tokens.
Cache-read/write counts are explicitly zero, and reasoning tokens are an output
subset. The production pricing catalog calculates the values; the UI receives
records, never precomputed USD totals. At the checked-in Standard rates the cycle
is $150. The $200 case uses 50 Astra and 100 Sol requests; the $250 case uses
100 Astra and 50 Sol requests.

Records span the current local subscription cycle, the current day, and both
sides of the seeded reset interval. Three fictional conversation names exercise
the real recent-conversation presentation, including long-title truncation. All
displayed conversation totals are accumulated since the saved tracking start;
older lifetime totals are excluded.
Quota data includes primary and secondary windows, two other limits, and two
reset cards with distinct expiries.

| Control | Expected evidence |
| --- | --- |
| Complete $150 | Known cycle value below $200; center mark present |
| Exactly $200 / Above $250 | Center mark absent |
| 14.9% / 15% | Red only at 14.9%; ordinary color exactly at 15% |
| Partial records | Known lower bounds use `≥`; comparison unavailable |
| Legacy estimate | Estimates use `≈`, with bounded pricing uncertainty |
| Unknown pricing | Tokens remain visible; USD is unavailable |
| Service-only omitted | Account date/lifetime buckets do not enter prospective local totals |
| Unavailable | Missing quota and usage remain unavailable |
| Read failure | After a successful scenario, old values remain visibly stale |
| Offline / Online | Offline suspends reads; online resumes through the store |
| AC / Battery | Existing cadence changes between one and five minutes |

Changing a scenario while offline queues the fixture choice until the next
allowed refresh. **Restore QA defaults** uses the public store actions to restore
day 5, Chinese, Project A, and the $150 fixture. It does not edit production
preferences.

The offline renderer also demonstrates a first partial subscription cycle in
its light-appearance fixtures: tracking starts on October 3 inside a September 5
to October 5 cycle. Today and recent-conversation values cover the new tracking
range; reset/cycle totals show only the known portion, and the center comparison
mark is absent. Dark-appearance fixtures start tracking at the cycle boundary
and retain the complete-cycle comparison example. All dates use fictional 2030
fixtures. These are layout images, not interactive acceptance screenshots.

## Computer-tool gate — unperformed

Building or launching this harness is not UI acceptance. Capture and inspect
the actual running app using the Computer tool before marking any row passed.

1. Open the real panel. Inspect the menu label, main quota, all three period rows,
   coverage label, tracking-start date, reset-card count and both expiry rows.
2. Expand conversations and other limits using the whole row. Confirm the top
   anchor stays fixed and the panel grows downward without jumping or clipping.
3. Toggle Chinese/English in the actual panel. Reopen, then relaunch the QA app to
   verify the language persists. Inspect both light and dark appearances.
4. Use the actual billing-day picker to select another day, clear it, and restore
   day 5. Reopen/relaunch to verify the selected day persists.
5. Open the actual folder picker, choose only the synthetic Project A/B folders,
   clear sources, and select them again. Verify unavailable coverage and recovery.
6. Exercise each scenario in the table, including failure after a good snapshot
   and recovery after failure. Inspect hover help for approximate dates, observed
   reset intervals, API-equivalent pricing, and selected-source comparison scope.
   Confirm tracking-date help excludes earlier history and explains why the
   first partial cycle cannot trigger the below-$200 comparison.
7. Inspect keyboard focus, accessibility labels and VoiceOver behavior. A visual
   screenshot alone does not establish accessibility compliance.
8. Use the real panel's refresh and quit actions. Confirm the QA process exits;
   do not close or restart Codex or the computer as part of this test.

Save only screenshots of this synthetic app. Record actual observations and
remaining gaps; do not infer successful interaction from compilation, offline
PNG renders, or process presence.
