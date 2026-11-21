"""Export the gold layer to plain files after `dbt build`.

Writes:
  outputs/<table>.csv   one CSV per gold KPI table (easy to open in Excel)
  outputs/kpis.json     everything in one file:
                        KPI tables, row counts per layer, dbt test results,
                        and data quality findings

Usage:
  python scripts/export_outputs.py                        # uses warehouse/factory_iot.duckdb
  python scripts/export_outputs.py --db warehouse/ci.duckdb
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "outputs"

KPI_TABLES = [
    "kpi_plant_summary",
    "kpi_failure_rate_by_product_type",
    "kpi_failure_mode_by_product_type",
    "kpi_failure_rate_by_tool_wear",
]

LAYER_TABLES = [
    ("raw", "ai4i2020"),
    ("bronze", "brz_sensor_readings"),
    ("silver", "slv_sensor_readings"),
    ("silver", "slv_failure_events"),
    ("gold", "dim_machine"),
    ("gold", "dim_product_type"),
    ("gold", "dim_failure_mode"),
    ("gold", "fct_sensor_readings"),
    ("gold", "fct_failure_events"),
]


def rows(con: duckdb.DuckDBPyConnection, sql: str) -> list[dict]:
    rel = con.sql(sql)
    cols = rel.columns
    return [dict(zip(cols, r)) for r in rel.fetchall()]


def test_summary() -> dict:
    """Summarise target/run_results.json written by the last dbt build."""
    path = ROOT / "target" / "run_results.json"
    if not path.exists():
        return {}
    run = json.loads(path.read_text(encoding="utf-8"))
    if run.get("args", {}).get("which") != "build":
        # `dbt docs generate` also writes run_results.json; only a build has test results.
        print("note: target/run_results.json is not from `dbt build` - run this script right after it")
        return {}
    results = run["results"]
    tests = [r for r in results if r["unique_id"].startswith("test.")]
    models = [r for r in results if r["unique_id"].startswith("model.")]
    status = Counter(r["status"] for r in tests)
    return {
        "tests_total": len(tests),
        "tests_pass": status.get("pass", 0),
        "tests_warn": status.get("warn", 0),
        "tests_fail": status.get("fail", 0) + status.get("error", 0),
        "models_built": sum(1 for r in models if r["status"] == "success"),
        "warnings": [
            {"test": r["unique_id"].split(".")[-1], "rows": r.get("failures")}
            for r in tests
            if r["status"] == "warn"
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(ROOT / "warehouse" / "factory_iot.duckdb"))
    args = parser.parse_args()

    OUT_DIR.mkdir(exist_ok=True)
    con = duckdb.connect(args.db, read_only=True)

    payload: dict = {"generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds")}

    for table in KPI_TABLES:
        out_csv = (OUT_DIR / f"{table}.csv").as_posix()
        con.sql(f"copy (select * from gold.{table}) to '{out_csv}' (header, delimiter ',')")
        payload[table] = rows(con, f"select * from gold.{table}")
        print(f"wrote outputs/{table}.csv")

    payload["layer_row_counts"] = [
        {"schema": s, "table": t, "rows": con.sql(f"select count(*) from {s}.{t}").fetchone()[0]}
        for s, t in LAYER_TABLES
    ]

    payload["data_quality"] = {
        "failure_class_counts": rows(
            con,
            "select failure_class, count(*) as readings from silver.slv_sensor_readings "
            "group by 1 order by 2 desc",
        ),
        "rule_vs_label_mismatches": rows(
            con,
            """
            select 'HDF' as mode, count(*) filter (where hdf_rule_triggered != has_hdf) as mismatches,
                   count(*) filter (where has_hdf) as labelled from silver.slv_sensor_readings
            union all
            select 'PWF', count(*) filter (where pwf_rule_triggered != has_pwf),
                   count(*) filter (where has_pwf) from silver.slv_sensor_readings
            union all
            select 'OSF', count(*) filter (where osf_rule_triggered != has_osf),
                   count(*) filter (where has_osf) from silver.slv_sensor_readings
            """,
        ),
    }

    payload["dbt"] = test_summary()

    (OUT_DIR / "kpis.json").write_text(json.dumps(payload, indent=2, default=str), encoding="utf-8")
    print("wrote outputs/kpis.json")


if __name__ == "__main__":
    main()
