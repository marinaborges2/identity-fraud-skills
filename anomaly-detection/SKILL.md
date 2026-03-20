---
name: anomaly-detection
description: >-
  Create Databricks notebooks for weekly anomaly detection on fraud indicators.
  Use when asked to detect anomalies, monitor indicators, create anomaly
  detection for a new variable, or build fraud monitoring notebooks. Reads
  source notebook logic and replicates it exactly into a PySpark anomaly
  detection notebook with Slack alerts.
---

# Anomaly Detection — Databricks Notebooks

Creates a PySpark Databricks notebook that detects weekly anomalies on a fraud indicator using Z-score + IQR, with enriched Slack alerts and visualizations.

## Workflow

1. **User provides**: variable name + source notebook (any Databricks notebook, not necessarily the same one every time)
2. **Agent reads the source notebook** to understand how the variable is constructed per country (tables, filters, joins)
3. **Agent creates a new `.py` notebook** following the template structure in [reference.md](reference.md)
4. **Agent generates `.ipynb`** and uploads both to Databricks via REST API
5. **User runs the notebook** on Databricks; if anomalies are found, a Slack alert is sent

## Step 1 — Read the Source Notebook

The source notebook contains the original logic for constructing the variable. **This logic MUST be replicated exactly** — tables, filters, joins, column names — for each country independently.

Critical rules:
- **Never assume** that BR, CO, and MX use the same tables or filters for the same variable
- **Never generalize** across countries — check each one individually in the source code
- Cross-reference the source notebook cell-by-cell
- If the source is Scala, translate to PySpark preserving exact semantics

Use the Databricks MCP or REST API to read the source notebook:
```python
# via REST API
GET /api/2.0/workspace/export?path=/path/to/notebook&format=SOURCE
```

## Step 2 — Create the Notebook

Follow the notebook template structure from [reference.md](reference.md). The notebook has these sections:

1. **Configuration** — thresholds, time windows, seasonality calendar
2. **Data Extraction** — PySpark logic per country (from source notebook)
3. **Aggregation** — weekly grouping by country × time_window
4. **Anomaly Detection** — Z-score + IQR functions
5. **Visualization** — two-panel charts per combination
6. **Slack Alert** — enriched narrative-first alert
7. **Summary Table** — all confirmed anomalies

### Calibrated Thresholds

| Parameter | Value | Rationale |
|---|---|---|
| Z-score threshold | ±3.0σ | Initial 2.0σ was too sensitive |
| IQR multiplier | 2.0x | Initial 1.5x flagged too many |
| Min deviation | ≥30% | Filters noise from small absolute changes |
| Rolling window | 12 weeks | Enough history without being stale |
| Min data points | 6 weeks | Below this, skip the combination |

### Time Windows

Time windows are **variable-specific, not a fixed rule**. They only apply when the variable is tied to account release date (e.g., "change personal info within N days of release"). For each new variable, analyze whether time windows are relevant. When used, each window aggregates independently.

### Checkpoint Strategy (CRITICAL)

Databricks blocks self-joins on remote tables. Fix with **two-level `checkpoint()`**:

```python
spark.sparkContext.setCheckpointDir("/tmp/anomaly_detection_checkpoints")

# Level 1: checkpoint acquisition DFs before reuse in multiple joins
acq_br = (spark.table("...").filter(...).groupBy(...).agg(...)).checkpoint()

# Level 2: checkpoint country unions before cross-country union
all_changes_br = email.unionByName(phone).unionByName(address).checkpoint()
```

**Never use**: `.localCheckpoint()` (data lost on executor recycle), `.cache()` on remote tables, or `spark.conf.set("spark.databricks.remoteFiltering.blockSelfJoins", "false")`.

## Step 3 — Slack Alert Format

The alert follows a **narrative-first format** focused on actionability. Key rules:

### Display Rules
- **Deviation > 500%**: show "*well above/below* expected" instead of the number
- **Week-over-week > 500%**: show "*well above/below* last week (X → Y customers)"
- **Expected range**: floor lower bound at 0 (no negative customer counts)
- **Confidence**: calculated as `(1 - 2 * norm.sf(|z_score|)) * 100`
- **Last anomaly**: show date + weeks ago, or "_none in the last 12 months_"
- **Cross-country overview**: show deviation per country, "_baseline maturing_" if >500%, "_insufficient data_" if NaN

### Alert Content (per anomaly)
1. Country flag + variable name + time window
2. Deviation % (or "well above/below") + customer count + rolling average
3. Week-over-week comparison
4. Last anomaly date
5. Consecutive anomalous weeks (if ≥2)
6. Expected range (IQR bounds, floored at 0)
7. Confidence percentage
8. Seasonality note (if applicable)
9. Multi-changer % vs historical (if applicable)
10. Top 10 customer IDs as clickable Shuffle links

### Alert Limits
- Show only **top 5 anomalies** by |z-score|, deduplicated by country
- Customer IDs link to Shuffle: `<https://backoffice.nubank.com.br/shuffle/#/person/{id}|{id}>`
- Webhook via Databricks Secrets: `dbutils.secrets.get(scope="identity-fraud", key="slack_webhook")`

## Step 4 — Generate and Upload

```python
# 1. Generate .ipynb from .py
# Split by "# COMMAND ----------", detect markdown cells by "# MAGIC %md"

# 2. Upload via REST API
import urllib.request, json, base64
# Read host/token from ~/.databrickscfg
payload = {"path": "/Users/user@nubank.com.br/notebook_name",
           "language": "PYTHON", "overwrite": True,
           "content": base64.b64encode(content.encode()).decode()}
# POST to {host}/api/2.0/workspace/import
```

## Common Pitfalls (from experience)

| Issue | Symptom | Fix |
|---|---|---|
| Self-join on remote tables | `Py4JJavaError: Self-joins are blocked` | Two-level `.checkpoint()` |
| localCheckpoint data loss | `CHECKPOINT_RDD_BLOCK_ID_NOT_FOUND` | Use `.checkpoint()` instead |
| Wrong table for a country | `TABLE_OR_VIEW_NOT_FOUND` | Check source notebook per country |
| Indentation in loop | Code never executes (dead code after `continue`) | Verify indentation after `if/continue` |
| Empty results list | `ValueError: No objects to concatenate` | Guard `if not all_results:` |
| NaN in percentages | `nan%` in alert | Check `pd.notna()` and `> 0` before division |
| Negative expected range | `Expected range: -5 – 10` | `max(0, iqr_lower)` |
| Absurd percentages | `1192675%` in alert | Cap display at 500%, show descriptive text |

## Metric Focus

The primary metric is **`unique_customers`** (not total events). This reflects the number of affected customers, which is more actionable for fraud investigation.

## Visualization

Two-panel chart per country × time_window:
- **Top**: Z-score — observed (purple `#820AD1`) + rolling mean (green `#00A86B`) + ±3σ band + red anomaly dots
- **Bottom**: IQR — observed (purple) + IQR band (blue `#1E90FF`) + orange IQR anomalies + red X confirmed

## Detailed Reference

For complete notebook template code (data extraction patterns, detection functions, alert builder, upload helpers), see [reference.md](reference.md).
