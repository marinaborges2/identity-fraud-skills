# Anomaly Detection — Reference

Complete Python code for local execution mode and Databricks helpers.

## Imports

```python
import pandas as pd
import numpy as np
import json
import urllib.request
import configparser
from pathlib import Path
```

## Config Loader

```python
def load_databricks_config(profile="DEFAULT"):
    cfg = configparser.ConfigParser()
    cfg.read(Path.home() / ".databrickscfg")
    return cfg[profile]["host"], cfg[profile]["token"]
```

## Databricks API Helpers

```python
def databricks_api(method, endpoint, host, token, body=None):
    url = f"{host}{endpoint}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(
        url, data=data,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method=method,
    )
    resp = urllib.request.urlopen(req, timeout=60)
    return json.loads(resp.read().decode())


def find_active_cluster(host, token):
    result = databricks_api("GET", "/api/2.0/clusters/list", host, token)
    for c in result.get("clusters", []):
        if c.get("state") == "RUNNING":
            return c["cluster_id"], c["cluster_name"]
    return None, None


def submit_notebook_run(host, token, cluster_id, notebook_path, params, run_name="Anomaly Detection"):
    body = {
        "run_name": run_name,
        "existing_cluster_id": cluster_id,
        "notebook_task": {
            "notebook_path": notebook_path,
            "base_parameters": params,
        },
    }
    result = databricks_api("POST", "/api/2.1/jobs/runs/submit", host, token, body)
    return result["run_id"]


def wait_for_run(host, token, run_id):
    import time
    while True:
        result = databricks_api("GET", f"/api/2.1/jobs/runs/get?run_id={run_id}", host, token)
        state = result["state"]["life_cycle_state"]
        if state in ("TERMINATED", "SKIPPED", "INTERNAL_ERROR"):
            return result
        time.sleep(15)


def get_run_output(host, token, run_id):
    output = databricks_api("GET", f"/api/2.1/jobs/runs/get-output?run_id={run_id}", host, token)
    raw = output.get("notebook_output", {}).get("result", "{}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw_output": raw}
```

## Detection Functions

```python
def zscore_rolling(series, window=12, threshold=2.0):
    rolling_mean = series.rolling(window=window, min_periods=max(4, window // 2)).mean()
    rolling_std = series.rolling(window=window, min_periods=max(4, window // 2)).std().replace(0, np.nan)
    z_score = (series - rolling_mean) / rolling_std
    return pd.DataFrame({
        "rolling_mean": rolling_mean,
        "rolling_std": rolling_std,
        "z_score": z_score,
        "zscore_anomaly": z_score.abs() > threshold,
    })


def iqr_rolling(series, window=12, multiplier=1.5):
    q1 = series.rolling(window=window, min_periods=max(4, window // 2)).quantile(0.25)
    q3 = series.rolling(window=window, min_periods=max(4, window // 2)).quantile(0.75)
    iqr = q3 - q1
    lower = q1 - multiplier * iqr
    upper = q3 + multiplier * iqr
    return pd.DataFrame({
        "iqr_q1": q1,
        "iqr_q3": q3,
        "iqr_lower": lower,
        "iqr_upper": upper,
        "iqr_anomaly": (series < lower) | (series > upper),
    })


def detect_anomalies(df, metric_col, date_col, window=12, zscore_thresh=2.0, iqr_mult=1.5):
    df = df.sort_values(date_col).reset_index(drop=True)

    if len(df) < 6:
        return df.assign(
            rolling_mean=np.nan, rolling_std=np.nan, z_score=np.nan,
            zscore_anomaly=False, iqr_q1=np.nan, iqr_q3=np.nan,
            iqr_lower=np.nan, iqr_upper=np.nan, iqr_anomaly=False,
            confirmed_anomaly=False, any_anomaly=False,
        )

    zs = zscore_rolling(df[metric_col], window, zscore_thresh)
    iq = iqr_rolling(df[metric_col], window, iqr_mult)

    result = df.copy()
    for col in zs.columns:
        result[col] = zs[col].values
    for col in iq.columns:
        result[col] = iq[col].values

    result["confirmed_anomaly"] = result["zscore_anomaly"] & result["iqr_anomaly"]
    result["any_anomaly"] = result["zscore_anomaly"] | result["iqr_anomaly"]
    return result
```

## Run Detection with Groups

```python
def run_detection(df, metric_col, date_col, group_cols=None, window=12, zscore_thresh=2.0, iqr_mult=1.5):
    results = []

    if group_cols:
        for keys, group in df.groupby(group_cols):
            result = detect_anomalies(group, metric_col, date_col, window, zscore_thresh, iqr_mult)
            results.append(result)
    else:
        results.append(detect_anomalies(df, metric_col, date_col, window, zscore_thresh, iqr_mult))

    return pd.concat(results, ignore_index=True)
```

## Visualization

