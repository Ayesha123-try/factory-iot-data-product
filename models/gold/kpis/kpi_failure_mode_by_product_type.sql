{#
    KPI: failure modes by product type. Grain: one row per (product type x failure mode).
    Built from a cross join of the two dimensions, so combinations with zero events still
    appear (a zero is information; a missing row is ambiguous).
#}

with grid as (

    select
        pt.product_type_key,
        pt.product_type_code,
        fm.failure_mode_key,
        fm.failure_mode_code,
        fm.failure_mode_name
    from {{ ref('dim_product_type') }} as pt
    cross join {{ ref('dim_failure_mode') }} as fm

),

readings_per_type as (

    select
        product_type_key,
        cast(count(*) as bigint) as readings
    from {{ ref('fct_sensor_readings') }}
    group by product_type_key

),

events as (

    select
        product_type_key,
        failure_mode_key,
        cast(count(*) as bigint) as failure_events
    from {{ ref('fct_failure_events') }}
    group by product_type_key, failure_mode_key

)

select
    g.product_type_code,
    g.failure_mode_code,
    g.failure_mode_name,
    r.readings,
    coalesce(e.failure_events, 0)                                                     as failure_events,
    {{ rate_per_1000('coalesce(e.failure_events, 0)', 'r.readings') }}                as events_per_1000_readings,
    {{ share_pct('coalesce(e.failure_events, 0)',
                 'sum(coalesce(e.failure_events, 0)) over (partition by g.product_type_code)') }}
                                                                                      as share_of_type_events_pct
from grid as g
inner join readings_per_type as r
    on g.product_type_key = r.product_type_key
left join events as e
    on g.product_type_key = e.product_type_key
   and g.failure_mode_key = e.failure_mode_key
order by g.product_type_code, g.failure_mode_code
