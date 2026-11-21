# Methodology: approach, logic and design decisions

This document explains **why** the project is built the way it is. For how to run it, see the [README](../README.md).

---

## 1. The goal

Factory sensor data usually arrives as wide, raw exports. Each analyst then writes their own SQL to answer
"how often do machines fail?", and the answers disagree. The goal was to build a **data product**, not just a set of queries:

1. **One trusted definition** of each KPI that every consumer shares.
2. **Clear layers**, so it is always obvious where data was cleaned and where business logic lives.
3. **Automatic checks**, so a broken number is caught by a test and not by a stakeholder.
4. **Documentation and CI**, so another engineer can understand, change and safely ship the project.

## 2. Which "model"? (no machine learning)

This is a **data engineering / analytics engineering** project. There is **no machine learning model**:
it does not predict failures, it measures them accurately and consistently. Three modelling ideas are used:

| Idea | Where | Why |
|---|---|---|
| **Medallion architecture** (bronze → silver → gold) | folder and schema layout | Separates *landing*, *cleaning* and *business logic*, so each step has one job |
| **Kimball dimensional modelling** (star schema) | `models/gold/dims`, `models/gold/facts` | The standard design for analytics: facts hold measurable events, dimensions hold descriptive context. It makes slicing KPIs by any dimension a simple join |
| **Semantic consistency through macros and contracts** | `macros/kpi_macros.sql`, enforced contract | Each KPI formula is written once and the output shape is locked |

A natural next step would be a failure-prediction model trained on `fct_sensor_readings`. The star schema is a clean feature table for it.

## 3. Tool choices

| Tool | Why |
|---|---|
| **dbt** | SQL models under version control, automatic dependency order (`ref()`), built-in testing, generated docs and lineage. It is the industry standard for the transformation layer |
| **DuckDB** | An in-process analytical (columnar) database. The whole warehouse is a single file, it needs no server or credentials, and it runs the same way on a laptop and in CI. 10,000 rows build in about 10 seconds |
| **dbt seeds** | The dataset is small and static, so loading it as a seed keeps the project self-contained and reproducible. In production this would be an external source such as an S3 path, a Kafka sink or an OPC UA historian |
| **GitHub Actions** | Free CI next to the code. Every pull request is built and tested from scratch |
| **Plain Python** for outputs | The export has no extra dependencies: plain CSV and JSON files that open anywhere |

## 4. Layer by layer: logic and decisions

### Raw (seeds)
- `ai4i2020.csv` is stored **exactly as downloaded**. Column types are declared in `dbt_project.yml`, so loading does not depend on type guessing.
- Two **reference tables** hold the business rules from the dataset paper:
  - `ref_product_types`: the overstrain threshold per quality variant (L 11,000 / M 12,000 / H 13,000 min·Nm) and the tool wear added per process.
  - `ref_failure_modes`: a name, category and trigger rule for each mode, plus **UNK** (explained below).
  Keeping these as data instead of hard-coding them in SQL means a rule change is a one-line CSV edit, reviewed in a pull request.

### Bronze: `brz_sensor_readings`
- **Rule: no business logic.** Columns are renamed to snake_case (`"Air temperature [K]"` → `air_temperature_k`), and two lineage columns are added: `_source_file` and `_ingested_at`.
- Why: if a gold number ever looks wrong, bronze is an untouched copy to compare against. Nothing is filtered, so nothing is lost.

### Silver: `slv_sensor_readings`, `slv_failure_events`
All cleaning happens **once**, here:
- **Types and codes:** explicit casts, trimmed and upper-cased codes, and booleans instead of 0/1 integers.
- **Physics-based features** that drive the failure rules:
  - `temp_diff_k = process_temp − air_temp` (heat dissipation)
  - `power_w = torque × rpm × 2π / 60` (mechanical power)
  - `overstrain_min_nm = tool_wear × torque`
  - `tool_wear_band`, in 50-minute buckets for risk reporting
