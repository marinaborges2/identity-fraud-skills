# Anomaly Detection — Reference

Complete code patterns for building anomaly detection notebooks. Use `change_personal_info_anomaly_detection.py` as the canonical example.

## Notebook Template Structure

The `.py` file uses Databricks source format. Cells are separated by `# COMMAND ----------`. Markdown cells use `# MAGIC %md`.

### Cell 1 — Markdown: Title and Description

```python
# Databricks notebook source
# MAGIC %md
# MAGIC # {Variable Name} - Anomaly Detection
# MAGIC
# MAGIC Weekly monitoring of {description}.
# MAGIC Covers BR, CO and MX. Data extraction logic mirrors the original notebook (`{source_notebook}`).
# MAGIC
# MAGIC **Time windows**: {list of windows, if applicable}.
# MAGIC
# MAGIC **Methods**: Z-score (Rolling 12w, ±3σ) + IQR (2.0x). Alert triggered only when both methods agree AND deviation ≥ 30%.
```

### Cell 2 — Configuration

```python
SLACK_WEBHOOK_URL = dbutils.secrets.get(scope="identity-fraud", key="slack_webhook")

ROLLING_WINDOW_WEEKS = 12
ZSCORE_THRESHOLD = 3.0
IQR_MULTIPLIER = 2.0
MIN_DEVIATION_PCT = 30

TIME_WINDOWS = [5, 10]  # variable-specific, may not apply to all indicators

COUNTRY_FLAGS = {"BR": "🇧🇷", "CO": "🇨🇴", "MX": "🇲🇽"}

SEASONALITY = [
    {"name": "Black Friday / Natal", "start_month": 11, "start_day": 15,
     "end_month": 12, "end_day": 31, "countries": ["BR", "CO", "MX"]},
    {"name": "Início de ano", "start_month": 1, "start_day": 1,
     "end_month": 1, "end_day": 31, "countries": ["BR", "CO", "MX"]},
    {"name": "Carnaval", "start_month": 2, "start_day": 20,
     "end_month": 3, "end_day": 10, "countries": ["BR"]},
]


def get_seasonality_note(week_date, country):
    month = week_date.month
    day = week_date.day
    notes = []
    for s in SEASONALITY:
        if country not in s["countries"]:
            continue
        start = (s["start_month"], s["start_day"])
        end = (s["end_month"], s["end_day"])
        if start <= end:
            in_range = start <= (month, day) <= end
        else:
            in_range = (month, day) >= start or (month, day) <= end
        if in_range:
            notes.append(f"📆 _Seasonal period: {s['name']}_")
    return "\n".join(notes) if notes else ""
```

### Cell 3 — Imports + Checkpoint Dir

```python
from pyspark.sql import functions as F
from pyspark.sql.window import Window
import pandas as pd
import numpy as np
from scipy.stats import norm
from datetime import datetime, timedelta
import json
import urllib.request

spark.sparkContext.setCheckpointDir("/tmp/anomaly_detection_checkpoints")
```

### Cell 4 — Start Date

```python
start_date = (datetime.now() - timedelta(days=365)).strftime("%Y-%m-%d")
```

### Cells 5-10 — Data Extraction Per Country

**THIS IS THE VARIABLE-SPECIFIC PART.** Read the source notebook and replicate per country.

Pattern for each country:

```python
# Level 1 checkpoint: acquisition DF (reused in multiple joins)
acq_{country} = (
    spark.table("{acquisition_table}")
    .filter(F.col("{confirmed_col}") >= start_date)
    .select(F.col("customer__id"), F.col("{released_col}").cast("timestamp").alias("released_at"))
    .where(F.col("released_at").isNotNull())
    .groupBy("customer__id")
    .agg(F.min("released_at").alias("released_at"))
).checkpoint()

# Event joins (use F.broadcast on acquisition DF)
event_type_1 = (
    spark.table("{event_history_table}")
    .select(F.col("customer__id"), F.col("{event_timestamp}").cast("timestamp").alias("event_at"))
    .join(F.broadcast(acq_{country}), "customer__id", "inner")
    .filter(F.col("event_at") > F.col("released_at"))
    .withColumn("days_since_release", F.datediff(F.col("event_at"), F.col("released_at")))
    .filter(F.col("days_since_release") <= max(TIME_WINDOWS))
    .withColumn("change_type", F.lit("{type_name}"))
    .withColumn("country", F.lit("{COUNTRY}"))
    .select("customer__id", "event_at", "released_at", "days_since_release", "change_type", "country")
)

# Level 2 checkpoint: country union (before cross-country union)
all_changes_{country} = event_type_1.unionByName(event_type_2).unionByName(event_type_3).checkpoint()
```

