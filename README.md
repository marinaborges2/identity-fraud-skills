# Identity Fraud — Cursor AI Skills

Modular Cursor AI Skills for automated anomaly detection on fraud indicators across BR, CO, and MX.

## Quick Install

```bash
git clone https://github.com/marinaborges2/identity-fraud-skills.git
cd identity-fraud-skills
bash install.sh
```

## Skills

| Skill | What it does | Use when |
|---|---|---|
| **fraud-monitoring** | Full end-to-end pipeline (composes all below) | "Create anomaly monitoring for Fast Cash Out" |
| **data-extraction** | Reads Databricks source notebooks, generates PySpark per country | "Extract data from this Scala notebook" |
| **statistical-detection** | Z-score + IQR anomaly detection on time series | "Detect anomalies in this weekly data" |
| **slack-alerting** | Narrative Slack alerts + Parquet export | "Send alert for these detection results" |

## Architecture

```
fraud-monitoring (orchestrator)
    ├── data-extraction       → Pandas DataFrame (pdf)
    ├── statistical-detection → Pandas DataFrame (results_df) + skipped_countries
    └── slack-alerting        → Slack message + Parquet files
```

Each skill defines clear **input/output contracts**, so they can be composed in new ways:

- `fraud-monitoring` = data-extraction + statistical-detection + slack-alerting
- `product-monitoring` = data-extraction + statistical-detection + slack-alerting (different source)
- `model-drift` = statistical-detection + slack-alerting (custom data)
- `daily-report` = data-extraction + slack-alerting (no detection)

## Usage

After installing, just ask Cursor:

> "Create anomaly detection monitoring for Fast Cash Out from the quicksight_anomaly_detection notebook"

The `fraud-monitoring` skill will automatically orchestrate all three mini-skills.

For standalone use:

> "Detect anomalies in this DataFrame using Z-score and IQR"

Cursor will use only the `statistical-detection` skill.

## Detection Methodology

- **Z-score** (rolling 12-week window, threshold ±3.0σ)
- **IQR** (rolling 12-week window, multiplier 2.0x)
- Anomaly confirmed only when **both methods agree** + deviation ≥ 30%
- Deviations > 500% treated as immature baseline
- Minimum 10 weeks of data required
- Alerts only for last 15 days

## Indicators Implemented

| Indicator | Description |
|---|---|
| Change Personal Info | Email, phone or address changes after onboarding |
| Fast Cash Out | High cash out ratio vs. initial limit after release |
| Login Frequency | Zero logins after account release |
| Flutter Flow | Legacy document capture flow usage |
| First Payment Default | First delinquency within 40 days of release |