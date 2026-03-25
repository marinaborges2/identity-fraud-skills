---
name: data-extraction
description: >-
  Extract and replicate data logic from Databricks source notebooks into PySpark
  code. Use when asked to read a source notebook, understand data extraction per
  country, replicate Scala logic in PySpark, or extract data for BR/CO/MX.
---

# Data Extraction — Databricks Source Notebooks

Reads a Databricks source notebook (Scala or PySpark) and generates equivalent PySpark data extraction code that exactly replicates the original logic per country (BR, CO, MX).

## Workflow

1. **User provides**: source notebook path or reference
2. **Agent reads** the source notebook cell-by-cell
3. **Agent identifies** dependency notebooks (`%run` imports)
4. **Agent reads** each dependency to resolve hidden logic
5. **Agent generates** PySpark extraction code per country

## Step 1 — Read the Source Notebook

The source notebook contains the original logic for constructing the variable. **This logic MUST be replicated exactly** — tables, filters, joins, column names — for each country independently.

Critical rules:
- **Never assume** that BR, CO, and MX use the same tables or filters for the same variable
- **Never generalize** across countries — check each one individually in the source code
- Cross-reference the source notebook cell-by-cell
- If the source is Scala, translate to PySpark preserving exact semantics

Use the Databricks MCP or REST API to read notebooks:
```python
GET /api/2.0/workspace/export?path=/path/to/notebook&format=SOURCE
```

## Step 2 — Read Dependency Notebooks

Source notebooks often import helper functions via `%run` that **hide critical logic** — especially `.transform()` calls. These transforms may add columns like `initial_limit`, `released_at`, or `product` that do NOT come from the main notebook's tables.

**Always do this**:
1. Search the source notebook for `%run` lines
2. Export each dependency notebook via the API
3. Search for any function name referenced in `.transform(functionName)` calls
4. Read the function body to understand which tables it queries, what columns it adds, and what filters it applies

### Known dependency notebooks

| Notebook | Path | Key functions |
|---|---|---|
| `kyc_utils` | `/Workspace/squads/loss-mitigation/KYC/imports/kyc_utils` | `getCustomerDataBRFull`, `getCustomerDataCOFull`, `getCustomerDataMXFull`, and 40+ others |
| `scala_imports` | `/Workspace/squads/loss-mitigation/KYC/imports/scala_imports` | `getPii`, `removePiiHash`, `datasets`, `translateName` |

### `initial_limit` source per country (from `kyc_utils`)

| Country | Function | Table | Column |
|---|---|---|---|
| BR | `getCustomerDataBRFull` | `br__core.account_requests_current_snapshot` | `account_request__limit_range_max / 100` |
| CO | `getCustomerDataCOFull` | `co__dataset.applications` | `credit_limit / 100` |
| MX | `getCustomerDataMXFull` | `mx__dataset.underwriting_table_v2` | `initial_limit` (already exists as column) |

### Resolving `translateName` table names

The `datasets()` function in `scala_imports` uses `translateName()` to map internal dataset names to actual catalog table paths.

**Known mappings**:
| Dataset key | Actual table |
|---|---|
| `contract-paparazzi/docs-captures` | `br__contract.paparazzi__docs_captures` |

For unknown mappings, run this Scala snippet in a Databricks notebook:
```scala
println(translateName("dataset-key/name"))
```

## Step 3 — Generate PySpark Code

### Checkpoint Strategy (CRITICAL)

Databricks blocks self-joins on remote tables. Fix with **two-level `checkpoint()`**:

```python
spark.sparkContext.setCheckpointDir("/tmp/anomaly_detection_checkpoints")

# Level 1: checkpoint acquisition DFs before reuse in multiple joins
acq_br = (spark.table("...").filter(...).groupBy(...).agg(...)).checkpoint()

# Level 2: checkpoint country unions before cross-country union
all_changes_br = email.unionByName(phone).unionByName(address).checkpoint()
```

**Never use**: `.localCheckpoint()`, `.cache()` on remote tables, or `spark.conf.set("spark.databricks.remoteFiltering.blockSelfJoins", "false")`.

### Extraction Pattern

```python
from pyspark.sql import functions as F

start_date = (datetime.now() - timedelta(days=365)).strftime("%Y-%m-%d")

acq_{country} = (
    spark.table("{acquisition_table}")
    .filter(F.col("{confirmed_col}") >= start_date)
    .select(F.col("customer__id"), F.col("{released_col}").cast("timestamp").alias("released_at"))
    .where(F.col("released_at").isNotNull())
    .groupBy("customer__id")
    .agg(F.min("released_at").alias("released_at"))
).checkpoint()
```

### Aggregation Pattern

```python
from functools import reduce

weekly_dfs = []
for window_days in TIME_WINDOWS:
    w = (
        all_events_detailed
        .filter(F.col("days_since_release") <= window_days)
        .withColumn("time_window", F.lit(f"0-{window_days}d"))
        .groupBy("country", "cohort_week", "time_window")
        .agg(
            F.countDistinct("customer__id").alias("unique_customers"),
            F.count("*").alias("total_events"),
        )
    )
    weekly_dfs.append(w)

weekly_all = reduce(lambda a, b: a.unionByName(b), weekly_dfs)
pdf = weekly_all.toPandas()
```

## Output Contract

This skill produces a **Pandas DataFrame** (`pdf`) with these columns:

| Column | Type | Description |
|---|---|---|
| `country` | str | "BR", "CO", or "MX" |
| `cohort_week` | datetime | Monday of the week |
| `time_window` | str | e.g. "0-5d", "0-10d", or "all" (if applicable) |
| `unique_customers` | int | Count of distinct customers |
| `total_events` | int | Total event count |

This DataFrame is the input for the `statistical-detection` skill.

## Common Pitfalls

| Issue | Symptom | Fix |
|---|---|---|
| Self-join on remote tables | `Py4JJavaError: Self-joins are blocked` | Two-level `.checkpoint()` |
| localCheckpoint data loss | `CHECKPOINT_RDD_BLOCK_ID_NOT_FOUND` | Use `.checkpoint()` instead |
| Wrong table for a country | `TABLE_OR_VIEW_NOT_FOUND` | Check source notebook per country |
| Hidden `.transform()` logic | `UNRESOLVED_COLUMN` for columns like `initial_limit` | Read `%run` dependency notebooks |
| `translateName` table resolution | `TABLE_OR_VIEW_NOT_FOUND` for `datasets()` calls | Run `println(translateName("dataset-name"))` in Scala |