### Cell 11 — Union All Countries + Time Window Aggregation

```python
all_changes = all_changes_br.unionByName(all_changes_co).unionByName(all_changes_mx)

all_changes_detailed = (
    all_changes
    .withColumn("cohort_week", F.date_trunc("week", F.col("released_at")).cast("date"))
)

from functools import reduce

weekly_dfs = []
for window_days in TIME_WINDOWS:
    window_label = f"0-{window_days}d"
    w = (
        all_changes_detailed
        .filter(F.col("days_since_release") <= window_days)
        .withColumn("time_window", F.lit(window_label))
        .groupBy("country", "cohort_week", "time_window")
        .agg(
            F.countDistinct("customer__id").alias("unique_customers"),
            F.count("*").alias("total_events"),
        )
    )
    weekly_dfs.append(w)

weekly_all = reduce(lambda a, b: a.unionByName(b), weekly_dfs)
pdf = weekly_all.toPandas()
pdf["cohort_week"] = pd.to_datetime(pdf["cohort_week"])
pdf = pdf.sort_values(["country", "time_window", "cohort_week"]).reset_index(drop=True)
```

**If time windows are not applicable**, skip the loop and aggregate directly by `country + cohort_week`.

### Cell 12 — Detection Functions

```python
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
        result["zscore_anomaly"] & result["iqr_anomaly"] & (result["deviation_pct"] >= MIN_DEVIATION_PCT)
    )
    result["any_anomaly"] = result["zscore_anomaly"] | result["iqr_anomaly"]
    return result
```

### Cell 13 — Run Detection Loop

```python
all_results = []

for country in pdf["country"].unique():
    for time_window in pdf["time_window"].unique():
        subset = (
            pdf[(pdf["country"] == country) & (pdf["time_window"] == time_window)]
            .sort_values("cohort_week")
            .reset_index(drop=True)
        )
        if len(subset) < 6:
            continue
        result = detect_anomalies(subset, metric_col="unique_customers")
        all_results.append(result)

if not all_results:
    print("No data to analyze — check that aggregation cell ran successfully.")
    results_df = pd.DataFrame()
else:
    results_df = pd.concat(all_results, ignore_index=True)
    confirmed = results_df[results_df["confirmed_anomaly"] == True]
    print(f"\nConfirmed anomalies (both methods): {len(confirmed)}")
```

**CRITICAL**: The lines after `continue` MUST be at the loop indentation level, not inside the `if` block. This was a real bug that caused empty results.

### Cell 14 — Visualization

