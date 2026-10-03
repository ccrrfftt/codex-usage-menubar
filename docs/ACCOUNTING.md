# Tracking scope and start date

The user-selected local project roots and their descendants define the accounting
scope. Tracking begins at local midnight on first activation. The start is saved
as `accountingTrackingStart` in the local preference domain and never advances
merely because the app restarts or the calendar date changes. No personal date or
project path is compiled into the distributable.

Only requests at or after this start contribute to today, reset and subscription
cycle totals. An old conversation can continue contributing new records. Its old
cumulative counters are used only as a baseline, not counted as new usage. The
latest three conversations show cumulative usage since this tracking start.
The prospective path does not query account-wide or per-thread lifetime totals.

The first subscription cycle is partial if it began before tracking. Its values
show the known subtotal and cannot trigger the below-$200 comparison. Later full
cycles use the confirmed local scope; records from other devices and outside the
selected roots are not part of that comparison.

The local Codex index is read-only and filters inactive pre-start conversations
before the row limit. Existing active logs are decoded incrementally so earlier
turn contexts and counter baselines can be preserved without importing old usage.
While the app is closed, Codex can continue writing its own records; on the next
launch those retained records are read again from the fixed start and deduplicated.
The app does not promise recovery of logs deleted from Codex, an unsupported
future format, or records outside its configured sources. Incomplete coverage is
shown explicitly; missing data is never silently converted to a complete zero.

A successful, empty scoped index is a known zero since tracking began. A missing
or incompatible index, unavailable source, interrupted import or row cap is not.
All accounting follows the existing power-aware polling schedule.

---

# Usage accounting / 用量统计

The 1.7.0 development branch adds token statistics and **current Standard API-equivalent USD**. Desktop acceptance and the release are still pending. This comparison is not a bill, credit balance, refund or demonstrated saving.

1. 在统计设置中选择每月续费日。周期以本机时区的当天 00:00 划分；日期不足的月份取最后一天。这里只知道续费日，不推断支付平台精确扣费时间。
2. 选择允许纳入的项目目录。根目录会覆盖其下的工作目录。应用通过只读会话索引查找相应记录，**不会遍历项目源码目录**；相似名称的相邻目录不在范围内。
3. 面板显示今日、本周期及重置观测以后的 Token / API 等值，并显示所选范围最近三个根对话。切换语言不会重新查询，修改日期会本地重算；更改来源取消旧读取并清除旧范围的数据。

## Meaning of the numbers

| Mark | Meaning |
| --- | --- |
| `—` | Required records, model price or period boundary are unavailable. |
| `≥` | Known lower bound from a partial set of reported records. |
| `≈` | Estimated legacy telemetry. This is not a guaranteed lower bound. |
| `$a–b` | Applicable token-price bounds for a complete priced scope; missing requests are not included in the upper bound. |
| Ring `!` | The **selected sources** have a complete current-cycle scan, no estimated current-cycle records, and a priced upper bound below USD 200. The comparison is explicitly local; other devices are outside the accepted scope. |

No value is derived from quota percentage. Unknown models retain their token counts and remain unpriced. The rate catalogue distinguishes ordinary input, cache reads, cache writes and output. Reasoning is already included in output. Long-context rules apply to the request, never to the whole day's cumulative tokens. See [pricing and official sources](PRICING.md).

The three time-period rows use selected local request records from the saved tracking start. Production tracking never substitutes account-wide service-date totals or per-conversation lifetime counters. Those sources do not match the selected local scope and prospective time boundary.

The next quota reset is not proof of the last reset. The app observes a usage drop and a moved reset schedule, preserving the interval between live observations. Post-start records can supply numeric quota snapshots to bootstrap an estimated reset observation for the same current allowance window; unidentified or different-model limits are excluded. The “since reset” row counts records after the interval's end and marks the result partial. The row identifies the allowance period (for example, the 7-day limit). Historical inference is marked estimated because the exact instant and historical account identity are not provided. Without compatible live or historical evidence, it remains unavailable. Account or quota-window changes invalidate previous reset evidence.

For recent conversations, the app counts each conversation's own local records since the tracking start. Child-agent usage contributes to overall scoped totals but is not rolled into its parent conversation's row. The local index does not read conversation titles. Rows use a sequence number and activity time; an optional explicit service-provided name can still be displayed. Message previews are never substituted as titles.

## Data and privacy

- Authentication remains inside the installed Codex CLI. This app does not read/copy authentication files, use API keys, call a model, redeem resets or purchase credits.
- Production tracking calls `account/rateLimits/read` after the standard handshake; it does not request account or conversation lifetime usage. A separate read-only SQLite projection selects thread IDs, times and rollout locations under the chosen roots; it never selects titles or previews. The app-server child keeps its isolated database. See the [official app-server documentation](https://learn.chatgpt.com/docs/app-server).
- Empty scope never opens the thread index or calls `thread/list`. Normal operation has no global thread listing. The internal exact-directory compatibility fallback is disabled by default and marks recursive coverage incomplete when explicitly enabled. Rollout paths must be absolute JSONL files beneath configured Codex session roots; symlinks and traversal paths are rejected.
- The parser decodes only usage metadata. Prompts, responses and previews are not part of its model and are not saved. Modern request records are deduplicated by response ID; inherited fork history is excluded. Legacy cumulative telemetry remains an estimate.
- Runtime request records and parser caches remain in memory. App preferences hold language, renewal day, selected directories, the fixed tracking start and minimal reset observations. None of these private settings or actual usage records is packaged or published.
- Initial catch-up of post-start records is bounded per refresh and explicitly partial. Later refreshes read appended bytes; cancellation, account changes, scope changes and file replacement invalidate the appropriate cached state.
- One temporary Codex process serves a refresh, then exits. The existing AC/battery cadence and sleep/offline policy remain in force. There is no extra polling timer or continuously running animation.

## Limits that remain visible

Cloud-only, other-device, deleted, unreadable, excluded and not-yet-imported records are not silently counted as zero. Historical working directories are used as recorded. Moving a project does not automatically associate its former paths with the new root. Model attribution from recorded turn context is an API comparison basis, not proof of the backend's final routing. The pricing snapshot uses current published rates, not reconstructed historical invoices.

Synthetic parser, pricing, calendar, aggregation and process tests are necessary but do not establish real desktop usability or complete personal-account coverage. Those checks are tracked separately in [design review](DESIGN_REVIEW.md) and [acceptance requirements](REQUIREMENTS.md).

## Compatibility evidence and limits

The index uses the official `state_5.sqlite` schema and respects documented
`CODEX_HOME` and `CODEX_SQLITE_HOME` environment overrides. It does not parse
private `config.toml`; a custom `sqlite_home` configured only there requires the
matching environment override. Unsupported schema and unavailable indexes remain
visible as incomplete coverage. Non-OpenAI providers and internal sessions are
excluded; an OpenAI provider name does not prove historical account ownership.

The official personal daily analytics route was also examined. In the sanitized
runtime contract check, the response carried per-model relative usage but no
input, cache, output or total-token fields. Those values are not a substitute for
API-priceable token counts. No delegated authentication or extra HTTP transport
was added to the shipped application on that basis.
