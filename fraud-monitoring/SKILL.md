---
name: fraud-monitoring
description: >-
  End-to-end fraud indicator monitoring pipeline. Composes data-extraction,
  statistical-detection, and slack-alerting skills to create a complete anomaly
  detection notebook. Use when asked to create monitoring for a new fraud
  variable, build an anomaly detection pipeline, or set up end-to-end anomaly
  detection with alerts.
---

# Fraud Monitoring — End-to-End Pipeline

Composes three specialized skills to create a complete Databricks anomaly detection notebook for any fraud indicator. Given a variable name and a source notebook, it generates the full pipeline from data extraction to Slack alerts.

## Workflow

1. **User provides**: variable name + source notebook
2. **Agent follows Step 1** (Data Extraction) to understand and replicate source logic
3. **Agent follows Step 2** (Statistical Detection) to add anomaly detection
4. **Agent follows Step 3** (Slack Alerting) to configure alerts and exports
5. **Agent assembles** everything into a single notebook and uploads to Databricks

## Step 1 — Data Extraction

Read and follow the skill at `~/.cursor/skills/data-extraction/SKILL.md`.

Use it to:
- Read the source notebook and its `%run` dependencies
- Generate PySpark extraction code per country (BR, CO, MX)
- Apply two-level checkpoint strategy
- Aggregate data into weekly cohorts

**Output**: a Pandas DataFrame `pdf` with columns `country`, `cohort_week`, `unique_customers`, `total_events` (and optionally `time_window`).

## Step 2 — Statistical Detection

Read and follow the skill at `~/.cursor/skills/statistical-detection/SKILL.md`.

Use it to:
- Apply Z-score (rolling 12w, ±3.0σ) + IQR (2.0x) detection
- Confirm anomalies when both methods agree + deviation ≥ 30%
- Track skipped countries with insufficient data
- Generate two-panel visualization charts

**Output**: a Pandas DataFrame `results_df` with detection columns + a `skipped_countries` dict.

## Step 3 — Slack Alerting

Read and follow the skill at `~/.cursor/skills/slack-alerting/SKILL.md`.

Use it to:
- Format a narrative-first Slack alert with cross-country overview
- Include customer samples with Shuffle links
- Export flagged customers as Parquet to DBFS
- Show summary table of confirmed anomalies

**Input**: `results_df` and `skipped_countries` from Step 2, plus the Spark DataFrames from Step 1.

## Step 4 — Assemble the Notebook

Combine all generated code into a single `.py` Databricks notebook with these sections (in order):

| Cell | Section | Source |
|---|---|---|
| 1 | Markdown: Title & description | — |
| 2 | Configuration (thresholds, seasonality, flags) | All skills |
| 3 | Imports + checkpoint dir | `data-extraction` |
| 4 | Start date | `data-extraction` |
| 5-10 | Data extraction per country | `data-extraction` |
| 11 | Union + aggregation | `data-extraction` |
| 12 | Detection functions | `statistical-detection` |
| 13 | Detection loop | `statistical-detection` |
| 14 | Visualization | `statistical-detection` |
| 15 | Alert builder + helpers | `slack-alerting` |
| 16 | Parquet export | `slack-alerting` |
| 17 | Send alert | `slack-alerting` |
| 18 | Summary table | `slack-alerting` |

## Using Skills Independently

Each skill can be used standalone:

| Need | Skill to use |
|---|---|
| Extract data from a Scala notebook | `data-extraction` only |
| Detect anomalies on existing aggregated data | `statistical-detection` only |
| Send Slack alerts for any detection results | `slack-alerting` only |
| Full pipeline from source to alert | `fraud-monitoring` (this skill) |

## Common Pitfalls (all skills combined)

| Issue | Symptom | Fix |
|---|---|---|
| Self-join on remote tables | `Py4JJavaError` | Two-level `.checkpoint()` |
| Wrong table per country | `TABLE_OR_VIEW_NOT_FOUND` | Check source notebook per country |
| Hidden `.transform()` logic | `UNRESOLVED_COLUMN` | Read `%run` dependency notebooks |
| Indentation after `continue` | Empty results | Verify loop indentation |
| Country missing from alert | Silent omission | Track skipped countries explicitly |
| Empty summary DataFrame | `ValueError: can not infer schema` | Guard `if summary.empty:` |
| Old anomalies alerting | Stale alerts | Filter by `ALERT_LOOKBACK_DAYS` |
| Absurd percentages | `1192675%` | Cap at `MAX_DEVIATION_DISPLAY` (500%) |