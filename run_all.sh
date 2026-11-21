#!/usr/bin/env bash
# One-command local run on macOS / Linux:  bash run_all.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -r requirements.txt
fi

export DBT_PROFILES_DIR="$(pwd)"
mkdir -p warehouse

.venv/bin/dbt build
.venv/bin/python scripts/export_outputs.py
.venv/bin/dbt docs generate

echo "Done. KPIs are in outputs/. Run '.venv/bin/dbt docs serve' for the docs site."