```python
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

def plot_anomaly_series(df, country, label, time_window, metric="unique_customers"):
    subset = df[(df["country"] == country) & (df["time_window"] == time_window)].sort_values("cohort_week")
    if subset.empty:
        return
    flag = COUNTRY_FLAGS.get(country, country)
    fig, axes = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
    fig.suptitle(f"Anomaly Detection — {flag} {country} / {label} / {time_window}", fontsize=14, fontweight="bold")

    ax = axes[0]
    ax.plot(subset["cohort_week"], subset[metric], "o-", color="#820AD1", markersize=4, label="Observed")
    ax.plot(subset["cohort_week"], subset["rolling_mean"], "--", color="#00A86B", label=f"Rolling Mean ({ROLLING_WINDOW_WEEKS}w)")
    ax.fill_between(subset["cohort_week"],
        subset["rolling_mean"] - ZSCORE_THRESHOLD * subset["rolling_std"],
        subset["rolling_mean"] + ZSCORE_THRESHOLD * subset["rolling_std"],
        alpha=0.15, color="#00A86B", label=f"±{ZSCORE_THRESHOLD}σ band")
    zs_anom = subset[subset["zscore_anomaly"] == True]
    ax.scatter(zs_anom["cohort_week"], zs_anom[metric], color="red", s=80, zorder=5, label="Z-score anomaly")
    ax.set_ylabel(metric)
    ax.set_title("Z-score (Rolling Window)")
    ax.legend(loc="upper left", fontsize=8)
    ax.grid(True, alpha=0.3)

    ax = axes[1]
    ax.plot(subset["cohort_week"], subset[metric], "o-", color="#820AD1", markersize=4, label="Observed")
    ax.fill_between(subset["cohort_week"], subset["iqr_lower"], subset["iqr_upper"],
        alpha=0.15, color="#1E90FF", label=f"IQR ±{IQR_MULTIPLIER}x band")
    iq_anom = subset[subset["iqr_anomaly"] == True]
    ax.scatter(iq_anom["cohort_week"], iq_anom[metric], color="orange", s=80, zorder=5, label="IQR anomaly")
    conf = subset[subset["confirmed_anomaly"] == True]
    ax.scatter(conf["cohort_week"], conf[metric], color="red", s=120, zorder=6, marker="X", label="Confirmed (both)")
    ax.set_ylabel(metric)
    ax.set_xlabel("Week")
    ax.set_title("IQR (Rolling Window)")
    ax.legend(loc="upper left", fontsize=8)
    ax.grid(True, alpha=0.3)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d"))
    plt.tight_layout()
    plt.show()

# Call with guard
if not results_df.empty:
    for country in results_df["country"].unique():
        for time_window in sorted(results_df["time_window"].unique()):
            plot_anomaly_series(results_df, country, "{variable_name}", time_window)
else:
    print("No results to plot.")
```

### Cell 15 — Slack Alert Builder

