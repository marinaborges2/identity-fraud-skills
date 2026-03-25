---
name: statistical-detection
description: >-
  Detect anomalies in time series data using Z-score and IQR methods. Use when
  asked to detect anomalies, find outliers, identify unusual patterns in weekly
  data, or apply statistical anomaly detection to aggregated metrics.
---

# Statistical Anomaly Detection — Z-score + IQR

Applies dual-method anomaly detection (Z-score with rolling window + IQR) to weekly aggregated data. Confirms anomalies only when both methods agree and the deviation is business-relevant.

## Input Contract

Expects a **Pandas DataFrame** with at minimum:

| Column | Type | Description |
|---|---|---|
| `country` | str | Country identifier (e.g. "BR", "CO", "MX") |
| `cohort_week` | datetime | Week start date |
| `unique_customers` | int | Primary metric (or any numeric metric) |

Optional column:
| `time_window` | str | e.g. "0-5d", "0-10d" — if present, detection runs per country × time_window |

## Calibrated Thresholds

| Parameter | Value | Rationale |
|---|---|---|
| Z-score threshold | ±3.0σ | Initial 2.0σ was too sensitive — too many false positives |
| IQR multiplier | 2.0x | Initial 1.5x flagged too many — calendar variation triggered alerts |
| Min deviation | ≥30% | Filters noise from small absolute changes irrelevant to the business |
| Max deviation | ≤500% | Above this = insufficient baseline, not a real anomaly |
| Rolling window | 12 weeks | Enough history without being stale |
| Min data points | 10 weeks | Below this, skip the combination (not enough data to trust) |

## Configuration

```python
ROLLING_WINDOW_WEEKS = 12
ZSCORE_THRESHOLD = 3.0
IQR_MULTIPLIER = 2.0
MIN_DEVIATION_PCT = 30
MAX_DEVIATION_DISPLAY = 500
MIN_DATA_POINTS = 10
```

## Detection Functions

```python
import pandas as pd
import numpy as np

def zscore_rolling(series, window=ROLLING_WINDOW_WEEKS, threshold=ZSCORE_THRESHOLD):
    rolling_mean = series.rolling(window=window, min_periods=max(4, window // 2)).mean()
    rolling_std = series.rolling(window=window, min_periods=max(4, window // 2)).std().replace(0, np.nan)
    z_score = (series - rolling_mean) / rolling_std
    return pd.DataFrame({
        "rolling_mean": rolling_mean, "rolling_std": rolling_std,
        "z_score": z_score, "zscore_anomaly": z_score.abs() > threshold,
    })


def iqr_detection(series, window=ROLLING_WINDOW_WEEKS, multiplier=IQR_MULTIPLIER):
    q1 = series.rolling(window=window, min_periods=max(4, window // 2)).quantile(0.25)
    q3 = series.rolling(window=window, min_periods=max(4, window // 2)).quantile(0.75)
    iqr = q3 - q1
    lower = q1 - multiplier * iqr
    upper = q3 + multiplier * iqr
    return pd.DataFrame({
        "iqr_q1": q1, "iqr_q3": q3, "iqr_lower": lower, "iqr_upper": upper,
        "iqr_anomaly": (series < lower) | (series > upper),
    })


def detect_anomalies(df, metric_col="unique_customers"):
    zs = zscore_rolling(df[metric_col])
    iq = iqr_detection(df[metric_col])
    result = df.copy()
    for col in zs.columns:
        result[col] = zs[col].values
    for col in iq.columns:
        result[col] = iq[col].values
    result["deviation_pct"] = ((result[metric_col] - result["rolling_mean"]) / result["rolling_mean"] * 100).abs()
    result["confirmed_anomaly"] = (
        result["zscore_anomaly"] & result["iqr_anomaly"]
        & (result["deviation_pct"] >= MIN_DEVIATION_PCT)
        & (result["deviation_pct"] <= MAX_DEVIATION_DISPLAY)
    )
    result["any_anomaly"] = result["zscore_anomaly"] | result["iqr_anomaly"]
    return result
```

## Detection Loop

```python
all_results = []
skipped_countries = {}

has_time_window = "time_window" in pdf.columns
groups = pdf.groupby(["country", "time_window"] if has_time_window else ["country"])

for group_key, subset in groups:
    country = group_key[0] if has_time_window else group_key
    tw = group_key[1] if has_time_window else "all"

    subset = subset.sort_values("cohort_week").reset_index(drop=True)

    if len(subset) < MIN_DATA_POINTS:
        skipped_countries[(country, tw)] = len(subset)
        print(f"⏭️ {country} / {tw}: skipped — only {len(subset)} weeks (minimum is {MIN_DATA_POINTS})")
        continue

    result = detect_anomalies(subset, metric_col="unique_customers")
    all_results.append(result)

if not all_results:
    print("No data to analyze.")
    results_df = pd.DataFrame()
else:
    results_df = pd.concat(all_results, ignore_index=True)
    confirmed = results_df[results_df["confirmed_anomaly"] == True]
    print(f"\nConfirmed anomalies (both methods): {len(confirmed)}")
```

**CRITICAL**: The `result = detect_anomalies(...)` and `all_results.append(result)` lines MUST be at the loop indentation level, NOT inside the `if len(subset) < MIN_DATA_POINTS` block.

## Skipped Country Tracking

When the detection loop skips a country/time_window due to insufficient data, it records the skip in `skipped_countries`. This dict is passed to the alerting skill so that **all expected countries are always shown** in the alert.

## Output Contract

This skill produces a **Pandas DataFrame** (`results_df`) with all input columns plus:

| Column | Type | Description |
|---|---|---|
| `rolling_mean` | float | 12-week rolling average |
| `rolling_std` | float | 12-week rolling std dev |
| `z_score` | float | Z-score value |
| `zscore_anomaly` | bool | True if \|z\| > 3.0 |
| `iqr_q1`, `iqr_q3` | float | Quartile values |
| `iqr_lower`, `iqr_upper` | float | IQR bounds |
| `iqr_anomaly` | bool | True if outside IQR bounds |
| `deviation_pct` | float | Absolute % deviation from rolling mean |
| `confirmed_anomaly` | bool | True when both methods agree + deviation ≥ 30% and ≤ 500% |

Plus a **dict** `skipped_countries` mapping `(country, time_window)` to the number of weeks available.

These are the inputs for the `slack-alerting` skill.

## Common Pitfalls

| Issue | Symptom | Fix |
|---|---|---|
| Indentation in loop | Code never executes (dead code after `continue`) | Verify indentation after `if/continue` |
| Empty results list | `ValueError: No objects to concatenate` | Guard `if not all_results:` |
| NaN in percentages | `nan%` in division | Check `pd.notna()` and `> 0` before division |
| Absurd percentages | `1192675%` flagged as anomaly | Exclude `deviation_pct > 500%` from `confirmed_anomaly` |