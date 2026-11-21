# Factory IoT Data Product: Machine Sensor KPIs

**dbt · DuckDB · SQL · Git · GitHub Actions** &nbsp;|&nbsp; Personal project on public data ([AI4I 2020 Predictive Maintenance](https://archive.ics.uci.edu/dataset/601/ai4i+2020+predictive+maintenance+dataset), UCI)

This project turns **10,000 raw machine sensor readings** into a tested, documented **data product**.
The data moves through **bronze, silver and gold layers in dbt**. The gold layer is a **star schema**
with machine, product type and failure mode dimensions. On top of it sit **standardised KPIs**, such as
failure rate by product type. Every KPI is computed by the same shared formulas, checked by
**76 dbt tests**, documented in a dbt docs site, and rebuilt by a **CI pipeline in GitHub Actions** on every pull request.

> How the project was designed and why: see **[docs/METHODOLOGY.md](docs/METHODOLOGY.md)**.

---

## Results at a glance

These numbers come from the gold layer of the last build (`outputs/`):

| KPI | Value |
|---|---|
| Sensor readings / machines | 10,000 / 10,000 |
| Machine failures | 339 |
| **Plant failure rate** | **3.39 %** |
| Failure rate, L (low quality) | 3.92 % (235 of 6,000) |
| Failure rate, M (medium quality) | 2.77 % (83 of 2,997) |
| Failure rate, H (high quality) | 2.09 % (21 of 1,003) |
| Failure rate, tool wear 200+ min | 15.36 % (vs. 2.2 to 2.7 % below 200 min) |
| Top failure mode | HDF, heat dissipation (115 events) |
| dbt tests | 74 pass, 2 warnings (known source-data issues), 0 fail |

**What it means:**
- Low-quality (L) products fail **1.9x as often** as high-quality (H) ones. L is 60 % of readings but 69 % of failures.
- Tools past **200 minutes** of wear fail about **6x more often**. Replacing tools before 200 minutes is the clearest action.
- Overstrain failures (OSF) hit L products hardest (87 of 98 events), because L has the lowest strain limit.

---

## How to run it yourself

### Prerequisites
- **Python 3.10 or newer** (built with 3.12), with `pip`
- **Git** (only needed to clone the project or use CI)
- Nothing else. DuckDB is embedded, so there is no database server to install.

### Option A: one command

Windows (PowerShell), from the project folder:

```powershell
.\run_all.ps1
```

macOS / Linux:

```bash
bash run_all.sh
```

The script creates a virtual environment on its first run, installs the pinned packages, and then runs these three steps:
`dbt build` → export KPIs → generate docs.

> If PowerShell blocks the script ("running scripts is disabled"), run it once with
> `powershell -ExecutionPolicy Bypass -File .\run_all.ps1`.

### Option B: step by step (to see what each step does)

```powershell
# 1. Create and activate a virtual environment, then install the packages
python -m venv .venv
.\.venv\Scripts\Activate.ps1          # macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt

# 2. Tell dbt to use the profiles.yml in this folder
$env:DBT_PROFILES_DIR = "."           # macOS/Linux: export DBT_PROFILES_DIR=.

# 3. Check the connection
dbt debug

# 4. Load the seeds, build every model and run every test, in dependency order
dbt build

# 5. Export the gold KPI tables to outputs/ (CSV + JSON).
#    Run this right after `dbt build`: it also reads the test results.
python scripts/export_outputs.py

# 6. Generate and open the documentation site (lineage graph, column docs, tests)
dbt docs generate
dbt docs serve                        # opens http://localhost:8080
```

### Useful dbt commands

| Command | What it does |
|---|---|
| `dbt build --select gold` | Build only the gold layer (plus its tests) |
| `dbt build --select +kpi_plant_summary` | Build one KPI and everything it depends on |
| `dbt test --select silver` | Run only the silver tests |
| `dbt build --full-refresh` | Rebuild from scratch (use this after changing a seed's columns) |
| `dbt ls --resource-type test` | List all tests |
| `dbt clean` | Delete `target/` and `logs/` |

### Query the warehouse directly

The whole warehouse is one file, `warehouse/factory_iot.duckdb`. You can query it from Python:

```python
import duckdb
con = duckdb.connect("warehouse/factory_iot.duckdb", read_only=True)
con.sql("select * from gold.kpi_failure_rate_by_product_type").show()
```

You can also open it in any DuckDB client, such as DBeaver or the DuckDB CLI.

---

## How it works

### Project structure

```
IOT data project/
├── dbt_project.yml          # dbt config: layers -> schemas, materialisations, seed column types
├── profiles.yml             # DuckDB connection (dev + ci targets); kept in repo so it runs anywhere
├── requirements.txt         # pinned dbt-core, dbt-duckdb, duckdb
├── run_all.ps1 / run_all.sh # one-command end-to-end run
│
├── seeds/                   # RAW landing zone (loaded by `dbt seed`)
│   ├── ai4i2020.csv         #   the UCI dataset, unchanged (10,000 rows)
│   ├── ref_product_types.csv#   L / M / H reference data (thresholds from the dataset paper)
│   ├── ref_failure_modes.csv#   TWF, HDF, PWF, OSF, RNF + UNK reference data
│   └── _seeds.yml
│
├── models/
│   ├── bronze/              # 1:1 copy, snake_case names, lineage columns
│   ├── silver/              # typed + cleaned + engineered features; failure events unpivoted
│   ├── gold/
│   │   ├── dims/            # dim_machine, dim_product_type, dim_failure_mode
│   │   ├── facts/           # fct_sensor_readings, fct_failure_events
│   │   └── kpis/            # 4 KPI marts
│   └── overview.md          # landing page of the dbt docs site
│
├── macros/
│   ├── kpi_macros.sql       # THE standard KPI formulas (failure_rate_pct, rate_per_1000, share_pct)
│   ├── surrogate_key.sql    # MD5 surrogate keys
│   └── generate_schema_name.sql  # clean schema names: raw / bronze / silver / gold
│
├── tests/
│   ├── generic/             # reusable tests: accepted_range, unique_combination, row_count_equals
│   └── singular/            # reconciliation + data quality checks
│
├── scripts/
│   └── export_outputs.py    # gold tables -> outputs/*.csv + outputs/kpis.json
│
├── outputs/                 # exported KPI tables (CSV) + kpis.json
├── docs/METHODOLOGY.md      # approach, modelling decisions, KPI and testing strategy
├── warehouse/               # DuckDB database file is created here (git-ignored)
└── .github/workflows/dbt_ci.yml   # CI pipeline
```

### Data flow

```
 seeds (raw)                bronze                   silver                          gold
┌──────────────────┐   ┌────────────────────┐   ┌──────────────────────┐   ┌───────────────────────────┐
│ ai4i2020         │──▶│ brz_sensor_readings│──▶│ slv_sensor_readings  │──▶│ dim_machine               │
│ ref_product_types│   │  rename + lineage  │   │  types, features,    │   │ dim_product_type          │
│ ref_failure_modes│   └────────────────────┘   │  failure_class,      │   │ dim_failure_mode          │
└──────────────────┘                            │  rule checks         │   │ fct_sensor_readings       │
                                                ├──────────────────────┤   │ fct_failure_events        │
                                                │ slv_failure_events   │──▶│ kpi_* (4 KPI marts)       │
                                                │  wide flags -> long  │   └─────────────┬─────────────┘
                                                └──────────────────────┘                 ▼
                                                                    outputs/*.csv · kpis.json · dbt docs
```

| Layer | Schema | Models | Rule |
|---|---|---|---|
| Raw | `raw` | 3 seeds | Data exactly as received |
| Bronze | `bronze` | `brz_sensor_readings` | No business logic. Rename columns, add `_source_file` and `_ingested_at` |
| Silver | `silver` | `slv_sensor_readings`, `slv_failure_events` | Clean once, here: types, booleans, derived features, classification |
| Gold | `gold` | 3 dims, 2 facts, 4 KPIs | Business-ready star schema and KPIs. Consumers read only from here |

### Star schema (gold)

```
                    dim_machine                       dim_failure_mode
                (1 row per product_id)              (TWF HDF PWF OSF RNF UNK)
                         │                                   │
                         │ machine_key                       │ failure_mode_key
                         ▼                                   ▼
 dim_product_type ──▶ fct_sensor_readings ◀── reading_id ── fct_failure_events
  (L / M / H)          1 row per reading                     1 row per failed reading x mode
   product_type_key    sensors + outcome                     (also carries machine_key, product_type_key)
```

- **`fct_sensor_readings`** has one row per reading: sensor measures, derived features and the failure outcome.
- **`fct_failure_events`** has one row per failed reading and failure mode. It is a bridge, because one failure can have several modes (24 readings have 2 or more).
- Keys are **MD5 surrogate keys** of the natural keys, so every table can be rebuilt on its own and still join.

### KPIs (gold/kpis)

All KPIs use the macros in `macros/kpi_macros.sql`, so each formula is written in exactly one place:

| Model | Grain | Main KPI |
|---|---|---|
| `kpi_failure_rate_by_product_type` | product type | `failure_rate_pct = 100 × failures / readings`, share of failures, average sensors. **Enforced contract.** |
| `kpi_failure_mode_by_product_type` | product type × failure mode | `events_per_1000_readings`, share of type's events (zero combinations included) |
| `kpi_failure_rate_by_tool_wear` | 50-minute tool wear band | failure rate per band |
| `kpi_plant_summary` | one row | totals, plant failure rate, top failure mode, highest-risk product type |

### Tests (76 in total)

| Kind | Examples |
|---|---|
| Built-in generic | `unique` / `not_null` on every key, `accepted_values` on codes, `relationships` from every fact key to its dimension |
| Custom generic (`tests/generic/`) | `accepted_range` (sensor plausibility, rates between 0 and 100), `unique_combination` (grain of event and KPI tables), `row_count_equals` |
| Singular (`tests/singular/`) | `assert_kpis_reconcile_to_fact`: fact total = sum by type = sum by wear band = plant summary. `assert_every_failure_has_an_event`. `assert_failure_shares_sum_to_100` |
| Data quality (**warn**) | `dq_failure_label_consistency`, `dq_failure_rules_match_labels`. These flag known issues in the source data on every build without stopping it |
| Contract | `kpi_failure_rate_by_product_type` column names and types are enforced at build time |

The two warnings are **expected**. They are real issues in the public dataset, and the project reports them instead of hiding them:
- 9 readings have `machine_failure = 1` but no failure mode. They are kept as mode `UNK`.
- 18 readings have the random-failure (RNF) flag but `machine_failure = 0`. They are classified as `mode_without_failure`.
- 12 HDF labels sit exactly on the 8.6 K temperature boundary of the documented rule. This comes from rounding in the published temperatures. The PWF and OSF rules reproduce their labels with 0 mismatches.

### CI pipeline (GitHub Actions)

`.github/workflows/dbt_ci.yml` runs on **every pull request**, on pushes to `main`, and on manual runs:

```
checkout → setup Python 3.12 → pip install → dbt debug → dbt parse → dbt build → export KPIs → dbt docs generate → upload artifacts
```

- It uses the `ci` target, which is a fresh DuckDB file, so every run builds from zero.
- A failing test fails the check, so a pull request that breaks a KPI shows a red ❌ before it is merged.
- Run results, the manifest, the docs site and `outputs/` are uploaded as a downloadable artifact (`dbt-ci-results`).

### Outputs

After a run, `outputs/` contains:

| File | Contents |
|---|---|
| `kpi_plant_summary.csv` | One-row plant summary |
| `kpi_failure_rate_by_product_type.csv` | Headline KPI by L / M / H |
| `kpi_failure_mode_by_product_type.csv` | 18 rows: 3 types × 6 modes |
| `kpi_failure_rate_by_tool_wear.csv` | 5 tool wear bands |
| `kpis.json` | All of the above plus row counts per layer, test results and data quality findings |

---

## Putting it on GitHub (so CI runs)

The folder is already a Git repository on branch `main`. To publish it:

```powershell
git add .
git commit -m "Factory IoT data product: dbt + DuckDB medallion pipeline"
git remote add origin https://github.com/<your-username>/factory-iot-dbt.git
git push -u origin main
```

Then open any pull request. The **dbt CI** check runs automatically, and you can follow it in the repo's **Actions** tab.

## Data source and licence

AI4I 2020 Predictive Maintenance Dataset, S. Matzka, UCI Machine Learning Repository (2020),
licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The data is synthetic and modelled on real milling-machine behaviour.
