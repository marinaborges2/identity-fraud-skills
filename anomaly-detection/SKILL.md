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

## Step 1 — Read the Source Notebook (and its dependencies)

The source notebook contains the original logic for constructing the variable. **This logic MUST be replicated exactly** — tables, filters, joins, column names — for each country independently.

Critical rules:
- **Never assume** that BR, CO, and MX use the same tables or filters for the same variable
- **Never generalize** across countries — check each one individually in the source code
- Cross-reference the source notebook cell-by-cell
- If the source is Scala, translate to PySpark preserving exact semantics

### Reading dependency notebooks (`%run` imports)

Source notebooks often import helper functions via `%run` that **hide critical logic** — especially `.transform()` calls. These transforms may add columns like `initial_limit`, `released_at`, or `product` that do NOT come from the main notebook's tables.

**Always do this**:
1. Read the source notebook and search for `%run` lines (e.g., `%run "squads/loss-mitigation/KYC/imports/kyc_utils"`)
2. Export each dependency notebook via the API
3. Search for any function name referenced in `.transform(functionName)` calls
4. Read the function body to understand which tables it queries, what columns it adds, and what filters it applies

Known dependency notebooks:
| Notebook | Path | Key functions |
|---|---|---|
| `kyc_utils` | `/Workspace/squads/loss-mitigation/KYC/imports/kyc_utils` | `getCustomerDataBRFull`, `getCustomerDataCOFull`, `getCustomerDataMXFull`, and 40+ others |
| `scala_imports` | `/Workspace/squads/loss-mitigation/KYC/imports/scala_imports` | `getPii`, `removePiiHash`, `datasets` |

**`initial_limit` source per country** (from `kyc_utils`):
| Country | Function | Table | Column |
|---|---|---|---|
| BR | `getCustomerDataBRFull` | `br__core.account_requests_current_snapshot` | `account_request__limit_range_max / 100` |
| CO | `getCustomerDataCOFull` | `co__dataset.applications` | `credit_limit / 100` |
| MX | `getCustomerDataMXFull` | `mx__dataset.underwriting_table_v2` | `initial_limit` (already exists as column) |

A local copy of `kyc_utils` is saved at `kyc_utils_reference.scala` in the workspace for quick reference.

### Resolving `datasets()` table names

The `datasets("name")` function in Scala calls `spark.table(translateName("name"))`. The `translateName` function is an internal library that does NOT follow a simple naming convention — it uses an internal registry.

**To find the actual table name**, run this in a Databricks Scala cell:
```scala
import etl.databricks.DatabricksHelpers.translateName
println(translateName("contract-paparazzi/docs-captures"))
```

Known mappings:
| `datasets()` name | Actual table |
|---|---|
| `"contract-paparazzi/docs-captures"` | `br__contract.paparazzi__docs_captures` |
| `"dataset/acquisition-funnel"` | `br__dataset.acquisition_funnel` |

Use the Databricks MCP or REST API to read notebooks:
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
5. **Parquet Export** — full customer list for each confirmed anomaly saved to DBFS
6. **Visualization** — two-panel charts per combination
7. **Slack Alert** — enriched narrative-first alert
8. **Summary Table** — all confirmed anomalies

### Calibrated Thresholds

| Parameter | Value | Rationale |
|---|---|---|
| Z-score threshold | ±3.0σ | Initial 2.0σ was too sensitive |
| IQR multiplier | 2.0x | Initial 1.5x flagged too many |
| Min deviation | ≥30% | Filters noise from small absolute changes |
| Max deviation | ≤500% | Above this = insufficient baseline, not a real anomaly |
| Rolling window | 12 weeks | Enough history without being stale |
| Min data points | 10 weeks | Below this, skip the combination (increased from 6) |
| Alert lookback | 15 days | Only alert on anomalies from the last 15 days, ignore older ones |

### Skipped Country Tracking

When the detection loop skips a country/time_window due to insufficient data (`< MIN_DATA_POINTS` weeks), it **must**:
1. Record the skip in a `skipped_countries` dict: `skipped_countries[country] = num_weeks`
2. Print a message: `⏭️ {country} / {time_window}d: skipped — only {N} weeks of data (minimum is {MIN_DATA_POINTS})`
3. Include the country in the cross-country overview with: `_skipped — N weeks (min 10)_`