- **`failure_class`** puts every reading into exactly one of five classes:
  `no_failure`, `single_mode_failure`, `multi_mode_failure`, `failure_without_mode`, `mode_without_failure`.
  Inconsistent labels in the source are **made visible and kept**, not silently dropped.
- **Rule checks:** `hdf_rule_triggered`, `pwf_rule_triggered` and `osf_rule_triggered` recompute each documented failure rule from the raw sensors. This is how the project checks the labels against the physics.
- **Unpivot:** the source stores failure modes as five wide 0/1 columns, and one failure can have several modes. `slv_failure_events` turns them into **one row per failure and mode**. Only real failures (`machine_failure = 1`) create events. A failure with no mode flag gets the mode `UNK`, so **every failure is counted exactly once**, both in failure totals and in mode breakdowns.

### Gold: star schema
Each table has a written **grain**:

| Table | Type | Grain |
|---|---|---|
| `dim_product_type` | dimension | one row per quality variant (L/M/H) |
| `dim_failure_mode` | dimension | one row per failure mode (6, including UNK) |
| `dim_machine` | dimension | one row per `product_id` |
| `fct_sensor_readings` | fact | one row per sensor reading |
| `fct_failure_events` | fact (bridge) | one row per failed reading × failure mode |

Design decisions:
- **Surrogate keys** are MD5 hashes of the natural keys (macro `surrogate_key`). They are deterministic, so dimensions and facts can be rebuilt separately and still join. This is the same approach as `dbt_utils.generate_surrogate_key`, written as a local macro so the project has no package dependencies.
- **`reading_id` is a degenerate dimension.** It identifies a reading but has no attributes of its own, so it stays on the fact.
- **Bridge fact for the many-to-many.** 24 failures have two or more modes. Counting modes from the wide columns would double count failures. Counting failures from the event table would also double count. Keeping two facts at two grains gives the right answer for both questions.
- **The `UNK` member** follows a Kimball best practice: never drop rows that do not match a dimension. Point them at an explicit "unknown" member.
- **Zero rows are kept on purpose.** `kpi_failure_mode_by_product_type` cross joins the two dimensions, so "H products had 0 random failures" appears as a row with 0 instead of a missing row.
- **`dim_machine` is 1:1 with readings in this dataset.** Every Product ID appears once. The model still builds the dimension from the distinct IDs, so it works unchanged when a real sensor stream sends many readings per machine.

### Gold: KPIs and how they are standardised
The core problem was that "failure rate" meant different things in different reports. The fix has three parts:

1. **One formula, one place.** `macros/kpi_macros.sql` defines:
   ```sql
   failure_rate_pct(failures, readings) = round(100.0 * failures / nullif(readings, 0), 2)
   rate_per_1000(events, readings)      = round(1000.0 * events / nullif(readings, 0), 2)
   share_pct(part, whole)               = round(100.0 * part / nullif(whole, 0), 2)
   count_if_true(condition)             = cast(sum(case when condition then 1 else 0 end) as bigint)
   ```
   Every KPI model calls these macros. Changing a definition is one edit, and it reaches every KPI.
2. **An enforced model contract** on the headline KPI, `kpi_failure_rate_by_product_type`. Column names and data types are declared in YAML, and dbt fails the build if the SQL output does not match. Downstream consumers can rely on the shape.
3. **Documented definitions.** Each KPI model carries `meta.kpi_definition` (and an owner) in YAML. These show up in the dbt docs site next to the lineage graph.

Totals **reconcile by construction**, and a test proves it (see below).

## 5. Testing strategy

The tests are layered like a pyramid, from cheap structural checks up to business-logic checks:

