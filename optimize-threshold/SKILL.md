---
name: optimize-threshold
description: >-
  Optimize anti-fraud policy thresholds using Wind Tunnel 4Policies. Use when
  asked to define thresholds, optimize a policy, create a Wind Tunnel flow,
  simulate thresholds, or work on fraud defense policies.
---

# Threshold Optimization with Wind Tunnel

Guide for creating and optimizing anti-fraud policy thresholds using Wind Tunnel 4Policies in the Identity Fraud squad.

## Context

- **Squad repo**: `fraud-identity-defenses` (cloned at `~/dev/nu/fraud-identity-defenses`)
- **Wind Tunnel CLI**: `uv run -- wind-tunnel <command>`
- **Two modes**: Optimization (finds best threshold) and Simulation (tests predefined thresholds)

## Workflow

1. **Prepare dataset** (Databricks) -> save as `.parquet` on S3
2. **Write policy** (Python file in squad repo)
3. **Validate** -> `uv run -- wind-tunnel validate <flow_path>`
4. **Run** -> `uv run -- wind-tunnel run <flow_path>` (local) or `run-kubeflow` (remote)
5. **Analyze results** -> load artifacts from S3

## Policy File Structure

Create under `src/fraud_identity_defenses/policies/<policy_name>.py`:

```python
from polars import DataFrame, col, when, lit
from wind_tunnel.flows.policy_optimization import FlowPolicyOptimization

WIND_TUNNEL_CONFIG = {
    "experiment_name": "<descriptive name>",
    "input_dataset": {
        "dataset_path": "s3://nu-temp-training-datasets-br/teams/fraud/<user>/<dataset>.parquet",
        "target_column": "target",
    },
    "policies": {
        "<policy_name>": {
            "optimization_metric": "recall",
            "constraints": {
                "precision": {"type": "higher", "value": 0.1},
            },
            "thresholds": {
                "<threshold_name>": {
                    "feature": "<column_name>",
                    "type": "numerical",
                }
            },
        }
    },
}

def my_policy(df: DataFrame, thresholds: dict) -> DataFrame:
    return df.with_columns(
        score=when(col("<feature>") > thresholds["<threshold_name>"])
            .then(lit(1.0))
            .otherwise(lit(0.0))
    ).with_columns(
        reason=when(col("score") == lit(1.0))
            .then(lit("reason-high-risk"))
            .otherwise(lit("reason-low-risk"))
    )

class MyPolicyFlow(FlowPolicyOptimization):
    def __init__(self, **kwargs):
        super().__init__(
            policy_set=[my_policy],
            config=WIND_TUNNEL_CONFIG,
            **kwargs,
        )
```

## Key Rules

### Policy Function
- Input: **Polars** DataFrame (not Pandas)
- Must return DataFrame with two new columns: `score` (float 0.0 or 1.0) and `reason` (string)
- Receives `thresholds` dict with current threshold values

### Config - Optimization Mode
- `optimization_metric`: metric to maximize (e.g., `recall`, `precision`, `f1`)
- `constraints`: minimum/maximum bounds for other metrics
- `thresholds`: define which features to optimize and their type (`numerical`)
- Finds a **local** maximum - not guaranteed global optimum

### Config - Simulation Mode
Use `FlowPolicySimulation` instead, and define explicit threshold combinations:

```python
from wind_tunnel.flows.policy_simulation import FlowPolicySimulation

POLICY_CONFIG = {
    "experiment_name": "Policy simulation",
    "input_dataset": {
        "dataset_path": "s3://...",
    },
    "policies": {
        "my_policy": {
            "thresholds": [
                {"prediction_threshold": 0.1, "amount_thresh": 450.00},
                {"prediction_threshold": 0.3, "amount_thresh": 600.00},
                {"prediction_threshold": 0.5, "amount_thresh": 800.00},
            ]
        },
    },
}
```

### Cost Function (optional)
Add financial context to evaluation:

```python
def cost_function(df: DataFrame) -> DataFrame:
    return df.with_columns(
        cost_true_positive=-1.0 * col("amount"),
        cost_false_positive=lit(50.0),
        fraud_losses=col("amount"),
    )

class MyPolicyFlow(FlowPolicyOptimization):
    def __init__(self, **kwargs):
        super().__init__(
            policy_set=[my_policy],
            config=WIND_TUNNEL_CONFIG,
            cost_function=cost_function,
            **kwargs,
        )
```

### Input Dataset Requirements
- Format: `.parquet`
- Must contain binary target column (0/1, no nulls)
- Save to: `s3://nu-temp-training-datasets-br/teams/fraud/<user>/<name>.parquet`

## Commands Quick Reference

| Command | Description |
|---|---|
| `nu-data aws credentials refresh` | Refresh AWS credentials |
| `uv sync` | Install/update dependencies |
| `uv run -- wind-tunnel hi` | Verify Wind Tunnel works |
| `uv run -- wind-tunnel validate <flow>` | Validate config and policy |
| `uv run -- wind-tunnel run <flow>` | Run locally (small datasets) |
| `uv run -- wind-tunnel run-kubeflow <flow>` | Run remotely (large datasets) |

## Results

Artifacts saved to: `s3://nu-ds-br-artifacts/models/fraud-identity-defenses/<branch>/<run-id>/`

**Optimization**: `results_optimization/filtered_<policy>.parquet` (best results, sorted by metric)
**Simulation**: `results_simulation/<policy>.parquet` (all scenarios with metrics)

## Additional Resources

- [Wind Tunnel docs](https://nubank.atlassian.net/wiki/spaces/DISFB/pages/264192068131/Wind+Tunnel)
- [Config parameters](https://nubank.atlassian.net/wiki/spaces/DISFB/pages/264331887299)
- [Custom metrics](https://nubank.atlassian.net/wiki/spaces/DISFB/pages/264353516206)
- [Shared constraints](https://nubank.atlassian.net/wiki/spaces/DISFB/pages/264397494878)
- [Deploy to Defense Platform](https://nubank.atlassian.net/wiki/spaces/DISFB/pages/264347430314)
