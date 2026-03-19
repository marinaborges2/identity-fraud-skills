---
name: anomaly-detection
description: >-
  Detect anomalies in weekly time series using Z-score and IQR methods, with
  Slack alerts. Use when asked to detect anomalies, find outliers, monitor
  indicators, run anomaly detection, check for unusual patterns, or send
  monitoring alerts.
---

# Anomaly Detection

Detect anomalies in weekly time series data using dual methods (Z-score rolling window + IQR). Sends Slack alerts when anomalies are confirmed by both methods.

## Context

- **Squad**: Identity Fraud
- **Data source**: Databricks tables (Spark SQL) or local Parquet/CSV files
- **Alert channel**: Slack via webhook
- **Granularity**: Weekly (configurable)

## Workflow

1. **User provides**: table name (or file path) + metric column + date column
2. **Agent generates**: a Python script that reads the data, detects anomalies, plots results, and sends Slack alerts
3. **User reviews**: charts and anomaly summary
4. **Slack**: receives alert if anomalies are found in the latest period

## What the User Provides

| Information | Example | Required? |
|---|---|---|
| Data source | `identity_fraud.weekly_changes` or `s3://bucket/data.parquet` | Yes |
| Metric column | `total_events` | Yes |
| Date column | `cohort_week` | Yes |
| Group-by columns | `country, change_type` | No |
| Indicator name | `Change Personal Info` | No (defaults to "Indicator") |
| Rolling window | `12` | No (default: 12 weeks) |
| Z-score threshold | `2.0` | No (default: 2.0) |
| IQR multiplier | `1.5` | No (default: 1.5) |

## Execution Modes

### Mode A — Run on Databricks (remote)

When the data lives in a Databricks table, submit a one-time run via REST API:

```python
import urllib.request, json, base64

host = "<from ~/.databrickscfg>"
token = "<from ~/.databrickscfg>"

# 1. Find active cluster
clusters = api_get("/api/2.0/clusters/list")
cluster_id = next(c["cluster_id"] for c in clusters["clusters"] if c["state"] == "RUNNING")

# 2. Submit notebook run
run = api_post("/api/2.1/jobs/runs/submit", {
    "run_name": f"Anomaly Detection — {indicator}",
    "existing_cluster_id": cluster_id,
    "notebook_task": {
        "notebook_path": "/Workspace/Users/marina.borges2@nubank.com.br/anomaly_detection_generic",
        "base_parameters": { ... }
    }
})

# 3. Poll until done
```

Read `~/.databrickscfg` to get `host` and `token`. Never hardcode credentials.

### Mode B — Run locally (pandas)

When the user provides a local file or a small dataset, run everything locally. See [reference.md](reference.md) for the complete code.

## Detection Methods

### 1. Z-score with Rolling Window

Compares each value against the mean and std of the last N weeks.

```
z_score = (value - rolling_mean) / rolling_std
anomaly if |z_score| > threshold
```

- Adapts to recent trends (not fooled by old data)
- Default window: 12 weeks, threshold: ±2σ

### 2. IQR (Interquartile Range)

Uses rolling Q1 and Q3 to set dynamic bounds.

```
IQR = Q3 - Q1
lower = Q1 - multiplier × IQR
upper = Q3 + multiplier × IQR
anomaly if value < lower OR value > upper
```

- Robust to outliers (quartiles don't shift much)
- Default multiplier: 1.5x

### Combined Decision

- **Confirmed anomaly**: both methods agree → send Slack alert
- **Weak signal**: only one method flags it → log but don't alert

## Slack Alert Format

Send a structured Slack message with blocks:

```
🚨 {Indicator} — Anomaly Alert ({week})
─────────────────────────────────
{Country / Group}
• Value: 1,200 (📈 above expected)
• Z-score: 3.41 (threshold: ±2.0)
• Rolling mean: 520 ± 85
• IQR bounds: [380, 710]
• Detection: Z-score + IQR
─────────────────────────────────
Anomaly Detection | Window: 12w | Z: 2.0σ | IQR: 1.5x
```

Default webhook: read from environment variable `SLACK_WEBHOOK_URL`. If not set, ask the user.

## Visualization

Generate a 2-panel chart per group:

1. **Top panel (Z-score)**: observed values + rolling mean + ±Nσ band + anomaly markers (red dots)
2. **Bottom panel (IQR)**: observed values + IQR band + anomaly markers (orange dots) + confirmed markers (red X)

Use Nubank colors:
- Observed line: `#820AD1` (purple)
- Z-score band: `#00A86B` (green)
- IQR band: `#1E90FF` (blue)
- Confirmed anomaly: red `X` marker

## Key Rules

- Always read credentials from `~/.databrickscfg`, never hardcode
- Minimum 6 data points required for detection
- Use `min_periods = max(4, window // 2)` to avoid early NaN inflation
- Replace rolling_std = 0 with NaN to avoid division by zero
- Sort data by date before applying rolling functions
- When group columns exist, apply detection independently per group
- Only alert on the **most recent period** — don't flood Slack with historical anomalies
- Show a summary table at the end with all anomalies sorted by date descending

## Prerequisites

```bash
pip install pandas numpy matplotlib --index-url https://pypi.org/simple/
```

For Databricks mode, also need: `urllib.request` (stdlib, no install needed).

## Example Prompts

> "Roda anomaly detection pra Change Personal Info na tabela identity_fraud.weekly_changes, agrupado por country"

> "Detect anomalies in total_events from the file weekly_data.parquet, date column is cohort_week"

> "Run anomaly detection for Login Frequency with a 8-week window and z-score threshold of 2.5"

## Detailed Reference

For complete Python code (detection functions, plotting, Slack alerting, Databricks API helpers), see [reference.md](reference.md).