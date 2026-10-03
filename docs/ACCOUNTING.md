# Usage accounting / 用量统计

The 1.7.0 development branch adds token statistics and **current Standard API-equivalent USD**. Desktop acceptance and the release are still pending. This comparison is not a bill, credit balance, refund or demonstrated saving.

1. 在统计设置中选择每月续费日。周期以本机时区的当天 00:00 划分；日期不足的月份取最后一天。这里只知道续费日，不推断支付平台精确扣费时间。
2. 选择允许纳入的项目目录。目录用于精确匹配对话的工作目录，**不递归扫描文件夹或整个会话库**。嵌套项目有不同工作目录时，需要分别选择。
3. 面板显示今日、本周期及重置观测以后的 Token / API 等值，并显示所选范围最近三个根对话。切换语言不会重新查询，修改日期会本地重算；更改来源取消旧读取并清除旧范围的数据。

## Meaning of the numbers

| Mark | Meaning |
| --- | --- |
| `—` | Required records, model price or period boundary are unavailable. |
| `≥` | Known lower bound from a partial set of reported records. |
| `≈` | Estimated legacy telemetry, or service-date totals whose timezone is undocumented. This is not a guaranteed lower bound. |
| `$a–b` | Applicable token-price bounds for a complete priced scope; missing requests are not included in the upper bound. |
| Ring `!` | The **selected sources** have a complete current-cycle scan, no estimated current-cycle records, and a priced upper bound below USD 200. Account-wide/cross-device coverage remains unverified. |

No value is derived from quota percentage. Unknown models retain their token counts and remain unpriced. The rate catalogue distinguishes ordinary input, cache reads, cache writes and output. Reasoning is already included in output. Long-context rules apply to the request, never to the whole day's cumulative tokens. See [pricing and official sources](PRICING.md).

The three time-period rows use selected local request records when available. Otherwise, the service's dated account buckets can supply approximate date totals, but no dollar equivalent: the account endpoint does not provide the required model/category breakdown or documented bucket timezone. Missing dates are not assumed to have zero usage.

The next quota reset is not proof of the last reset. The app observes a usage drop and a moved reset schedule, preserving the interval between observations. The “since reset” row counts records after the interval's end and marks the result partial. Before any reset has been observed, it remains unavailable. Account or quota-window changes invalidate previous reset evidence.

For recent conversations, the app prefers service-reported per-conversation model groups. The fallback counts that conversation's own local records. Descendant-agent inclusion in the service response is undocumented; this tool does not claim a complete agent-tree total. A user-assigned conversation title may be displayed locally; message previews are never substituted as titles.

## Data and privacy

- Authentication remains inside the installed Codex CLI. This app does not read/copy authentication files, use API keys, call a model, redeem resets or purchase credits.
- Read-only protocol calls are `account/rateLimits/read`, `account/usage/read`, and, after scope selection, `thread/list` with exact `cwd` filters and `useStateDbOnly: true`. See the [official app-server documentation](https://learn.chatgpt.com/docs/app-server).
- Empty scope never calls `thread/list`. Paths returned for selected directories must be absolute JSONL files beneath the standard local session roots; symlinks and traversal paths are rejected.
- The parser decodes only usage metadata. Prompts, responses and previews are not part of its model and are not saved. Modern request records are deduplicated by response ID; inherited fork history is excluded. Legacy cumulative telemetry remains an estimate.
- Runtime request records and parser caches remain in memory. App preferences hold language, renewal day, selected directories and minimal reset observations. None of these private settings or actual usage records is packaged or published.
- Initial history catch-up is bounded per refresh and explicitly partial. Later refreshes read appended bytes; cancellation, account changes, scope changes and file replacement invalidate the appropriate cached state.
- One temporary Codex process serves a refresh, then exits. The existing AC/battery cadence and sleep/offline policy remain in force. There is no extra polling timer or continuously running animation.

## Limits that remain visible

Cloud-only, other-device, deleted, unreadable, excluded and not-yet-imported records are not silently counted as zero. Exact project matching can omit conversations moved between directories. Model attribution from recorded turn context is an API comparison basis, not proof of the backend's final routing. The pricing snapshot uses current published rates, not reconstructed historical invoices.

Synthetic parser, pricing, calendar, aggregation and process tests are necessary but do not establish real desktop usability or complete personal-account coverage. Those checks are tracked separately in [design review](DESIGN_REVIEW.md) and [acceptance requirements](REQUIREMENTS.md).
