{#
    The same number must come out of every route through the model:
    total failures in the fact = sum over product types = plant summary.
    Returns a row (= test fails) if any of the three disagree.
#}

with fact as (
    select
        count(*)                                           as readings,
        sum(case when is_machine_failure then 1 else 0 end) as failures
    from {{ ref('fct_sensor_readings') }}
),

by_type as (
    select sum(readings) as readings, sum(failures) as failures
    from {{ ref('kpi_failure_rate_by_product_type') }}
),

by_wear as (
    select sum(readings) as readings, sum(failures) as failures
    from {{ ref('kpi_failure_rate_by_tool_wear') }}
),

plant as (
    select total_readings as readings, total_failures as failures
    from {{ ref('kpi_plant_summary') }}
)

select *
from fact, by_type, by_wear, plant
where fact.readings != by_type.readings
   or fact.readings != by_wear.readings
   or fact.readings != plant.readings
   or fact.failures != by_type.failures
   or fact.failures != by_wear.failures
   or fact.failures != plant.failures
