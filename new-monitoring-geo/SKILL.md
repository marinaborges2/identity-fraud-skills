---
name: new-monitoring-geo
description: >-
  Onboard a new geography (geo) into the Identity Fraud unified monitoring
  dashboard (fraud-monitoring): discover sources ONLY via Free Willy / registered
  etl contracts, build a Scala metrics notebook, write S3 Parquets, wire agent
  configs + COUNTRY_MAP, and render Fraud Rate / Losses / Policy tabs. Never
  invent datasets, metrics, fraudsters, losses, policies, or other facts. Use
  when adding a real country/geo to the monitoring dash (US/Troy/CO/MX-style).
  Do NOT invent fake geos or Winterfell-style synthetic data.
---

# New Monitoring Geo — Dashboard Onboarding

Runbook to add a **real** geo to the unified Identity Fraud monitoring dashboard.
Reference implementation: **US (Troy)** — notebook pattern in
`~/Desktop/us-monitoring/us_monitoring_metrics.scala` (or Workspace copy under
`fraud-monitoring/notebooks/`).

## Non-negotiables (read before any phase)

### 1) Sources come from Free Willy

Every input table **must** be a real dataset discoverable in **[Free Willy](https://backoffice.nubank.com.br/free-willy/)** (Datasetcard / search / lineage / series contract). Prefer registered names like `etl.<geo>__contract.*` / `etl.<geo>__data_source.*` that appear in Free Willy with `is_present_on_etl` (or equivalent) and a known owner/domain.

**How to discover (required in Phase 1):**

1. Search Free Willy Datasetcard for the geo + domain (acquisition, big_mama, risk_platform, …).
2. Confirm dataset name, country, layer, owner squad, and that it is present on ETL.
3. Only then use that exact Spark/Unity Catalog name in the notebook (`spark.table(...)` / `SHOW TABLES` as a secondary check — never as the only discovery).
4. Record each chosen dataset in the capability matrix with the Free Willy name + link/path.

**Forbidden:** guessing table names, copying BR/MX/CO table strings and “hoping” a Troy twin exists, reading ad-hoc CSVs/manual sheets as if they were production metrics, or inventing schema columns that Free Willy / the contract do not expose.

### 2) Never invent data or information

If it was not computed from a Free Willy–backed table (or an explicit user-confirmed live policy list for **seeding empty chart series**), do not put it in Parquets, payloads, insights, labels, or handoff text.

| Situation | Allowed | Forbidden |
|---|---|---|
| Metric has no Free Willy source / helper | `null` + `unavailable_reason` in contract; document in matrix | Fake rates, made-up losses, synthetic fraudsters |
| Source exists but rows are 0 (e.g. no `fraudster`) | Keep **real** zeros from the query | Inflating FID / inventing statuses |
| Chart UI hides all-null series | **Zero-fill for display only**, same periods as fraud rate; handoff must say “no feed / chart UX”, not “measured zero loss” | Presenting UX zeros as measured KPIs |
| Policy not seen in BM yet but confirmed live | Seed zero series for that named policy | Inventing policy names, report counts, or precision |
| Unknown fact (owner, column meaning, threshold) | Ask user or leave null / “unknown” | Guessing in insights, actions, or docs |

Sibling context:
- Repo: `fraud-monitoring` (agents + `pipeline/dashboard.py` + template)
- Helpers SoT: `IdentityFraudUtils` in `nubank/fraud-identity-job-repo`
- Metric KB: [Defenses Monitoring Metric Definitions](https://nubank.atlassian.net/wiki/spaces/KYC/pages/265589784931/Defenses+Monitoring+Metric+Definitions+Data+Sources+KB)
- Free Willy: [portal](https://backoffice.nubank.com.br/free-willy/) · search catalog often via `usr.free_willy.search`

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

### 1.1 Find geo analogues via Free Willy (required)

**Primary:** Free Willy Datasetcard / search for each need below.  
**Secondary:** Glean `code_search` + Databricks `SHOW TABLES` only to **confirm** a Free Willy hit, never to invent a candidate.

| Need | Typical Free Willy / ETL pattern | US example |
|---|---|---|
| Acquisition / customers | `etl.<geo>__contract.acquisition__account_requests` | Troy AR |
| FID / Big Mama | `etl.<geo>__contract.big_mama__reports` | status `fraudster`, type `id` |
| Scorer | `etl.<geo>__data_source.risk_platform_{event,scorer}` | scorer name may have leading `:` |
| Losses | helpers `getLossesAmountbyCID*` over Free Willy loss feeds | **often missing** → null |
| Money saved / report source | `getMoneySaved*`, `getReportSource*` | often missing → null |
| Policy weekly | curated policyperformance **or** BM reports from Free Willy | often build-from-BM |

For each row that is `available` / `build-from-BM`, capability matrix must cite the **exact Free Willy dataset name**. If Free Willy has no match → status `null` (do not approximate with another country’s table).

Also read `IdentityFraudUtils` for `*US` / `*<GEO>*` helpers. **Port logic into the notebook** if the geo is not on the shared lib classpath; helpers still read Free Willy–backed tables only.

### 1.2 Capability matrix (required artifact)

Publish **before** writing notebook code:

| Metric | Status | Free Willy dataset(s) or reason |
|---|---|---|
| Fraud rate + customers | available / null | `etl.…` or “not in Free Willy” |
| Pre-release capture | available / null | … |
| Scorer band mix | available / null | … |
| $ Losses (+ dims) | available / null | … |
| Money saved | available / null | … |
| Report source | available / null | … |
| Policy performance | available / build-from-BM / null | … |

**Rules:** unavailable → **null** in contracts. Do not fabricate fraudsters, losses, policies, or substitute another geo’s numbers.

---

## Phase 2 — Scala Metrics Notebook + S3

Create `<geo>_monitoring_metrics` (Scala Databricks notebook). Use US notebook as template.

Minimum sections:

1. **Config** — `GEO`, `GEO_LABEL`, `CURRENCY`, `S3_ROOT`, `reportDate` = last Sunday, ~19-week window
2. **Helpers** — port `getCustomerData*`, `getFraudstersID*`, `getScorer*ByCID` as needed
3. **Load tables** — only Free Willy–confirmed names; optional fallbacks must each be Free Willy–confirmed (no speculative names)
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

1. Capability matrix (final) **with Free Willy dataset names** for every `available` / `build-from-BM` cell.
2. S3 root + notebook path.
3. Local HTML path + how to open.
4. What is **measured** vs **null** vs **zero-filled for chart UX only** (never conflate).
5. Policy list (aggregated names) + live policies still at zero (and how those names were confirmed).
6. Follow-ups (pipeline PR, missing IdentityFraudUtils helpers, missing Free Willy datasets to request from data owners).

---

## Anti-patterns

- Using tables that do not appear in Free Willy / are not present on ETL
- Guessing `etl.<geo>__…` names from BR/MX/CO without Free Willy confirmation
- Creating fake geos or synthetic Winterfell data to "demo" the tab
- Inventing losses / fraudsters / policies / insights / thresholds when sources do not support them
- Copying another country’s time series into the new geo “so charts look full”
- Presenting chart UX zeros as if they were measured KPIs
- Leaving every `back_office_*` / `batch_policy_*` as separate noisy entities without asking
- Skipping `COUNTRY_MAP` (tab shows raw slug / wrong flag)
- Shipping only null losses when the user wants a visible empty chart → zero-fill **and** document UX-only
- Amending production Julio/Gabriela Parquet paths for other geos

## Additional resources

- [reference.md](reference.md) — S3 layout, helper inventory, payload shapes, policy mapping notes
