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
MIN_DATA_POINTS = 10
MAX_DEVIATION_DISPLAY = 500
ALERT_LOOKBACK_DAYS = 15

TIME_WINDOWS = [5, 10]  # variable-specific, may not apply to all indicators

COUNTRY_FLAGS = {"BR": "🇧🇷", "CO": "🇨🇴", "MX": "🇲🇽"}

SEASONALITY = [
    {"name": "Black Friday / Christmas", "start_month": 11, "start_day": 15,
     "end_month": 12, "end_day": 31, "countries": ["BR", "CO", "MX"]},
    {"name": "New Year", "start_month": 1, "start_day": 1,
     "end_month": 1, "end_day": 31, "countries": ["BR", "CO", "MX"]},
    {"name": "Carnival", "start_month": 2, "start_day": 20,
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

See actual notebooks for country-specific patterns.

### Cell 12 — Detection Functions

Same across all notebooks — see SKILL.md for thresholds.

### Cell 13 — Run Detection Loop

Includes `skipped_countries` tracking and `MIN_DATA_POINTS` check.

### Cell 14 — Parquet Export

Exports full customer list for each confirmed anomaly.

### Cell 15 — Visualization

Two-panel charts (Z-score + IQR) per country.

### Cell 16 — Slack Alert

With `ALERT_LOOKBACK_DAYS` filter, clean customer links, cross-country overview with all countries.

### Cell 17 — Summary Table

Displays all confirmed anomalies.

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

If the variable is not tied to account release date (e.g., Flutter Flow), remove the time window loop and use `time_window = "all"` as a fixed label.

## Adapting for Variables With Different Event Types

If the variable doesn't have sub-types (like email/phone/address), simplify `get_sample_customers` to just order by a relevant metric (e.g., `released_at` desc for recency).