```python
SHUFFLE_URL = "https://backoffice.nubank.com.br/shuffle/#/person"


def get_sample_customers(detailed_df, country, week, max_days, n=10):
    base_filters = (
        (F.col("country") == country) &
        (F.col("cohort_week") == week) &
        (F.col("days_since_release") <= max_days)
    )
    sample = (
        detailed_df.filter(base_filters)
        .groupBy("customer__id")
        .agg(
            F.countDistinct("change_type").alias("num_change_types"),
            F.collect_set("change_type").alias("change_types_list"),
            F.min("days_since_release").alias("min_days_since_release"),
        )
        .withColumn("change_types_str", F.concat_ws(" + ", F.col("change_types_list")))
        .orderBy(F.desc("num_change_types"), F.asc("min_days_since_release"))
        .select("customer__id", "min_days_since_release", "num_change_types", "change_types_str")
        .limit(n)
        .toPandas()
    )
    return sample


def get_multi_changer_pct(detailed_df, country, week, max_days):
    base_filters = (
        (F.col("country") == country) &
        (F.col("days_since_release") <= max_days)
    )
    stats = (
        detailed_df.filter(base_filters)
        .groupBy("cohort_week", "customer__id")
        .agg(F.countDistinct("change_type").alias("n_types"))
    )
    weekly_pcts = (
        stats.groupBy("cohort_week")
        .agg(
            F.count("*").alias("total"),
            F.sum(F.when(F.col("n_types") >= 2, 1).otherwise(0)).alias("multi"),
        )
        .withColumn("pct", F.round(F.col("multi") / F.col("total") * 100, 1))
        .toPandas()
    )
    weekly_pcts["cohort_week"] = pd.to_datetime(weekly_pcts["cohort_week"])
    current = weekly_pcts[weekly_pcts["cohort_week"] == week]
    current_pct = float(current["pct"].iloc[0]) if not current.empty else 0.0
    hist = weekly_pcts[weekly_pcts["cohort_week"] < week]
    avg_pct = float(hist["pct"].mean()) if not hist.empty else 0.0
    return current_pct, avg_pct


def send_slack_alert(anomalies_df, full_results_df, detailed_df=None):
    if anomalies_df.empty:
        print("No anomalies to report.")
        return

    latest_week = anomalies_df["cohort_week"].max()
    recent_all = anomalies_df[anomalies_df["cohort_week"] == latest_week]
    if recent_all.empty:
        print(f"No anomalies in the latest week ({latest_week}).")
        return

    MAX_ALERTS = 5
    MAX_DEVIATION_DISPLAY = 500
    max_tw_days = max(TIME_WINDOWS)

    deduped = (
        recent_all
        .sort_values("z_score", key=abs, ascending=False)
        .drop_duplicates(subset=["country"], keep="first")
    )
    top = deduped.sort_values("z_score", key=abs, ascending=False).head(MAX_ALERTS)
    countries_in_data = sorted(full_results_df["country"].unique())

    blocks = [
        {"type": "header", "text": {"type": "plain_text",
            "text": f"🚨 {VARIABLE_NAME} — Anomaly Alert ({latest_week.strftime('%Y-%m-%d')})"}},
        {"type": "section", "text": {"type": "mrkdwn", "text": (
            f"*{len(top)}* anomalies detected across *{len(deduped['country'].unique())}* "
            f"{'country' if len(deduped['country'].unique()) == 1 else 'countries'} "
            f"(Z ≥ {ZSCORE_THRESHOLD}σ, IQR {IQR_MULTIPLIER}x, deviation ≥ {MIN_DEVIATION_PCT}%).")}},
        {"type": "divider"},
    ]

    # Cross-country overview
    cross_country_lines = []
    for c in countries_in_data:
        latest_data = full_results_df[
            (full_results_df["country"] == c) & (full_results_df["cohort_week"] == latest_week)]
        if latest_data.empty:
            continue
        best = latest_data.sort_values("z_score", key=abs, ascending=False).iloc[0]
        flag = COUNTRY_FLAGS.get(c, c)
        if pd.notna(best["rolling_mean"]) and best["rolling_mean"] > 0:
            dev = ((best["unique_customers"] - best["rolling_mean"]) / best["rolling_mean"] * 100)
            if abs(dev) <= MAX_DEVIATION_DISPLAY:
                arrow = "⬇️" if dev < 0 else "⬆️"
                cross_country_lines.append(f"{flag} {c}: {arrow}{abs(dev):.0f}%")
            else:
                cross_country_lines.append(f"{flag} {c}: _baseline maturing_")
        else:
            cross_country_lines.append(f"{flag} {c}: _insufficient data_")

    if cross_country_lines:
        blocks.append({"type": "section", "text": {"type": "mrkdwn",
            "text": f"*Cross-country overview:*  {' | '.join(cross_country_lines)}"}})
        blocks.append({"type": "divider"})

    # Per-anomaly details
    for _, row in top.iterrows():
        flag = COUNTRY_FLAGS.get(row["country"], row["country"])
        dev_pct = ((row["unique_customers"] - row["rolling_mean"]) / row["rolling_mean"] * 100)
        direction_arrow = "⬇️" if dev_pct < 0 else "⬆️"

        # Week-over-week
        prev_week = latest_week - pd.Timedelta(weeks=1)
        prev_data = full_results_df[
            (full_results_df["country"] == row["country"]) &
            (full_results_df["time_window"] == row["time_window"]) &
            (full_results_df["cohort_week"] == prev_week)]
        if not prev_data.empty:
            prev_customers = prev_data.iloc[0]["unique_customers"]
            if prev_customers > 0:
                wow_pct = ((row["unique_customers"] - prev_customers) / prev_customers * 100)
                wow_arrow = "⬇️" if wow_pct < 0 else "⬆️"
                if abs(wow_pct) > MAX_DEVIATION_DISPLAY:
                    wow_text = f"{wow_arrow} *well {'below' if wow_pct < 0 else 'above'}* last week ({int(prev_customers):,} → {int(row['unique_customers']):,} customers)"
                else:
                    wow_text = f"{wow_arrow}{abs(wow_pct):.0f}% vs last week ({int(prev_customers):,} customers)"
            else:
                wow_text = f"⬆️ *new activity* — last week had 0 customers"
        else:
            wow_text = "_no data last week_"

        # Consecutive anomalous weeks
        consecutive = 0
        check_week = latest_week
        while True:
            match = anomalies_df[
                (anomalies_df["country"] == row["country"]) &
                (anomalies_df["time_window"] == row["time_window"]) &
                (anomalies_df["cohort_week"] == check_week)]
            if match.empty:
                break
            consecutive += 1
            check_week -= pd.Timedelta(weeks=1)
        consec_text = f"\n🔴 *{consecutive} consecutive anomalous weeks*" if consecutive >= 2 else ""

        # Last anomaly history
        history = anomalies_df[
            (anomalies_df["country"] == row["country"]) &
            (anomalies_df["time_window"] == row["time_window"]) &
            (anomalies_df["cohort_week"] < latest_week)
        ].sort_values("cohort_week", ascending=False)
        if not history.empty:
            prev_anom = history.iloc[0]
            weeks_ago = int((latest_week - prev_anom["cohort_week"]).days / 7)
            history_text = f"📅 Last anomaly: *{prev_anom['cohort_week'].strftime('%Y-%m-%d')}* ({weeks_ago}w ago)"
        else:
            history_text = "📅 Last anomaly: _none in the last 12 months_"

        # Deviation display
        if abs(dev_pct) > MAX_DEVIATION_DISPLAY:
            dev_display = f"*well {'below' if dev_pct < 0 else 'above'}* expected"
        else:
            dev_display = f"*{abs(dev_pct):.0f}% {'below' if dev_pct < 0 else 'above'}* expected"

        text = (
            f"*{flag} {row['country']} — {VARIABLE_NAME}* ({row['time_window']})\n"
            f"{direction_arrow} {dev_display} "
            f"— *{int(row['unique_customers']):,}* customers (avg ~{row['rolling_mean']:,.0f})\n"
            f"📊 {wow_text}\n"
            f"{history_text}{consec_text}\n"
            f"📏 Expected range: *{max(0, row['iqr_lower']):,.0f}* – *{row['iqr_upper']:,.0f}* customers\n"
            f"🔴 Confidence: *{(1 - 2 * norm.sf(abs(row['z_score']))) * 100:.1f}%* that this is an anomaly"
        )

        season_note = get_seasonality_note(latest_week, row["country"])
        if season_note:
            text += f"\n{season_note}"

        # Customer sample + multi-changer % (if detailed_df available)
        if detailed_df is not None:
            sample = get_sample_customers(detailed_df, row["country"], latest_week.strftime("%Y-%m-%d"), max_tw_days, n=10)
            if not sample.empty:
                try:
                    curr_pct, avg_pct = get_multi_changer_pct(detailed_df, row["country"], latest_week, max_tw_days)
                    text += (f"\n🔥 *{curr_pct:.1f}%* of customers changed 2+ info types at once "
                             f"(e.g. email + phone) — historically this is *{avg_pct:.1f}%*")
                except Exception:
                    pass
                ids_formatted = "\n".join(
                    f"  {i+1}. <{SHUFFLE_URL}/{r['customer__id']}|{r['customer__id']}>"
                    for i, (_, r) in enumerate(sample.iterrows()))
                text += f"\n\n*Top {len(sample)} customers:*\n{ids_formatted}"

        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": text}})

    blocks.append({"type": "divider"})
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn",
        "text": f"_Rolling: {ROLLING_WINDOW_WEEKS}w | Min deviation: {MIN_DEVIATION_PCT}% | "
                f"Customers ranked by number of info types changed_"}]})

    payload = json.dumps({"blocks": blocks}).encode("utf-8")
    req = urllib.request.Request(SLACK_WEBHOOK_URL, data=payload,
        headers={"Content-Type": "application/json"}, method="POST")
    resp = urllib.request.urlopen(req)
    print(f"Slack alert sent — status {resp.status}")
```

