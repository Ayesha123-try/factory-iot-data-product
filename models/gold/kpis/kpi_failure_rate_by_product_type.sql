{#
    KPI: failure rate by product type. Grain: one row per product type.
    This is the headline KPI, so it has an enforced model contract (see _gold.yml):
    column names and types cannot change without the build failing.
#}

with readings as (

    select
        pt.product_type_code,
        pt.quality_variant,
        f.*
    from {{ ref('fct_sensor_readings') }} as f
    inner join {{ ref('dim_product_type') }} as pt
        on f.product_type_key = pt.product_type_key

),

aggregated as (

    select
        product_type_code,
        quality_variant,
        cast(count(*) as bigint)                               as readings,
        {{ count_if_true('is_machine_failure') }}              as failures,
        cast(round(avg(tool_wear_min), 1) as double)           as avg_tool_wear_min,
        cast(round(avg(torque_nm), 2) as double)               as avg_torque_nm,
        cast(round(avg(rotational_speed_rpm), 0) as double)    as avg_rotational_speed_rpm,
        cast(round(avg(power_w) / 1000, 2) as double)          as avg_power_kw
    from readings
    group by product_type_code, quality_variant

)

select
    cast(product_type_code as varchar)                                   as product_type_code,
    cast(quality_variant as varchar)                                     as quality_variant,
    readings,
    failures,
    {{ failure_rate_pct('failures', 'readings') }}                      as failure_rate_pct,
    {{ share_pct('failures', 'sum(failures) over ()') }}                as share_of_failures_pct,
    {{ share_pct('readings', 'sum(readings) over ()') }}                as share_of_readings_pct,
    avg_tool_wear_min,
    avg_torque_nm,
    avg_rotational_speed_rpm,
    avg_power_kw
from aggregated
order by failure_rate_pct desc
