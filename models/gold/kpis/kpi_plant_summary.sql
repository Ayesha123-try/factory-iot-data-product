{#
    KPI: plant-level summary. Grain: exactly one row.
    The "front page" numbers, each computed with the same standard macros as the
    breakdown KPIs so the totals always reconcile (enforced by a singular test).
#}

with readings as (

    select * from {{ ref('fct_sensor_readings') }}

),

events as (

    select
        fm.failure_mode_code,
        cast(count(*) as bigint) as failure_events
    from {{ ref('fct_failure_events') }} as e
    inner join {{ ref('dim_failure_mode') }} as fm
        on e.failure_mode_key = fm.failure_mode_key
    group by fm.failure_mode_code

),

totals as (

    select
        cast(count(*) as bigint)                                    as total_readings,
        cast(count(distinct machine_key) as bigint)                 as total_machines,
        {{ count_if_true('is_machine_failure') }}                   as total_failures,
        {{ count_if_true("failure_class = 'multi_mode_failure'") }}   as multi_mode_failures,
        {{ count_if_true("failure_class = 'failure_without_mode'") }} as failures_without_mode,
        {{ count_if_true("failure_class = 'mode_without_failure'") }} as modes_without_failure,
        cast(round(avg(tool_wear_min), 1) as double)                as avg_tool_wear_min
    from readings

)

select
    t.total_readings,
    t.total_machines,
    t.total_failures,
    {{ failure_rate_pct('t.total_failures', 't.total_readings') }}           as failure_rate_pct,
    t.multi_mode_failures,
    t.failures_without_mode,
    t.modes_without_failure,
    t.avg_tool_wear_min,
    (select failure_mode_code from events order by failure_events desc limit 1)  as top_failure_mode,
    (select product_type_code from {{ ref('kpi_failure_rate_by_product_type') }}
        order by failure_rate_pct desc limit 1)                               as highest_risk_product_type
from totals as t