### Cell 16 — Send Alert

```python
if not results_df.empty:
    confirmed_recent = results_df[results_df["confirmed_anomaly"] == True]
    send_slack_alert(confirmed_recent, full_results_df=results_df, detailed_df=all_changes_detailed)
else:
    print("No results — skipping alert.")
```

### Cell 17 — Summary Table

```python
if results_df.empty:
    print("No results — skipping summary.")
else:
    summary = (
        results_df[results_df["confirmed_anomaly"] == True]
        [["country", "time_window", "cohort_week", "total_events", "unique_customers",
          "rolling_mean", "z_score", "iqr_lower", "iqr_upper"]]
        .sort_values(["cohort_week", "country", "time_window"], ascending=[False, True, True])
    )
    summary["deviation_pct"] = ((summary["unique_customers"] - summary["rolling_mean"]) / summary["rolling_mean"] * 100).round(1)
    display(spark.createDataFrame(summary))
```

## Databricks API Helpers

### Read Credentials

```python
import configparser
from pathlib import Path

def load_databricks_config(profile="DEFAULT"):
    cfg = configparser.ConfigParser()
    cfg.read(Path.home() / ".databrickscfg")
    return cfg[profile]["host"], cfg[profile]["token"]
```

### Upload Notebook

```python
import urllib.request, json, base64

def upload_notebook(host, token, local_path, remote_path):
    with open(local_path, "r") as f:
        content = f.read()
    payload = json.dumps({
        "path": remote_path,
        "language": "PYTHON",
        "overwrite": True,
        "content": base64.b64encode(content.encode()).decode()
    }).encode()
    req = urllib.request.Request(
        f"{host}/api/2.0/workspace/import",
        data=payload,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST"
    )
    resp = urllib.request.urlopen(req)
    return resp.status
```

