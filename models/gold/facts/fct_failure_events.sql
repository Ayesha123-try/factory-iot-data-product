{#
    GOLD fact: failure events. Grain: one row per (failed reading x failure mode).
    Resolves the many-to-many between readings and failure modes, so a reading that
    failed by both HDF and OSF counts once in each mode but only once as a failure.
#}

select
    {{ surrogate_key(['e.reading_id', 'e.failure_mode_code']) }}  as failure_event_key,
    e.reading_id,
    f.machine_key,
    f.product_type_key,
    {{ surrogate_key(['e.failure_mode_code']) }}                  as failure_mode_key,
    f.tool_wear_min,
    f.torque_nm,
    f.power_w
from {{ ref('slv_failure_events') }} as e
inner join {{ ref('fct_sensor_readings') }} as f
    on e.reading_id = f.reading_id
