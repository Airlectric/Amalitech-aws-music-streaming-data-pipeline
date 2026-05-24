#!/usr/bin/env bash
# ──────────────────────────────────────────────────
# Music Streaming Data Producer — example invocations
# ──────────────────────────────────────────────────
set -euo pipefail

BUCKET="bronze-108782069549"

echo "=== Demo: ~500 events, unpredictable batches, ~2 min ==="
python scripts/produce_streams.py "$BUCKET"

echo ""
echo "=== Full replay: ALL 34k events ==="
python scripts/produce_streams.py "$BUCKET" --all --min-delay 1 --max-delay 5

echo ""
echo "=== Burst: upload everything NOW ==="
python scripts/produce_streams.py "$BUCKET" --burst