### Generate .ipynb from .py

```python
import json, re

def py_to_ipynb(py_path, ipynb_path):
    with open(py_path, "r") as f:
        content = f.read()
    cells = re.split(r'\n# COMMAND ----------\n', content)
    nb = {
        "nbformat": 4, "nbformat_minor": 0,
        "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
                      "language_info": {"name": "python", "version": "3.9.0"}},
        "cells": []
    }
    for cell in cells:
        cell = cell.strip()
        if not cell:
            continue
        if cell.startswith("# Databricks notebook source"):
            cell = cell.replace("# Databricks notebook source", "").strip()
            if not cell:
                continue
        if cell.startswith("# MAGIC %md"):
            lines = cell.split("\n")
            md_lines = []
            for line in lines:
                if line.startswith("# MAGIC "):
                    md_lines.append(line[8:])
                elif line.strip() == "# MAGIC":
                    md_lines.append("")
            nb["cells"].append({"cell_type": "markdown", "metadata": {},
                "source": [l + "\n" for l in md_lines[:-1]] + [md_lines[-1]] if md_lines else []})
        else:
            nb["cells"].append({"cell_type": "code", "metadata": {},
                "source": [l + "\n" for l in cell.split("\n")[:-1]] + [cell.split("\n")[-1]],
                "outputs": [], "execution_count": None})
    with open(ipynb_path, "w") as f:
        json.dump(nb, f, indent=1, ensure_ascii=False)
    return len(nb["cells"])
```

## Adapting for Variables Without Time Windows

If the variable is not tied to account release date, remove the time window loop:

```python
# Instead of looping over TIME_WINDOWS, aggregate directly
weekly = (
    all_events_detailed
    .groupBy("country", "cohort_week")
    .agg(
        F.countDistinct("customer__id").alias("unique_customers"),
        F.count("*").alias("total_events"),
    )
)
pdf = weekly.toPandas()

# Detection loop without time_window
for country in pdf["country"].unique():
    subset = pdf[pdf["country"] == country].sort_values("cohort_week").reset_index(drop=True)
    if len(subset) < 6:
        continue
    result = detect_anomalies(subset, metric_col="unique_customers")
    all_results.append(result)
```

Also adjust the alert builder to not reference `time_window` in the display.

## Adapting for Variables With Different Event Types

If the variable doesn't have sub-types (like email/phone/address), the `get_sample_customers` and `get_multi_changer_pct` functions should be simplified or removed. The customer sample would just be ordered by event count or another relevant metric.
