# New Monitoring Geo — Reference

Supporting detail for [`SKILL.md`](SKILL.md). Read when implementing Phases 2–5.

---

## Canonical repos & paths

| What | Where |
|---|---|
| Dashboard agents + template | `fraud-monitoring` (`agents/{fraud_rate,losses,policy}/`, `pipeline/dashboard.py`, `dashboard_template.html` or `templates/`) |
| Identity Fraud helpers SoT | `nubank/fraud-identity-job-repo` → `IdentityFraudUtils` |
| US reference notebook (local) | `~/Desktop/us-monitoring/us_monitoring_metrics.scala` |
| US Workspace notebook | `/Workspace/Users/<user>/fraud-monitoring/notebooks/us_monitoring_metrics` |
| Metric definitions KB | https://nubank.atlassian.net/wiki/spaces/KYC/pages/265589784931/Defenses+Monitoring+Metric+Definitions+Data+Sources+KB |

Existing geos in production dash: **br**, **mx**, **co**. Curated weekly trees historically under Julio/Gabriela `nu-tmp/.../monitoring/...`. New geos often have **no** curated tree — build from contracts.

---

## IdentityFraudUtils — US helper inventory (pattern)

Present for US:

- `getCustomerDataUSFull(accountRequestsUS)`
- `getFraudstersIDUS(bigMamaReportsUS)` — `report__type == "id"` and `report__status == "fraudster"`
- `getScorerUSByCID(scorerName)(riskPlatformEventUS, riskPlatformScorerUS)`

Typically **absent** for US (treat as null until implemented):

- `getLossesAmountbyCIDUS` / product variant
- `getMoneySavedUS`
- `getReportSourceUS`

For a new geo: search `def get.*<GEO>` / `def get.*<Country>` in the same file. If only BR/MX/CO variants exist, port the closest helper and adapt table columns.

---

## Suggested S3 layout

Root: `s3://nu-tmp/<user>/monitoring/<geo-folder>/`

```
fraud_rate/rate
fraud_rate/rate_by_product
fraud_rate/released_rate
fraud_rate/released_rate_by_product
fraud_rate/scorer_band_mix          # optional
customers/spine                     # optional debug
losses/total_losses
losses/tenure
losses/product
losses/fraud_type
losses/report_source
policy/policyperformance            # weekly policy rows or stub
```

Write with Snappy Parquet overwrite. Keep a small `manifest` DF in the notebook (geo, report_date, available, null_stubs).

---

## Fraud-rate weekly schema (minimum)

| Column | Type | Notes |
|---|---|---|
| `cohort_week` | date | week truncated from `confirmed_at` |
| `customers` | long | distinct CIDs |
| `fraudsters` | long | distinct FID CIDs |
| `fraud_rate` | double | `fraudsters * 100.0 / customers` |
| `country` | string | geo slug |
| `product` | string | only on by-product tables (`cc` / `nuconta` / …) |

Capture tables reuse the same shape; metric is share of FID with `released_at IS NULL`.

---

## Losses: null stub vs zero series

**Parquet / contract:** null columns + `unavailable_reason` is fine for honesty.

**Dashboard chart:** if the UI hides series when all values are null, inject a **zero-filled** time series aligned to fraud-rate `periods` so "Total Losses Over Time" shows a flat line at currency 0. Document that zeros mean "no loss feed", not "measured zero loss", unless true.

---

## Policy weekly schema (from Big Mama)

| Column | Type | Notes |
|---|---|---|
| `reported_at_week` | date | week of `report__created_at` |
| `policy` | string | mapped slug |
| `reports` | long | count of reports |
| `fraudsters` | long | status `fraudster` |
| `precision` | double | `fraudsters/reports*100` or 0 |
| `release_stage` | string | `PRE-RELEASE` / `POST-RELEASE` |
| `country` | string | geo slug |

### Aggregation defaults

