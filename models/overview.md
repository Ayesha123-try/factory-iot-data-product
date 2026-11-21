{% docs __overview__ %}
# Factory IoT Data Product: Machine Sensor KPIs

This dbt project turns the public **AI4I 2020 Predictive Maintenance** dataset (10,000 machine
sensor readings) into a tested, documented data product with standardised reliability KPIs.

## Layers (medallion architecture)

| Layer  | Schema  | What happens |
|--------|---------|--------------|
| Raw    | `raw`   | dbt seeds: the UCI CSV as published plus two reference tables |
| Bronze | `bronze`| 1:1 copy, snake_case column names, lineage metadata |
| Silver | `silver`| Typed, cleaned, physics features, failure classification, unpivoted failure events |
| Gold   | `gold`  | Star schema (`dim_machine`, `dim_product_type`, `dim_failure_mode`, `fct_sensor_readings`, `fct_failure_events`) and KPI marts |

## Standard KPI definitions

All KPIs use shared macros in `macros/kpi_macros.sql`:

* **Failure rate %** = 100 x failed readings / total readings
* **Events per 1,000 readings** = 1000 x failure events / readings
* **Share %** = 100 x part / whole

Use the lineage graph (bottom-right button) to see how each KPI is built.
{% enddocs %}
