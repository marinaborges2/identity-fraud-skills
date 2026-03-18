---
name: monitoring-segmentation
description: >-
  Segment numerical variables into homogeneous clusters for fraud monitoring.
  Use when asked to segment, cluster, create monitoring groups, define
  monitoring thresholds, split indicators into buckets, or prepare variables
  for anomaly detection dashboards.
---

# Monitoring Segmentation

Segment numerical features from a dataset into homogeneous clusters for efficient monitoring and anomaly detection in the Identity Fraud squad.

## Context

- **Squad**: Identity Fraud
- **Data source**: Parquet files on S3
- **Monitoring tool**: QuickSight dashboards
- **Goal**: Split continuous variables into meaningful groups so each segment can be monitored independently for anomalies

## Workflow

1. **User provides**: S3 path to `.parquet` dataset + which columns to segment
2. **Agent generates**: A Python script that loads the data, finds optimal segments, and outputs results
3. **User reviews**: Cluster assignments, cutoff points, and visualizations
4. **User applies**: Uses the segment definitions in QuickSight dashboards

## What the Script Must Do

### 1. Load Data

```python
import polars as pl

df = pl.read_parquet("s3://nu-temp-training-datasets-br/teams/fraud/<user>/<dataset>.parquet")
```

AWS credentials must be refreshed first: `nu-data aws credentials refresh`

### 2. Find Optimal Number of Clusters

When the user does NOT specify a number of clusters, use the **Elbow Method + Silhouette Score** to suggest the best k:

```python
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import silhouette_score
import numpy as np

scaler = StandardScaler()
X_scaled = scaler.fit_transform(df.select(features).to_numpy())

silhouette_scores = {}
inertias = {}
K_range = range(2, 11)

for k in K_range:
    km = KMeans(n_clusters=k, random_state=42, n_init=10)
    labels = km.fit_predict(X_scaled)
    inertias[k] = km.inertia_
    silhouette_scores[k] = silhouette_score(X_scaled, labels)

best_k = max(silhouette_scores, key=silhouette_scores.get)
```

When the user DOES specify a fixed number, skip this step and use their value directly.

### 3. Fit Final Clustering

```python
km_final = KMeans(n_clusters=best_k, random_state=42, n_init=10)
labels = km_final.fit_predict(X_scaled)
df = df.with_columns(pl.Series("segment", labels))
```

### 4. Generate Outputs

The script must produce **all three outputs**:

#### A. Cutoff Table

A summary table showing the range and statistics of each segment, per feature:

```python
segment_summary = (
    df.group_by("segment")
    .agg([
        pl.count().alias("count"),
        *[pl.col(f).min().alias(f"{f}_min") for f in features],
        *[pl.col(f).max().alias(f"{f}_max") for f in features],
        *[pl.col(f).mean().alias(f"{f}_mean") for f in features],
        *[pl.col(f).median().alias(f"{f}_median") for f in features],
        *[pl.col(f).std().alias(f"{f}_std") for f in features],
    ])
    .sort("segment")
)
```

Print this table clearly with segment labels (e.g., "Low", "Medium", "High" sorted by the primary feature's mean).

#### B. Enriched Dataset

Save the original dataset with the new `segment` column:

```python
output_path = "<feature>_segmented.parquet"
df.write_parquet(output_path)
```

#### C. Visualizations

Generate distribution plots per feature, colored by segment:

```python
import matplotlib.pyplot as plt

for feature in features:
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    # Histogram by segment
    for seg in sorted(df["segment"].unique().to_list()):
        subset = df.filter(pl.col("segment") == seg)
        axes[0].hist(subset[feature].to_numpy(), bins=50, alpha=0.6,
                     label=f"Segment {seg}")
    axes[0].set_title(f"{feature} \u2014 Distribution by Segment")
    axes[0].set_xlabel(feature)
    axes[0].legend()

    # Box plot by segment
    data_by_seg = [
        df.filter(pl.col("segment") == seg)[feature].to_numpy()
        for seg in sorted(df["segment"].unique().to_list())
    ]
    axes[1].boxplot(data_by_seg, labels=[f"Seg {s}" for s in sorted(df["segment"].unique().to_list())])
    axes[1].set_title(f"{feature} \u2014 Box Plot by Segment")

    plt.tight_layout()
    plt.savefig(f"{feature}_segments.png", dpi=150)
    plt.show()
```

Also generate the Elbow + Silhouette plot when k was auto-selected:

```python
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5))

ax1.plot(list(inertias.keys()), list(inertias.values()), "bo-")
ax1.axvline(x=best_k, color="purple", linestyle="--", label=f"Selected k={best_k}")
ax1.set_title("Elbow Method")
ax1.set_xlabel("Number of clusters (k)")
ax1.set_ylabel("Inertia")
ax1.legend()

ax2.plot(list(silhouette_scores.keys()), list(silhouette_scores.values()), "ro-")
ax2.axvline(x=best_k, color="purple", linestyle="--", label=f"Selected k={best_k}")
ax2.set_title("Silhouette Score")
ax2.set_xlabel("Number of clusters (k)")
ax2.set_ylabel("Score")
ax2.legend()

plt.tight_layout()
plt.savefig("cluster_selection.png", dpi=150)
plt.show()
```

## Key Rules

### Clustering
- Always use **StandardScaler** before KMeans \u2014 features may have very different scales
- Default k range: 2 to 10
- Use `random_state=42` for reproducibility
- When auto-selecting k, prefer **silhouette score** as primary criterion
- After clustering, **sort segments by the primary feature's mean** and relabel (0 = lowest, N = highest)
- Give segments human-readable labels: "Very Low", "Low", "Medium", "High", "Very High" (adapt count to k)

### Single Feature vs Multiple Features
- **Single feature**: Cluster on that feature alone. Output is a clean segmentation of that variable
- **Multiple features**: Cluster on all features together. Segments represent multivariate behavioral profiles

### Output
- Always print the cutoff summary table to the console
- Always save the enriched `.parquet` with the `segment` column
- Always generate and save the visualization PNGs
- When k was auto-selected, always show the Elbow + Silhouette plot and explain why that k was chosen

### QuickSight Integration
After segmentation, the user will use the `segment` column in QuickSight. Remind them:
- Upload the enriched `.parquet` to S3
- In QuickSight, use `segment` as a dimension to filter/group charts
- Set up anomaly detection per segment for more precise alerting

## What the User Provides

| Information | Example | Required? |
|---|---|---|
| S3 dataset path | `s3://nu-temp-training-datasets-br/.../data.parquet` | Yes |
| Features to segment | `login_frequency`, `amount`, `time_between_txns` | Yes |
| Number of clusters | `4`, `5` | No (auto-detected if not specified) |
| Segment labels | "Low Risk", "Medium", "High Risk" | No (auto-generated) |

## Prerequisites

```bash
pip install polars scikit-learn matplotlib pyarrow --index-url https://pypi.org/simple/
```

## Example Prompt

> "Segment the dataset at s3://nu-temp-training-datasets-br/teams/fraud/marina/identity_monitoring.parquet
> by login_frequency. Suggest how many clusters make sense."

> "Segment by login_frequency and transaction_amount into 4 groups."