```python
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

def plot_anomalies(df, date_col, metric_col, title, window, zscore_thresh, iqr_mult):
    fig, axes = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
    fig.suptitle(title, fontsize=14, fontweight="bold")

    # Z-score panel
    ax = axes[0]
    ax.plot(df[date_col], df[metric_col], "o-", color="#820AD1", markersize=4, label="Observed")
    ax.plot(df[date_col], df["rolling_mean"], "--", color="#00A86B", label=f"Rolling Mean ({window}w)")
    ax.fill_between(
        df[date_col],
        df["rolling_mean"] - zscore_thresh * df["rolling_std"],
        df["rolling_mean"] + zscore_thresh * df["rolling_std"],
        alpha=0.15, color="#00A86B", label=f"±{zscore_thresh}σ band",
    )
    zs_anom = df[df["zscore_anomaly"] == True]
    ax.scatter(zs_anom[date_col], zs_anom[metric_col], color="red", s=80, zorder=5, label="Z-score anomaly")
    ax.set_ylabel(metric_col)
    ax.set_title("Z-score (Rolling Window)")
    ax.legend(loc="upper left", fontsize=8)
    ax.grid(True, alpha=0.3)

    # IQR panel
    ax = axes[1]
    ax.plot(df[date_col], df[metric_col], "o-", color="#820AD1", markersize=4, label="Observed")
    ax.fill_between(df[date_col], df["iqr_lower"], df["iqr_upper"],
                     alpha=0.15, color="#1E90FF", label=f"IQR ±{iqr_mult}x band")
    iq_anom = df[df["iqr_anomaly"] == True]
    ax.scatter(iq_anom[date_col], iq_anom[metric_col], color="orange", s=80, zorder=5, label="IQR anomaly")
    conf = df[df["confirmed_anomaly"] == True]
    ax.scatter(conf[date_col], conf[metric_col], color="red", s=120, zorder=6, marker="X", label="Confirmed (both)")
    ax.set_ylabel(metric_col)
    ax.set_xlabel("Week")
    ax.set_title("IQR (Rolling Window)")
    ax.legend(loc="upper left", fontsize=8)
    ax.grid(True, alpha=0.3)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y-%m-%d"))

    plt.tight_layout()
    plt.show()


def plot_all_groups(results_df, date_col, metric_col, group_cols, indicator, window, zscore_thresh, iqr_mult):
    if group_cols:
        for keys, group in results_df.groupby(group_cols):
            label = " / ".join(str(k) for k in (keys if isinstance(keys, tuple) else (keys,)))
            plot_anomalies(group.sort_values(date_col), date_col, metric_col,
                           f"{indicator} — {label}", window, zscore_thresh, iqr_mult)
    else:
        plot_anomalies(results_df.sort_values(date_col), date_col, metric_col,
                       indicator, window, zscore_thresh, iqr_mult)
```

## Slack Alerting

```python
def send_slack_alert(anomalies_df, indicator, date_col, metric_col, group_cols,
                     webhook_url, window, zscore_thresh, iqr_mult):
    if anomalies_df.empty:
        print("No anomalies to report.")
        return

    latest = anomalies_df[date_col].max()
    recent = anomalies_df[anomalies_df[date_col] == latest]

    if recent.empty:
        print(f"No anomalies in the latest period ({latest}).")
        return

    blocks = [
        {"type": "header", "text": {"type": "plain_text",
            "text": f"🚨 {indicator} — Anomaly Alert ({latest.strftime('%Y-%m-%d')})"}},
        {"type": "divider"},
    ]

    for _, row in recent.iterrows():
        direction = "📈 above" if row["z_score"] > 0 else "📉 below"
        group_label = " / ".join(str(row[c]) for c in group_cols) if group_cols else "Overall"
        methods = []
        if row.get("zscore_anomaly"):
            methods.append("Z-score")
        if row.get("iqr_anomaly"):
            methods.append("IQR")

        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": (
            f"*{group_label}*\n"
            f"• Value: *{row[metric_col]:,.0f}* ({direction} expected)\n"
            f"• Z-score: *{row['z_score']:.2f}* (threshold: ±{zscore_thresh})\n"
            f"• Rolling mean: {row['rolling_mean']:,.0f} ± {row['rolling_std']:,.0f}\n"
            f"• IQR bounds: [{row['iqr_lower']:,.0f}, {row['iqr_upper']:,.0f}]\n"
            f"• Detection: {' + '.join(methods)}"
        )}})

    blocks.append({"type": "divider"})
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn",
        "text": f"_Window: {window}w | Z: {zscore_thresh}σ | IQR: {iqr_mult}x_"}]})

    payload = json.dumps({"blocks": blocks}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url, data=payload,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    resp = urllib.request.urlopen(req)
    print(f"Slack alert sent — status {resp.status}")
```

## Full Local Pipeline Example

```python
# Load
df = pd.read_parquet("weekly_data.parquet")
df["cohort_week"] = pd.to_datetime(df["cohort_week"])

# Detect
results = run_detection(
    df, metric_col="total_events", date_col="cohort_week",
    group_cols=["country"], window=12, zscore_thresh=2.0, iqr_mult=1.5,
)

# Plot
plot_all_groups(results, "cohort_week", "total_events", ["country"],
                "Change Personal Info", 12, 2.0, 1.5)

# Alert
confirmed = results[results["confirmed_anomaly"] == True]
send_slack_alert(confirmed, "Change Personal Info", "cohort_week", "total_events",
                 ["country"], webhook_url, 12, 2.0, 1.5)

# Summary
print(results[results["any_anomaly"] == True][
    ["cohort_week", "country", "total_events", "rolling_mean", "z_score",
     "iqr_lower", "iqr_upper", "confirmed_anomaly"]
].sort_values("cohort_week", ascending=False))
```

## Full Databricks Pipeline Example

```python
host, token = load_databricks_config()
cluster_id, cluster_name = find_active_cluster(host, token)

params = {
    "input_table": "identity_fraud.weekly_change_personal_info",
    "metric_column": "total_events",
    "date_column": "cohort_week",
    "group_columns": "country,change_type",
    "indicator_name": "Change Personal Info",
    "rolling_window": "12",
    "zscore_threshold": "2.0",
    "iqr_multiplier": "1.5",
    "slack_webhook": webhook_url,
}

run_id = submit_notebook_run(host, token, cluster_id,
    "/Workspace/Users/marina.borges2@nubank.com.br/anomaly_detection_generic",
    params, f"Anomaly Detection — {params['indicator_name']}")

result = wait_for_run(host, token, run_id)
output = get_run_output(host, token, run_id)
print(output)
```