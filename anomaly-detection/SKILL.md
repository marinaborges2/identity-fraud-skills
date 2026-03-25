---
name: anomaly-detection
description: >-
  Create Databricks notebooks for weekly anomaly detection on fraud indicators.
  Use when asked to detect anomalies, monitor indicators, create anomaly
  detection for a new variable, or build fraud monitoring notebooks. This skill
  orchestrates data-extraction, statistical-detection, and slack-alerting.
---

# Anomaly Detection — Modular Skill

This skill has been split into specialized mini-skills for better reusability. For the full end-to-end pipeline, read and follow:

**`~/.cursor/skills/fraud-monitoring/SKILL.md`**

It composes these three independent skills:

| Skill | Path | Use standalone for |
|---|---|---|
| **data-extraction** | `~/.cursor/skills/data-extraction/SKILL.md` | Reading source notebooks, replicating Scala logic in PySpark, country-specific data extraction |
| **statistical-detection** | `~/.cursor/skills/statistical-detection/SKILL.md` | Z-score + IQR anomaly detection on any time series data |
| **slack-alerting** | `~/.cursor/skills/slack-alerting/SKILL.md` | Narrative Slack alerts, customer samples, Parquet exports |

## Quick Reference

The full original skill (before splitting) is preserved at:
`~/.cursor/skills/anomaly-detection-full/SKILL.md` and `reference.md`