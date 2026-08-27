#!/bin/bash
# Install Identity Fraud Cursor AI Skills

DEST="$HOME/.cursor/skills"
mkdir -p "$DEST"

SKILLS=("data-extraction" "statistical-detection" "slack-alerting" "fraud-monitoring" "anomaly-detection" "create-pptx" "optimize-threshold" "monitoring-segmentation" "new-monitoring-geo")

for skill in "${SKILLS[@]}"; do
    if [ -d "$skill" ]; then
        mkdir -p "$DEST/$skill"
        cp -r "$skill/"* "$DEST/$skill/"
        echo "  ✓ $skill"
    fi
done

echo ""
echo "Skills installed to $DEST"
echo ""
echo "Usage: ask Cursor to 'create anomaly detection for <variable>' and it will use the fraud-monitoring skill automatically."