| Level | What it catches | Examples |
|---|---|---|
| **Structure** | Broken keys, duplicate rows, nulls | `unique` + `not_null` on every key, `unique_combination` on multi-column grains |
| **Referential integrity** | Orphan facts, missing dimension rows | `relationships` from every fact foreign key to its dimension |
| **Domain** | Impossible values | `accepted_values` on codes and classes; `accepted_range` on temperatures (290 to 310 K), rpm, torque, tool wear, and rates (0 to 100 %) |
| **Business logic** | KPIs that disagree with each other | `assert_kpis_reconcile_to_fact`: fact = by type = by wear band = plant summary, for both readings and failures. `assert_every_failure_has_an_event`. `assert_failure_shares_sum_to_100` |
| **Data quality (severity: warn)** | Known source issues | `dq_failure_label_consistency`, `dq_failure_rules_match_labels` |
| **Contract** | Schema drift in the headline KPI | Enforced column names and types |

**Why warnings and not errors for data quality?** The issues are real features of the public source, and the
model already handles them (UNK, `mode_without_failure`). Making them errors would block every build forever.
Hiding them would be dishonest. As warnings, they show up in every run and in CI, and their counts are exported to `outputs/kpis.json`.

### Data quality findings
| Finding | Count | Handling |
|---|---|---|
| `machine_failure = 1` with no failure-mode flag | 9 | Kept and assigned mode `UNK` |
| RNF flag set with `machine_failure = 0` | 18 | Classified `mode_without_failure` and excluded from failure events |
| HDF labelled but the rule (`ΔT < 8.6 K and rpm < 1380`) not met | 12 | All 12 sit exactly at ΔT = 8.6 K. The published temperatures are rounded to 0.1 K, so the boundary is ambiguous. Changing `<` to `≤` gives 15 mismatches instead of 12, so the documented rule was kept |
| PWF and OSF rules vs labels | 0 | The physics rules reproduce the labels exactly, which validates the derived features |
| Documented vs actual product mix | 50/30/20 vs 60/30/10 | The dataset description says L/M/H = 50/30/20 %, but the data is 60/30/10 %. Both are kept: `documented_population_share_pct` in the dimension and `share_of_readings_pct` in the KPI |

## 6. CI/CD

`.github/workflows/dbt_ci.yml` runs on every pull request:

1. `dbt debug` checks the connection and profile.
2. `dbt parse` catches YAML and Jinja errors in seconds.
3. `dbt build` loads seeds, builds models and runs tests **in DAG order**. A failing test stops the models downstream of it, and the job fails.
4. The KPIs are exported, which proves the gold layer can be read by downstream consumers.
5. `dbt docs generate` builds the documentation site.
6. The artifacts (run results, manifest, docs, outputs) are uploaded for review.

The `ci` target writes to a fresh DuckDB file, so CI always builds from zero. It never depends on state left over from an earlier run.

## 7. Outputs

- `scripts/export_outputs.py` reads the gold schema **read-only** and writes CSVs plus `kpis.json`, which includes the test results from `target/run_results.json`.

## 8. Limitations and next steps

| Limitation | Next step |
|---|---|
| No timestamps in the dataset (UDI is an ID, not a time) | With real streaming data: an incremental fact table partitioned by time, plus time-based KPIs such as MTBF (mean time between failures) and failures per shift |
| Each machine appears once | Track machine attribute changes with a dbt **snapshot** (slowly changing dimension, type 2) |
| Static seed data | Swap the seed for an external source (S3, Kafka sink, historian) and add source freshness tests |
| KPIs are dbt models | Define them as metrics in the **dbt Semantic Layer / MetricFlow**, so BI tools query one definition |
| CI rebuilds everything | Use **Slim CI** (`state:modified+` with deferral) once the project grows, and add SQL linting (`sqlfluff`) |
| Measures failures only | Train a failure-prediction model on `fct_sensor_readings` and write its scores back as a gold table |

## 9. How this project was produced

The project was built with the help of an AI coding assistant (Anthropic's Claude, model Opus 5.5) working in this folder.
It downloaded the public dataset, wrote the dbt project, ran every build and test locally, inspected the
results (that is how the data quality findings above were found), and exported the real outputs.
All code is plain SQL, YAML and Python, and you can read, run and change it yourself.
