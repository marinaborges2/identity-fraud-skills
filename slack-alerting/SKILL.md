---
name: slack-alerting
description: >-
  Send enriched Slack alerts for detected anomalies and export customer lists as
  Parquet. Use when asked to send alerts, notify Slack, format anomaly results,
  export anomalous customers, or build alert messages.
---

# Slack Alerting — Narrative Anomaly Alerts

Formats anomaly detection results into enriched, narrative-first Slack alerts and exports full customer lists as Parquet files for investigation.

## Input Contract

Expects:
1. **`results_df`** — Pandas DataFrame with detection results (output of `statistical-detection` skill)
2. **`skipped_countries`** — dict of `(country, time_window) → num_weeks` for skipped combinations
3. **`detailed_df`** (optional) — Spark DataFrame with per-customer event data for sampling
4. **`export_source_df`** (optional) — Spark DataFrame for Parquet export of flagged customers

## Configuration

```python
ALERT_LOOKBACK_DAYS = 15
SHUFFLE_URL = "https://backoffice.nubank.com.br/shuffle/#/person"
COUNTRY_FLAGS = {"BR": "🇧🇷", "CO": "🇨🇴", "MX": "🇲🇽"}
MAX_DEVIATION_DISPLAY = 500
SLACK_WEBHOOK_URL = dbutils.secrets.get(scope="identity-fraud", key="slack_webhook")
```

## Display Rules

- **Deviation > 500%**: treat as insufficient baseline — show "_insufficient baseline_" in cross-country overview
- **Week-over-week > 500%**: show "*well above/below* last week (X → Y customers)"
- **Expected range**: floor lower bound at 0 — `max(0, iqr_lower)`
- **Confidence**: `(1 - 2 * norm.sf(|z_score|)) * 100`
- **Last anomaly**: show date + weeks ago, or "_none in the last 12 months_"
- **Customer links**: clean format — just numbered Shuffle links, no extra text

## Alert Limits

- **Only alert on anomalies from the last `ALERT_LOOKBACK_DAYS` (15 days)**
- Show only **top 5 anomalies** by |z-score|, deduplicated by country
- Webhook via Databricks Secrets

## Cross-Country Overview

**Always list ALL expected countries** (BR, CO, MX), never omit one:

| Situation | Display |
|---|---|
| Normal data available | `🇧🇷 BR: ⬆️45%` |
| Deviation > 500% | `🇧🇷 BR: _insufficient baseline_` |
| Rolling mean is 0 or NaN | `🇧🇷 BR: _insufficient data_` |
| Skipped (< MIN_DATA_POINTS) | `🇧🇷 BR: _skipped — 3 weeks (min 10)_` |

## Parquet Export

For each confirmed anomaly, export the full list of flagged customers to DBFS.

**Path pattern**: `/dbfs/anomaly_exports/{variable_slug}/{date}_{country}_{window}.parquet`

## Common Pitfalls

| Issue | Symptom | Fix |
|---|---|---|
| Country missing from overview | Country silently omitted | Always list all expected countries; use `skipped_countries` dict |
| Negative expected range | `Expected range: -5 – 10` | `max(0, iqr_lower)` |
| Absurd percentages in alert | `1192675%` displayed | Cap with `MAX_DEVIATION_DISPLAY`; show descriptive text |
| Empty summary DataFrame | `ValueError: can not infer schema` | Guard `if summary.empty:` before `spark.createDataFrame()` |
| Old anomalies triggering alerts | Alert for November data in March | Filter by `ALERT_LOOKBACK_DAYS` before sending |
| Extra text after customer IDs | `(ratio: X%)` after link | Keep links clean: just `  1. <URL|ID>` |