**Never silently omit a country** — it looks like a bug. Always show all expected countries in the overview.

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
- **Deviation > 500%**: treat as **insufficient baseline** — do NOT alert. These are excluded from `confirmed_anomaly` via the filter `deviation_pct <= MAX_DEVIATION_DISPLAY`. In the cross-country overview, show "_insufficient baseline_"
- **Week-over-week > 500%**: show "*well above/below* last week (X → Y customers)"
- **Expected range**: floor lower bound at 0 (no negative customer counts)
- **Confidence**: calculated as `(1 - 2 * norm.sf(|z_score|)) * 100`
- **Last anomaly**: show date + weeks ago, or "_none in the last 12 months_"
- **Cross-country overview**: **always list ALL expected countries** (BR, CO, MX), never omit a country. Show deviation per country, "_insufficient baseline_" if >500%, "_insufficient data_" if NaN, "_skipped — N weeks (min 10)_" if the country was skipped due to insufficient data points. Track skipped countries in a `skipped_countries` dict during the detection loop and use it when building the overview.

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
11. Parquet export path with customer count (if exported)

### Alert Limits
- **Only alert on anomalies from the last `ALERT_LOOKBACK_DAYS` (15 days)**. Filter `confirmed_anomaly` by `cohort_week >= now - 15 days` before sending. Historical anomalies are still detected and visible in charts/summary, but do NOT trigger alerts.
- Show only **top 5 anomalies** by |z-score|, deduplicated by country
- Customer IDs link to Shuffle: `<https://backoffice.nubank.com.br/shuffle/#/person/{id}|{id}>`
- **Customer links must be clean**: just the numbered link, nothing after it. No extra text like ratios, labels, or metadata after the ID link. Format: `  1. <URL|ID>`
- Webhook via Databricks Secrets: `dbutils.secrets.get(scope="identity-fraud", key="slack_webhook")`

### Parquet Export of Anomalous Customers

For each confirmed anomaly, export the **full list of flagged customers** to DBFS as Parquet, so the entire cohort can be investigated beyond the top-10 sample.

**Path pattern**: `/dbfs/anomaly_exports/{variable_slug}/{date}_{country}_{window}d.parquet`
- `variable_slug`: variable name, lowercase, underscores (e.g., `fast_cash_out`)
- Example: `/dbfs/anomaly_exports/fast_cash_out/2026-03-16_BR_5d.parquet`

**Columns**: `customer__id`, `released_at`, `initial_limit`, `amount`, `cash_out_ratio` (or equivalent metric), `country`, `cohort_week`

**Implementation**:
1. After the detection loop, iterate over confirmed anomalies for the latest week
2. Filter the source Spark DataFrame by country, week, and flag
3. Write as Parquet with `mode("overwrite")`
4. Store paths in an `export_paths` dict keyed by `(country, time_window)`
5. Pass `export_paths` to `send_slack_alert`
6. In the alert, add a single italic line per anomaly: `_Full list (N customers): \`path\`_`

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
| Hidden `.transform()` logic | `UNRESOLVED_COLUMN` for columns like `initial_limit` | Read `%run` dependency notebooks (e.g., `kyc_utils`) to find which table provides the column |
| `translateName` table resolution | `TABLE_OR_VIEW_NOT_FOUND` for `datasets()` calls | Run `println(translateName("dataset-name"))` in Scala to get actual table path |
| Country missing from alert | Country silently omitted from cross-country overview | Always list all expected countries; track skipped ones in `skipped_countries` dict |
| Indentation in loop | Code never executes (dead code after `continue`) | Verify indentation after `if/continue` |
| Empty results list | `ValueError: No objects to concatenate` | Guard `if not all_results:` |
| NaN in percentages | `nan%` in alert | Check `pd.notna()` and `> 0` before division |
| Negative expected range | `Expected range: -5 – 10` | `max(0, iqr_lower)` |
| Absurd percentages / false positives | `1192675%` or country with immature baseline alerting | Exclude from `confirmed_anomaly` when `deviation_pct > 500%`; show "_insufficient baseline_" in overview |
| Empty summary DataFrame | `ValueError: can not infer schema from empty dataset` | Guard `if summary.empty:` before `spark.createDataFrame(summary)` |

## Metric Focus

The primary metric is **`unique_customers`** (not total events). This reflects the number of affected customers, which is more actionable for fraud investigation.

## Visualization

Two-panel chart per country × time_window:
- **Top**: Z-score — observed (purple `#820AD1`) + rolling mean (green `#00A86B`) + ±3σ band + red anomaly dots
- **Bottom**: IQR — observed (purple) + IQR band (blue `#1E90FF`) + orange IQR anomalies + red X confirmed

## Detailed Reference

For complete notebook template code (data extraction patterns, detection functions, alert builder, upload helpers), see [reference.md](reference.md).