---
name: new-monitoring-geo
description: >-
  Onboard a new geography (geo) into the Identity Fraud unified monitoring
  dashboard (fraud-monitoring): discover Troy/local data sources, build a
  Scala metrics notebook, write S3 Parquets, wire agent configs + COUNTRY_MAP,
  and render/inject Fraud Rate, Losses, and Policy Performance tabs (null or
  zero where helpers/data do not exist). Use when the user asks to add a new
  country/geo to the monitoring dash, implement US/Troy/CO/MX-style monitoring
  for a new market, or automate "nova geo no dashboard". Do NOT invent fake
  geos or synthetic Winterfell-style datasets.
---

# New Monitoring Geo — Dashboard Onboarding

Runbook to add a **real** geo to the unified Identity Fraud monitoring dashboard.
Reference implementation: **US (Troy)** — notebook pattern in
`~/Desktop/us-monitoring/us_monitoring_metrics.scala` (or Workspace copy under
`fraud-monitoring/notebooks/`).

**Out of scope:** fake datasets, synthetic Winterfell tabs, or inventing metrics
that have no source.

Sibling context:
- Repo: `fraud-monitoring` (agents + `pipeline/dashboard.py` + template)
- Helpers SoT: `IdentityFraudUtils` in `nubank/fraud-identity-job-repo`
- Metric KB: [Defenses Monitoring Metric Definitions](https://nubank.atlassian.net/wiki/spaces/KYC/pages/265589784931/Defenses+Monitoring+Metric+Definitions+Data+Sources+KB)

Copy this checklist and track progress:

```
Geo onboarding:
- [ ] Phase 0 — Inputs confirmed
- [ ] Phase 1 — Source discovery + capability matrix
- [ ] Phase 2 — Scala metrics notebook + S3 Parquets
- [ ] Phase 3 — Agent configs + COUNTRY_MAP
- [ ] Phase 4 — Dashboard HTML (pipeline or inject)
- [ ] Phase 5 — Policy Performance from Big Mama (+ aggregation)
- [ ] Phase 6 — UX fixes (zeros for charts, open via macOS open)
- [ ] Phase 7 — Handoff summary
```

---

## Phase 0 — Gather Inputs

Confirm with the user before coding:

| Input | Example (US) | Notes |
|---|---|---|
| Geo slug | `us` | lowercase; keys configs + payload |
| Label | `United States` | tab display name |
| Flag emoji | 🇺🇸 | `COUNTRY_MAP` |
| Currency | `USD` / `US$` | symbol in payload |
| Databricks cluster | personal or fraud-bu | for notebook runs |
| S3 output root | `s3://nu-tmp/<user>/monitoring/<geo-folder>/` | weekly Parquets |
| Workspace notebook path | `/Workspace/Users/.../fraud-monitoring/notebooks/<geo>_monitoring_metrics` | |
| Live IDF policies | Socure, liveness, batch reason codes… | for Policy tab zeros + mapping |

Output: one-paragraph geo spec the user confirmed. Do not proceed without it.

---

## Phase 1 — Source Discovery + Capability Matrix

### 1.1 Find geo analogues of BR/MX/CO sources

Search (Glean `code_search` + Databricks `SHOW TABLES` / `spark.catalog`):

| Need | Typical pattern | US example |
|---|---|---|
| Acquisition / customers | `etl.<geo>__contract.acquisition__account_requests` | Troy AR |
| FID / Big Mama | `etl.<geo>__contract.big_mama__reports` | status `fraudster`, type `id` |
| Scorer | `etl.<geo>__data_source.risk_platform_{event,scorer}` | scorer name may have leading `:` |
| Losses | helpers `getLossesAmountbyCID*` | **often missing** for new geos |
| Money saved / report source | `getMoneySaved*`, `getReportSource*` | often missing |
| Policy weekly | curated `.../policyperformance/full/data.parquet` | often missing → build from BM |

Also read `IdentityFraudUtils` for `*US` / `*<GEO>*` helpers. **Port logic into the notebook** if the geo is not on the shared lib classpath; do not assume the JAR is available.

### 1.2 Capability matrix (required artifact)

Publish a table before building:

| Metric | Status | Source or reason |
|---|---|---|
| Fraud rate + customers | available / null | … |
| Pre-release capture | available / null | … |
| Scorer band mix | available / null | … |
| $ Losses (+ dims) | available / null | … |
| Money saved | available / null | … |
| Report source | available / null | … |
| Policy performance | available / build-from-BM / null | … |

**Rule:** unavailable → **null** in data contracts. Do not fabricate fraudsters, losses, or policies.

---

## Phase 2 — Scala Metrics Notebook + S3

Create `<geo>_monitoring_metrics` (Scala Databricks notebook). Use US notebook as template.

Minimum sections:

1. **Config** — `GEO`, `GEO_LABEL`, `CURRENCY`, `S3_ROOT`, `reportDate` = last Sunday, ~19-week window
2. **Helpers** — port `getCustomerData*`, `getFraudstersID*`, `getScorer*ByCID` as needed
3. **Load tables** — with candidate table-name fallbacks
4. **Customer spine + FID** — `cohort_week` from `confirmed_at`
5. **Fraud rate** — overall + by product → `fraud_rate/rate`, `fraud_rate/rate_by_product`
6. **Capture** — FID with `released_at IS NULL` → `fraud_rate/released_rate(+_by_product)`
7. **Scorer band mix** — if join yields rows; else leave null and document
8. **Null stubs** — losses dims + policy placeholder with `unavailable_reason`
9. **Manifest** — available vs null_stubs

Run on cluster; verify Parquet row counts under `S3_ROOT`.

Details: [reference.md](reference.md) § Notebook + S3 layout.

---

## Phase 3 — Agent Configs + COUNTRY_MAP

In `fraud-monitoring`:

1. **`agents/fraud_rate/config.json`** — add `<geo>` under `countries` (copy thresholds from closest geo; point `dimensions.*.table` at new Parquets).
2. **`agents/losses/config.json`** — same; even if stubs/zeros.
3. **`agents/policy/config.json`** — add under `policies` (note: key is `policies`, not `countries`).
4. **`COUNTRY_MAP`** in `dashboard_template.html` (and any baked HTML you edit):

```js
var COUNTRY_MAP={..., <geo>:{flag:'…', name:'…'}};
```

Do not leave orphan fake keys (`wf`, etc.) unless the user explicitly wants them.

---

## Phase 4 — Dashboard HTML

**Preferred:** run the unified pipeline so agents classify + `pipeline/dashboard.py` renders multi-country HTML.

**Prototype / first-geo path (used for US):** inject a `<geo>` country payload into an existing `dashboard_unified_*.html` by deep-copying a donor geo (`mx`/`co`) and replacing time series / entities from the new Parquets or JSON exports.

Payload must include for each agent country blob: `country`, `country_code`, `country_label`, `currency_symbol`, `report_date`, plus agent-specific entities/dimensions.

Open for review with macOS (Cursor `file://` links often fail):

```bash
open ~/Desktop/dashboard_unified_<date>_<geo>.html
```

---

## Phase 5 — Policy Performance from Big Mama

When curated policy Parquet does not exist:

1. List **live** IDF policies (Stadium + `fraud-identity-job-repo` batch reason codes).
2. Aggregate BM reports weekly: `reports`, `fraudsters` (`status=fraudster`), `precision`.
3. Map report types / reason codes → policy slugs (document unmapped).
4. Seed **known live policies with zero series** across the fraud-rate week spine if no hits yet.
5. **Aggregate noisy families** (do this by default for new geos unless user wants raw):
   - all `back_office_*` → single entity `backoffice`
   - all `batch_policy_*` (non-IDF abuse packs) → single entity `batch_policy`
6. Keep IDF policies as separate entities (`aws_age_id_report`, Socure/external-check, face-match, liveness, …).

Entity shape: [reference.md](reference.md) § Policy entity payload.

---

## Phase 6 — Chart / UX Hardening

Lessons from US:

| Issue | Fix |
|---|---|
| Losses / series all `null` → chart missing | Emit **zero** time series (same periods as fraud rate) so "Total Losses Over Time" renders flat at 0 |
| Fraud-rate UI hardcodes "— Total Losses Over Time" on customer bars | Do not reinterpret bars as $; if confusing, note in handoff — axis may be currency-styled while values are counts |
| Scorer name mismatch (`:identity-fraud-external-check` vs without `:`) | Try both; if still 0 rows after CID join → leave null |
| FID = 0 (only `suspect_archived`) | Valid; precision stays 0; do not invent fraudsters |
| HTML won't open from chat | Use `open <path>` / Finder |

---

## Phase 7 — Handoff Summary

Return to the user:

1. Capability matrix (final).
2. S3 root + notebook path.
3. Local HTML path + how to open.
4. What is real vs null vs zero-filled.
5. Policy list (aggregated names) + live policies still at zero.
6. Follow-ups (wire full agent pipeline PR, add missing IdentityFraudUtils helpers, etc.).

---

## Anti-patterns

- Creating fake geos or synthetic Winterfell data to "demo" the tab
- Inventing losses / fraudsters when helpers or BM statuses do not support them
- Leaving every `back_office_*` / `batch_policy_*` as separate noisy entities without asking
- Skipping `COUNTRY_MAP` (tab shows raw slug / wrong flag)
- Shipping only null losses when the user wants a visible empty chart → use zeros
- Amending production Julio/Gabriela Parquet paths for other geos

## Additional resources

- [reference.md](reference.md) — S3 layout, helper inventory, payload shapes, policy mapping notes