| Pattern | Output entity |
|---|---|
| `back_office_*` | `backoffice` |
| `batch_policy_*` (abuse packs, not IDF ID rules) | `batch_policy` |
| IDF batch / stadium policies | keep separate |

Sum `reports` / `fraudsters` across members; recompute `precision` on the aggregate.

### Policy entity fields expected by the HTML

Mirror a donor geo (`mx`/`co`) entity:

- Identity: `name`, `section`, `release_stage`
- Currents: `reports_current`, `fraudsters_current`, `precision_current`, `source_rate` (often null)
- Deltas: `reports_pop`, `fraudsters_pop`, `precision_pop`, `*_4wk`, `*_12wk`, `*_cls`
- Labels: `entity_label`, `entity_direction`, `entity_label_slot`, `compound`, `early_warnings`
- Series: `time_series: { periods, reports, fraudsters, precision }`
- Narrative: `insight`, `action`, `watch`, consecutive_* flags

Country-level: `summary`, `pre_release`, `post_release` count maps; optional `ew_intelligence`, `system_event`, `hidden_policies`.

---

## Config wiring snippets

**fraud_rate / losses** — `countries.<geo>` with `label`, `currency_symbol`, `currency_code`, `timezone`, `slack_channel`, `thresholds`, `dimensions` → `parquet\`s3://...\`` tables.

**policy** — top-level key is `policies.<geo>` (not `countries`), with `table` pointing at policyperformance Parquet.

Copy thresholds from the closest mature geo; do not invent new threshold schemes on first onboarding.

---

## COUNTRY_MAP

In the HTML template JS:

```js
var COUNTRY_MAP={
  br:{flag:'🇧🇷',name:'Brasil'},
  mx:{flag:'🇲🇽',name:'México'},
  co:{flag:'🇨🇴',name:'Colombia'},
  us:{flag:'🇺🇸',name:'United States'}
  // add new geo here
};
```

Tabs are driven by countries present in the injected `agents.*.countries` / `agents.policy` payload **and** this map for flag/label.

---

## HTML inject procedure (prototype)

1. Locate the embedded JSON blob containing `"agents"`.
2. Deep-copy a donor country payload for each agent (`fraud_rate`, `losses`, `policy`).
3. Replace series/entities from geo Parquets or exported JSON (`dbfs:/tmp/...` → local via `databricks fs cp`).
4. Set `country` / `country_code` / `country_label` / `currency_symbol` / `report_date`.
5. Rewrite the blob with `json.dumps(..., ensure_ascii=False, default=str)`.
6. Update `COUNTRY_MAP` in the same file.
7. `open` the file locally for QA.

Prefer promoting this to the real multi-country pipeline once Parquets + configs are stable.

---

## Discovery checklist for live policies

1. Search job-repo / Stadium for geo-tagged IDF policies (batch reason codes, external-check/Socure, liveness, face-match, HoF, …).
2. Confirm which write into Big Mama (`report__type`, reason codes, status enum).
3. Map hits → entity names; seed misses with zero series + `POST-RELEASE` or `PRE-RELEASE` as appropriate.
4. Note if all BM rows are `suspect_archived` (precision stays 0).

---

## Chart quirks (template)

- Some fraud-rate entity charts reuse the losses title string **"Total Losses Over Time"** and currency Y-axis formatting while plotting **customer counts**. Treat as template debt; do not "fix" data to match the title.
- Empty/null series may omit the chart entirely — prefer explicit zeros when the user wants a visible empty state.

---

## US (Troy) outcomes worth remembering

- Fraud rate built from AR + BM; FID can be 0 for weeks if no `fraudster` status.
- Scorer tables exist but CID join can still yield 0 rows (name / coverage) → leave null.
- Losses: no helper → zero chart series for UX.
- Policy: few BM reports; Socure/external-check had hits; IDF batch policies lived at zero; `backoffice` + `batch_policy` aggregations cleaned the tab.
